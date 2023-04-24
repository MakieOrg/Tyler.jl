module Tyler

using Makie
using LinearAlgebra
using MapTiles: MapTiles, Tile, TileGrid, web_mercator, wgs84, CoordinateReferenceSystemFormat
using TileProviders: TileProviders, AbstractProvider, geturl, min_zoom, max_zoom
using Colors
using Colors: N0f8
using LRUCache
using GeometryBasics
using GeometryBasics: GLTriangleFace, decompose_uv
using Extents
using GeoInterface
using ThreadSafeDicts
using OrderedCollections
using HTTP
using ImageMagick

const TileImage = Matrix{RGB{N0f8}}

struct Map
    provider::AbstractProvider
    coordinate_system::CoordinateReferenceSystemFormat
    zoom::Observable{Int}
    figure::Figure
    axis::Axis
    displayed_tiles::OrderedSet{Tile}
    plots::Dict{Tile,Any}
    free_tiles::Vector{Makie.Combined}
    fetched_tiles::LRU{Tile,TileImage}
    max_parallel_downloads::Int
    # TODO, use Channel here
    queued_but_not_downloaded::OrderedSet{Tile}
    tiles_being_added::ThreadSafeDict{Tile,Task}
    downloaded_tiles::Channel{Tuple{Tile,TileImage}}
    display_task::Base.RefValue{Task}
    download_task::Base.RefValue{Task}
    screen::Makie.MakieScreen
    depth::Int
    halo::Float64
    scale::Float64
end

# Wait for all tiles to be
function Base.wait(map::Map)
    while true
        if !isempty(map.tiles_being_added)
            wait(last(first(map.tiles_being_added)))
        end
        if !isempty(map.queued_but_not_downloaded)
            sleep(0.001) # we don't have a task to wait on, so we sleep
        end
        # We're done if both are empty!
        if isempty(map.tiles_being_added) && isempty(map.queued_but_not_downloaded)
            return map
        end
    end
end

Base.showable(::MIME"image/png", ::Map) = true
function Base.show(io::IO, m::MIME"image/png", map::Map)
    wait(map)
    Makie.backend_show(map.screen, io::IO, m, map.figure.scene)
end

function Map(extent::Union{Rect,Extent}, input_cs=wgs84;
        resolution=(1000, 1000),
        figure=Figure(; resolution),
        coordinate_system = MapTiles.web_mercator,
        provider=TileProviders.OpenStreetMap(:Mapnik),
        max_parallel_downloads = 16,
        cache_size_gb=5,
        depth=8, halo=0.2, scale=1.0
       )

    fetched_tiles = LRU{Tile, Matrix{RGB{N0f8}}}(; maxsize=cache_size_gb * 10^9, by=Base.sizeof)
    free_tiles = Makie.Combined[]
    tiles_being_added = ThreadSafeDict{Tile,Task}()
    downloaded_tiles = Channel{Tuple{Tile,TileImage}}(128)
    screen = display(figure; title="Tyler (with Makie)")

    # if extent input is a HyperRectangle then convert to type Extent
    extent isa Extent ||  (extent = Extents.extent(extent))

    if isnothing(screen)
        error("please load either GLMakie, WGLMakie or CairoMakie")
    end
    display_task = Base.RefValue{Task}()
    nx, ny = cld.(size(screen), 256)
    download_task = Base.RefValue{Task}()

    ext_target = MapTiles.project_extent(extent, input_cs, coordinate_system)
    X = ext_target.X
    Y = ext_target.Y
    axis = Axis(figure[1, 1]; aspect=DataAspect(), limits=(X[1], X[2], Y[1], Y[2]))
    axis.autolimitaspect = 1
    plots = Dict{Tile,Any}()
    tyler = Map(
        provider, coordinate_system,
        Observable(1),
        figure, axis, OrderedSet{Tile}(), plots, free_tiles,
        fetched_tiles,
        max_parallel_downloads, OrderedSet{Tile}(),
        tiles_being_added, downloaded_tiles,
        display_task, download_task, screen,
        depth, halo, scale
    )
    tyler.zoom[] = get_zoom(tyler, extent)
    download_task[] = @async begin
        while isopen(screen)
            # we dont download all tiles at once, so when one download task finishes, we may want to schedule more downloads:
            if !isempty(tyler.queued_but_not_downloaded)
                queue_tile!(tyler, popfirst!(tyler.queued_but_not_downloaded))
            end
            sleep(0.01)
        end
        empty!(tyler.queued_but_not_downloaded)
        empty!(tyler.displayed_tiles)
    end
    #
    display_task[] = @async begin
        while isopen(screen)
            tile, img = take!(downloaded_tiles)
            try
                create_tile_plot!(tyler, tile, img)
                # fixes on demand renderloop which doesn't pick up all updates!
                if hasfield(typeof(tyler.screen), :requires_update)
                    tyler.screen.requires_update = true
                end
            catch e
                @warn "error while creating tile" exception = (e, Base.catch_backtrace())
            end
        end
    end

    # Queue tiles to be downloaded & displayed
    update_tiles!(tyler, ext_target)

    on(axis.finallimits) do extent
        isopen(screen) || return
        update_tiles!(tyler, extent)
        return
    end
    return tyler
end

function stop_download!(map::Map, tile::Tile)
    # delete!(map.tiles_being_added, tile)
    # TODO can we actually interrupt downloads?
    # Doesn't seem to work this way at least:
    # if haskey(map.tiles_being_added, tile)
    #     task = map.tiles_being_added[tile]
    #     ex = InterruptException()
    #     Base.throwto(task, ex)
    # end
end

function remove_tiles!(map::Map, tiles_being_displayed::OrderedSet{Tile})
    to_remove_plots = setdiff(keys(map.plots), tiles_being_displayed)
    for tile in to_remove_plots
        if haskey(map.plots, tile)
            plot = pop!(map.plots, tile)
            plot.visible = false
            push!(map.free_tiles, plot)
        end
    end
    remove_from_queue = setdiff(map.queued_but_not_downloaded, tiles_being_displayed)
    foreach(t-> delete!(map.queued_but_not_downloaded, t), remove_from_queue)
    to_remove_downloads = setdiff(keys(map.tiles_being_added), tiles_being_displayed)
    foreach(t -> stop_download!(map, t), to_remove_downloads)
end

function create_tileplot!(axis, image)
    # Use a mesh plot until image rotr90 is fixed
    # Also, this will make it easier to subdivide the image mesh
    # To apply some other coordinate transforms
    # use GeometryBasics.Tesselation(rect, (128, 128)) to get a 128x128 subdivied mesh
    rect = Rect2f(0, 0, 1, 1)
    points = decompose(Point2f, rect)
    faces = decompose(GLTriangleFace, rect)
    uv = decompose_uv(rect)
    map!(uv -> Vec2f(uv[1], 1 - uv[2]), uv, uv)
    m = GeometryBasics.Mesh(meta(points; uv=uv), faces)
    # Plot directly into scene to not update limits
    return mesh!(axis.scene, m; color=image, shading=false, inspectable=false)
end

function place_tile!(tile::Tile, plot, coordinate_system)
    bounds = MapTiles.extent(tile, coordinate_system)
    xmin, xmax = bounds.X
    ymin, ymax = bounds.Y
    translate!(plot, xmin, ymin, tile.z - 100)
    scale!(plot, xmax - xmin, ymax - ymin, 0)
    return
end

function create_tile_plot!(tyler::Map, tile::Tile, image::TileImage)
    if haskey(tyler.plots, tile)
        # this shouldn't get called with plots that are already displayed
        @warn "getting tile plot already plotted"
        return tyler.plots[tile]
    end
    if isempty(tyler.free_tiles)
        mplot = create_tileplot!(tyler.axis, image)
    else
        mplot = pop!(tyler.free_tiles)
        mplot.color[] = image
        mplot.visible = true
    end
    tyler.plots[tile] = mplot
    place_tile!(tile, mplot, tyler.coordinate_system)
end

function fetch_tile(tyler::Map, tile::Tile)
    return get!(tyler.fetched_tiles, tile) do
        url = TileProviders.geturl(tyler.provider, tile.x, tile.y, tile.z)
        result = HTTP.get(url; retry=false, readtimeout=4, connect_timeout=4)
        return ImageMagick.readblob(result.body)
    end
end

function queue_tile!(tyler::Map, tile)
    queue = tyler.tiles_being_added
    # NO need to start a need task!
    haskey(queue, tile) && return
    if length(queue) > tyler.max_parallel_downloads
        # queue them for being downloaded once all other downloads are finished
        # This helps not spamming the server and also gives a chance to delete
        # the download request when e.g. zooming out really fast
        push!(tyler.queued_but_not_downloaded, tile)
    else
        queue[tile] = @async try
            # TODO, i think we should better check if we want to display this tile,
            # even though we just scheduled it
            if (tile in tyler.displayed_tiles)
                img = fetch_tile(tyler, tile)
                # we may have moved already and the tile doesn't need to be displayed anymore
                if tile in tyler.displayed_tiles
                    put!(tyler.downloaded_tiles, (tile, img))
                end
            end
        catch e
            if !(e isa InterruptException)
                @warn "error while downloading tile" exception=e
            end
            # if the tile still needs to be displayed, reque it
            # TODO should only retry for certain errors
            if tile in tyler.displayed_tiles
                @info("requeing after download error!")
                delete!(queue, tile)
                queue_tile!(tyler, tile)
            end
        finally
            delete!(queue, tile)
        end
    end
end

function Extents.extent(rect::Rect2)
    (xmin, ymin), (xmax, ymax) = extrema(rect)
    return Extent(X=(xmin, xmax), Y=(ymin, ymax))
end

TileProviders.max_zoom(tyler::Map) = Int(max_zoom(tyler.provider))
TileProviders.min_zoom(tyler::Map) = Int(min_zoom(tyler.provider))

function get_zoom(tyler::Map, area)
    res = size(tyler.axis.scene) .* tyler.scale
    clamp(z_index(area, (X=res[2], Y=res[1]), tyler.coordinate_system), min_zoom(tyler), max_zoom(tyler))
end

function update_tiles!(tyler::Map, area::Union{Rect,Extent})
    area = typeof(area) <: Rect ? Extents.extent(area) : area
    # `depth` determines the number of layers below the current
    # layer to load. Tiles are downloaded in order from lowest to highest zoom.
    depth = tyler.depth

    # Calculate the zoom level
    zoom = get_zoom(tyler, area)
    tyler.zoom[] = zoom

    # And the z layers we will plot
    layer_range = max(min_zoom(tyler), zoom - depth):zoom
    # Get the tiles around the mouse first
    xpos, ypos = mouse_pos = Makie.mouseposition(tyler.axis.scene)
    xspan = (area.X[2] - area.X[1]) * 0.01
    yspan = (area.Y[2] - area.Y[1]) * 0.01
    mouse_area = Extents.Extent(X=(xpos - xspan, xpos + xspan), Y=(ypos - yspan, ypos + yspan))
    # Make a halo around the mouse tile to load next, intersecting area so we don't download outside the plot
    mouse_halo_area = grow(mouse_area, 10)
    # Define a halo around the area to download last, so pan/zoom are filled already
    halo_area = grow(area, tyler.halo) # We don't mind that the middle tiles are the same, the OrderedSet will remove them
    # Define all the tiles in the order they will load in
    areas = if Extents.intersects(mouse_halo_area, area)
        mha = Extents.intersect(mouse_halo_area, area)
        if Extents.intersects(mouse_area, area)
            [Extents.intersect(mouse_area, area), mha, area, halo_area]
        else
            [mha, area, halo_area]
        end
    else
        [area, halo_area]
    end

    area_layers = map(layer_range) do z
        map(areas) do ext
            MapTiles.TileGrid(ext, z, tyler.coordinate_system)
        end |> Iterators.flatten
    end |> Iterators.flatten

    # Create the full set of tiles
    # Using an ordered set gives a smoother load than a Set
    new_tiles_set = OrderedSet{Tile}(area_layers)
    # Remove any tiles not in the new set
    remove_tiles!(tyler, new_tiles_set)

    to_add = setdiff(new_tiles_set, tyler.displayed_tiles)

    # replace
    empty!(tyler.displayed_tiles)
    union!(tyler.displayed_tiles, new_tiles_set)

    # Queue tiles to be downloaded & displayed
    foreach(tile -> queue_tile!(tyler, tile), to_add)
end

function z_index(extent::Union{Rect,Extent}, res::NamedTuple, crs)
    # Calculate the number of tiles at each z and get the one
    # closest to the resolution `res`
    target_ntiles = prod(map(r -> r / 256, res))
    tiles_at_z = map(1:24) do z
        length(TileGrid(extent, z, crs))
    end
    return findmin(x -> abs(x - target_ntiles), tiles_at_z)[2]
end

# grow an extent
function grow(area::Union{Rect,Extent}, factor)
    map(Extents.bounds(area)) do axis_bounds
        span = axis_bounds[2] - axis_bounds[1]
        pad = factor * span / 2
        (axis_bounds[1] - pad, axis_bounds[2] + pad)
    end |> Extent
end

function debug_tile!(map::Tyler.Map, tile::Tile)
    plot = linesegments!(map.axis, Rect2f(0, 0, 1, 1), color=:red, linewidth=1)
    Tyler.place_tile!(tile, plot, web_mercator)
end

function debug_tiles!(map::Tyler.Map)
    for tile in m.displayed_tiles
        debug_tile!(m, tile)
    end
end

end
