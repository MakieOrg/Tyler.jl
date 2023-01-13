module Tyler

using Makie
using LinearAlgebra
using MapTiles
using MapTiles: Tile, TileGrid, web_mercator, wgs84
using TileProviders: TileProviders, AbstractProvider, Provider
using Colors
using Colors: N0f8
using LRUCache
using GeometryBasics
using GeometryBasics: GLTriangleFace, decompose_uv
using MapTiles.GeoFormatTypes: CoordinateReferenceSystemFormat
using Extents
using GeoInterface
using ThreadSafeDicts

const TileImage = Matrix{RGB{N0f8}}

struct Map
    provider::AbstractProvider
    coordinate_system::CoordinateReferenceSystemFormat
    min_tiles::Int
    max_tiles::Int
    zoom::Observable{Int}
    figure::Figure
    axis::Axis
    displayed_tiles::Set{MapTiles.Tile}
    plots::Dict{MapTiles.Tile,Any}
    free_tiles::Vector{Makie.Combined}
    fetched_tiles::LRU{Tile,TileImage}
    tiles_being_added::ThreadSafeDict{Tile,Task}
    downloaded_tiles::Channel{Tuple{Tile,TileImage}}
    display_task::Base.RefValue{Task}
    screen::Makie.MakieScreen
end

# Wait for all tiles to be
function Base.wait(map::Map)
    while !isempty(map.tiles_being_added)
        wait(last(first(map.tiles_being_added)))
    end
end

Base.showable(::MIME"image/png", ::Map) = true
function Base.show(io::IO, m::MIME"image/png", map::Map)
    wait(map)
    show(io, m, map.figure)
end

function Map(rect::Rect, zoom=3, input_cs = wgs84;
        figure=Figure(resolution=(1500, 1500)),
        coordinate_system = MapTiles.web_mercator,
        provider=TileProviders.OpenStreetMap(:Mapnik),
        min_tiles=Makie.automatic,
        max_tiles=Makie.automatic,
        cache_size_gb=5)
    ext = extent(rect)
    tiles = MapTiles.TileGrid(ext, zoom, input_cs)
    fetched_tiles = LRU{Tile, Matrix{RGB{N0f8}}}(; maxsize=cache_size_gb * 10^9, by=Base.sizeof)
    free_tiles = Makie.Combined[]
    tiles_being_added = ThreadSafeDict{Tile,Task}()
    downloaded_tiles = Channel{Tuple{Tile,TileImage}}(128)
    screen = display(figure)
    if isnothing(screen)
        error("please load either GLMakie, WGLMakie or CairoMakie")
    end
    display_task = Base.RefValue{Task}()
    nx, ny = cld.(size(screen), 256)
    if !(min_tiles isa Int)
        min_tiles = fld(nx, 2) * fld(ny, 2)
    end
    if !(max_tiles isa Int)
        max_tiles = nx * ny
    end
    ext_target = MapTiles.project_extent(ext, input_cs, coordinate_system)
    X = ext_target.X
    Y = ext_target.Y
    axis = Axis(figure[1, 1]; aspect=DataAspect(), limits=(X[1], X[2], Y[1], Y[2]))
    plots = Dict{Tile,Any}()
    tyler = Map(
        provider, coordinate_system,
        min_tiles, max_tiles, Observable(zoom),
        figure, axis, Set(tiles), plots, free_tiles,
        fetched_tiles, tiles_being_added, downloaded_tiles,
        display_task, screen
    )
    display_task[] = @async begin
        while isopen(screen)
            tile, img = take!(downloaded_tiles)
            try
                create_tile_plot!(tyler, tile, img)
            catch e
                @warn "error while creating tile" exception = (e, Base.catch_backtrace())
            end
        end
    end

    # Queue tiles to be downloaded & displayed
    foreach(tile -> queue_tile!(tyler, tile), tiles)

    on(axis.finallimits) do rect
        update_tiles!(tyler, rect)
        return
    end
    return tyler
end

function remove_tiles!(tyler::Map, tiles::Set{Tile})
    for tile in tiles
        if haskey(tyler.plots, tile)
            plot = pop!(tyler.plots, tile)
            plot.visible = false
            push!(tyler.free_tiles, plot)
        end
    end
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
    return mesh!(axis.scene, m; color=image, shading=false)
end

function place_tile!(tile::Tile, plot, coordinate_system)
    bounds = MapTiles.extent(tile, coordinate_system)
    xmin, xmax = bounds.X
    ymin, ymax = bounds.Y
    translate!(plot, xmin, ymin, 0)
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
        mplot.visible = true
        mplot.color[] = image
    end
    tyler.plots[tile] = mplot
    place_tile!(tile, mplot, tyler.coordinate_system)
end


function fetch_tile(tyler::Map, tile::Tile)
    return get!(tyler.fetched_tiles, tile) do
        MapTiles.fetchrastertile(tyler.provider, tile)
    end
end

function queue_tile!(tyler::Map, tile)
    queue = tyler.tiles_being_added
    # NO need to start a need task!
    haskey(queue, tile) && return
    queue[tile] = Threads.@spawn begin
        try
            img = fetch_tile(tyler, tile)
            # we may have moved already and the tile doesn't need to be displayed anymore
            if tile in tyler.displayed_tiles
                put!(tyler.downloaded_tiles, (tile, img))
            end
        catch e
            @warn "error while downloading tile" exception = (e, Base.catch_backtrace())
        finally
            delete!(queue, tile)
        end
    end
end

function Extents.extent(rect::Rect2)
    (xmin, ymin), (xmax, ymax) = extrema(rect)
    return Extent(X=(xmin, xmax), Y=(ymin, ymax))
end

function get_tiles(extent::Extent, crs, zoom::Int, min_tiles::Int, max_tiles::Int, tries=1)
    new_tiles = MapTiles.TileGrid(extent, zoom, crs)
    if zoom <= 0 || zoom >= 20 || tries > 10
        return new_tiles, zoom
    end
    if length(new_tiles) > max_tiles
        return get_tiles(extent, crs, max(zoom - 1, 0), min_tiles, max_tiles, tries + 1)
    elseif length(new_tiles) <= min_tiles
        return get_tiles(extent, crs, min(zoom + 1, 20), min_tiles, max_tiles, tries + 1)
    end
    return new_tiles, zoom
end

function update_tiles!(tyler::Map, display_rect::Rect2)
    min_tiles = tyler.min_tiles
    max_tiles = tyler.max_tiles
    new_tiles, new_zoom = get_tiles(extent(display_rect), tyler.coordinate_system, tyler.zoom[], min_tiles, max_tiles)
    tyler.zoom[] = new_zoom
    new_tiles_set = Set(new_tiles)
    to_add = setdiff(new_tiles_set, tyler.displayed_tiles)
    to_remove = setdiff(tyler.displayed_tiles, new_tiles_set)
    remove_tiles!(tyler, to_remove)
    # replace
    empty!(tyler.displayed_tiles)
    union!(tyler.displayed_tiles, new_tiles_set)
    # Queue tiles to be downloaded & displayed
    foreach(tile -> queue_tile!(tyler, tile), to_add)
end

end
