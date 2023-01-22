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
    min_tiles::Int
    max_tiles::Int
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

function Map(rect::Rect, zoom=15, input_cs = wgs84;
        resolution=(1000, 1000),
        figure=Figure(; resolution),
        coordinate_system = MapTiles.web_mercator,
        provider=TileProviders.OpenStreetMap(:Mapnik),
        min_tiles=Makie.automatic,
        max_tiles=Makie.automatic,
        max_parallel_downloads = 16,
        cache_size_gb=5,
        depth=8, halo=0.5
       )

    fetched_tiles = LRU{Tile, Matrix{RGB{N0f8}}}(; maxsize=cache_size_gb * 10^9, by=Base.sizeof)
    free_tiles = Makie.Combined[]
    tiles_being_added = ThreadSafeDict{Tile,Task}()
    downloaded_tiles = Channel{Tuple{Tile,TileImage}}(128)
    screen = display(figure; title="Tyler (with Makie)")
    if isnothing(screen)
        error("please load either GLMakie, WGLMakie or CairoMakie")
    end
    display_task = Base.RefValue{Task}()
    nx, ny = cld.(size(screen), 256)
    download_task = Base.RefValue{Task}()
    if !(min_tiles isa Int)
        min_tiles = fld(nx, 2) * fld(ny, 2)
    end
    if !(max_tiles isa Int)
        max_tiles = nx * ny
    end
    ext = Extents.extent(rect)
    ext_target = MapTiles.project_extent(ext, input_cs, coordinate_system)
    X = ext_target.X
    Y = ext_target.Y
    axis = Axis(figure[1, 1]; aspect=DataAspect(), limits=(X[1], X[2], Y[1], Y[2]))
    plots = Dict{Tile,Any}()
    tyler = Map(
        provider, coordinate_system,
        min_tiles, max_tiles, Observable(zoom),
        figure, axis, OrderedSet{Tile}(), plots, free_tiles,
        fetched_tiles,
        max_parallel_downloads, OrderedSet{Tile}(),
        tiles_being_added, downloaded_tiles,
        display_task, download_task, screen,
        depth, halo,
    )
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

    on(axis.finallimits) do rect
        isopen(screen) || return
        update_tiles!(tyler, Extents.extent(rect))
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
        @show url
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

function get_tiles(extent::Extent, crs, zoom::Int, min_zoom::Int, max_zoom::Int, min_tiles::Int, max_tiles::Int, tries=1)
    new_tiles = TileGrid(extent, zoom, crs)
    if tries > 10
        return new_tiles, zoom
    end
    if length(new_tiles) > max_tiles
        return get_tiles(extent, crs, max(zoom - 1, min_zoom), min_zoom, max_zoom, min_tiles, max_tiles, tries + 1)
    elseif length(new_tiles) <= min_tiles
        return get_tiles(extent, crs, min(zoom + 1, max_zoom), min_zoom, max_zoom, min_tiles, max_tiles, tries + 1)
    end
    return new_tiles, zoom
end

TileProviders.max_zoom(tyler::Map) = Int(max_zoom(tyler.provider))
TileProviders.min_zoom(tyler::Map) = Int(min_zoom(tyler.provider))

function update_tiles!(tyler::Map, area::Extent)
    min_tiles = tyler.min_tiles
    max_tiles = tyler.max_tiles
    # `depth` determines the number of layers below the current
    # layer to load. Tiles are downloaded in order from lowest to highest zoom.
    depth = tyler.depth

    res = tyler.figure.scene.theme.resolution.val
    @show res
    # Calculate the zoom level
    zoom = clamp(z_index(area, (X=res[2], Y=res[1]), tyler.coordinate_system), min_zoom(tyler), max_zoom(tyler))
    tyler.zoom[] = zoom
    # And the z layers we will plot
    layer_range = max(min_zoom(tyler), zoom - depth):zoom
    # Define a halo around the area to download last, so pan/zoom are filled already
    halo_area = grow(area, tyler.halo + 1) # We don't mind that the middle tiles are the same, the OrderedSet will remove them
    # Define all the tiles
    area_layers = [MapTiles.TileGrid(area, z, tyler.coordinate_system) for z in layer_range]
    halo_layers = [MapTiles.TileGrid(halo_area, z, tyler.coordinate_system) for z in layer_range]

    # Create the full set of tiles
    # Using an ordered set gives a smoother load than a Set
    new_tiles_set = OrderedSet{Tile}(
        Iterators.flatten((
            Iterators.flatten(area_layers), # Visible layers load first, from lowest zoom to highest
            Iterators.flatten(halo_layers), # Halo loads last
        ))
    )
    # Remove any tiles not in the new set
    remove_tiles!(tyler, new_tiles_set)

    to_add = setdiff(new_tiles_set, tyler.displayed_tiles)

    # replace
    empty!(tyler.displayed_tiles)
    union!(tyler.displayed_tiles, new_tiles_set)

    # Queue tiles to be downloaded & displayed
    foreach(tile -> queue_tile!(tyler, tile), to_add)
end

function z_index(extent::Extent, res::NamedTuple, crs::MapTiles.WebMercator)
    ntiles = map(r -> r / 256, res)
    tile_size_X = (extent.X[2] - extent.X[1]) / ntiles.X 
    tile_size_Y = (extent.Y[2] - extent.Y[1]) / ntiles.Y 
    tile_size = (tile_size_X + tile_size_Y) / 2
    z = log2(MapTiles.CE / tile_size)
    return round(Int, z)
end

# grow an extent
function grow(area::Extent, factor)
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
