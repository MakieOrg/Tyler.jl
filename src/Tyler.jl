module Tyler

using Makie
using LinearAlgebra
using MapTiles
using MapTiles: Tile
using Colors
using Colors: N0f8
using LRUCache
using GeometryBasics
using GeometryBasics: GLTriangleFace, decompose_uv

const TileImage = Matrix{RGB{N0f8}}

struct Map
    provider::MapTiles.AbstractProvider
    figure::Figure
    axis::Axis
    displayed_tiles::Set{MapTiles.Tile}
    plots::Dict{MapTiles.Tile,Any}
    free_tiles::Vector{Makie.Combined}
    fetched_tiles::LRU{Tile,TileImage}
    tiles_being_added::Dict{Tile,Task}
    downloaded_tiles::Channel{Tuple{Tile,TileImage}}
end

function fetch_tile(tyler::Map, tile::Tile)
    return get!(tyler.fetched_tiles, tile) do
        MapTiles.fetchrastertile(tyler.provider, tile)
    end
end

function fetch_tile!(tyler::Map, tile)
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

function Map(minlon, minlat, maxlon, maxlat, zoom=15; figure=Figure(), provider=MapTiles.OpenStreetMapProvider(variant="standard"), cache_size_gb=5)
    axis = Axis(figure[1, 1]; aspect=AxisAspect(1), limits=(minlon, maxlon, minlat, maxlat))
    plots = Dict{Tile,Any}()
    tiles = MapTiles.get_tiles(minlon, minlat, maxlon, maxlat, zoom)
    fetched_tiles = LRU{Tile, Matrix{RGB{N0f8}}}(; maxsize=cache_size_gb * 10^9, by=Base.sizeof)
    free_tiles = Makie.Combined[]
    tiles_being_added = Dict{Tile,Task}()
    downloaded_tiles = Channel{Tuple{Tile,TileImage}}(128)
    tyler = Map(provider, figure, axis, Set(tiles), plots, free_tiles, fetched_tiles, tiles_being_added, downloaded_tiles)
    screen = display(figure)
    @async begin
        while isopen(screen)
            tile, img = take!(downloaded_tiles)
            try
                create_tile_plot!(tyler, tile, img)
            catch e
                @warn "error while creating tile" exception = (e, Base.catch_backtrace())
            end
        end
    end
    queue_tiles!(tyler, tiles)

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
    rect = Rect2f(0, 0, 1, 1)
    points = decompose(Point2f, rect)
    faces = decompose(GLTriangleFace, rect)
    uv = decompose_uv(rect)
    map!(uv -> Vec2f(uv[1], 1 - uv[2]), uv, uv)
    m = GeometryBasics.Mesh(meta(points; uv=uv), faces)
    return mesh!(axis, m; color=image, shading=false)
end

function place_tile!(tyler::Map, tile::Tile, plot)
    bounds = MapTiles.bounds(tile)
    lonmin, lonmax = bounds.X
    latmin, latmax = bounds.Y
    translate!(plot, lonmin, latmin, 0)
    scale!(plot, lonmax - lonmin, latmax - latmin, 0)
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
    place_tile!(tyler, tile, mplot)
end

function queue_tiles!(tyler::Map, tiles)
    for tile in tiles
        fetch_tile!(tyler, tile)
    end
end

function update_tiles!(tyler::Map, limit_rect::Rect)
    min_latlon, max_latlon = extrema(limit_rect)
    zoom = first(tyler.displayed_tiles).zoom
    new_tiles = Set(MapTiles.get_tiles(min_latlon[1], min_latlon[2], max_latlon[1], max_latlon[2], zoom))
    to_add = setdiff(new_tiles, tyler.displayed_tiles)
    to_remove = setdiff(tyler.displayed_tiles, new_tiles)
    remove_tiles!(tyler, to_remove)
    # replace
    empty!(tyler.displayed_tiles)
    union!(tyler.displayed_tiles, new_tiles)

    queue_tiles!(tyler, to_add)
end


end
