"""
    Map

    Map(extent, [extent_crs=wgs84]; kw...)

Tylers main object, it plots tiles onto a Makie.jl `Axis`,
downloading and plotting more tiles as you zoom and pan.

# Arguments

-`extent`: the initial extent of the map, as a `GeometryBasics.Rect`
    or an `Extents.Extent` in the projection of `extent_crs`.
-`extent_crs`: Any `GeoFormatTypes` compatible crs, the default is wsg84.

# Keywords

-`resolution`: The figure resolution.
-`figure`: an existing `Makie.Figure` object.
-`crs`: The providers coordinate reference system.
-`provider`: a TileProviders.jl `Provider`.
-`max_parallel_downloads`: limits the attempted simultaneous downloads, with a default of `16`.
-`cache_size_gb`: limits the cache for storing tiles, with a default of `5`.
-`depth`: the number of layers to load when zooming. Lower numbers will be slightly faster
    but have more artefacts. The default is `8`.
-`halo`: The fraction of the width of tiles to add as a halo so that panning is smooth - the
    tiles will already be loaded. The default is `0.2`, which means `0.1` on each side.
-`scale`: a tile scaling factor. Low number decrease the downloads but reduce the resolution.
    The default is `1.0`.
"""
struct Map3D <: AbstractMap
    provider::AbstractProvider
    figure::Figure
    axis::LScene

    tiles::TileCache
    displayed_tiles::OrderedSet{Tile}
    free_tiles::Vector{Makie.Plot}
    plots::Dict{Tile,Makie.Plot}
    display_task::Base.RefValue{Task}

    crs::CoordinateReferenceSystemFormat
    zoom::Observable{Int}
    depth::Int
    halo::Float64
    scale::Float64
    max_zoom::Int
end

using Makie: Vec3f

function Map3D(extent, extent_crs=wgs84;
        resolution=(1000, 1000),
        figure=Makie.Figure(; size=resolution),
        axis=Makie.LScene(figure[1, 1]; show_axis=false),
        provider=TileProviders.OpenStreetMap(:Mapnik),
        crs=web_mercator,
        cache_size_gb=5,
        depth=8,
        halo=0.2,
        scale=2.0,
        max_zoom=TileProviders.max_zoom(provider)
    )
    # Extent
    # if extent input is a HyperRectangle then convert to type Extent
    extent isa Extent || (extent = Extents.extent(extent))
    ext_target = MapTiles.project_extent(extent, extent_crs, crs)
    X = ext_target.X
    Y = ext_target.Y

    tiles = TileCache{Any}(provider; cache_size_gb=cache_size_gb)
    downloaded_tiles = tiles.downloaded_tiles

    plots = Dict{Tile,Any}()
    displayed_tiles = OrderedSet{Tile}()
    free_tiles = Makie.Plot[]
    display_task = Base.RefValue{Task}()
    map = Map3D(
        provider, figure,
        axis,
        tiles,
        displayed_tiles,
        free_tiles,
        plots,
        display_task, crs,
        Observable(1),
        depth, halo, scale, max_zoom
    )

    map.zoom[] = calculate_optimal_zoom(map, extent)

    display_task[] = @async for (tile, img) in downloaded_tiles
        while isnothing(Makie.getscreen(map.axis.scene))
            sleep(0.01)
        end
        screen = Makie.getscreen(map.axis.scene)
        while !isopen(screen)
            sleep(0.01)
        end
        try
            create_tile_plot!(map, tile, img)
            # fixes on demand renderloop which doesn't pick up all updates!
            if hasproperty(screen, :requires_update)
                screen.requires_update = true
            end
        catch e
            @warn "error while creating tile" exception = (e, Base.catch_backtrace())
        end
    end

    # Queue tiles to be downloaded & displayed
    update_tiles!(map, ext_target)

    return map
end


GeoInterface.crs(map::Map3D) = map.crs
Extents.extent(map::Map3D) = Extents.extent(map.axis.scene.theme.limits[])

TileProviders.max_zoom(map::Map3D) = map.max_zoom
TileProviders.min_zoom(map::Map3D) = Int(min_zoom(map.provider))

function calculate_optimal_zoom(map::Map3D, area)
    res = size(map.axis.scene) .* map.scale
    return clamp(z_index(area, (X=res[2], Y=res[1]), map.crs), min_zoom(map), max_zoom(map))
end

function update_tiles!(m::Map3D, area::Union{Rect,Extent})
    area = typeof(area) <: Rect ? Extents.extent(area) : area
    # `depth` determines the number of layers below the current
    # layer to load. Tiles are downloaded in order from lowest to highest zoom.
    depth = m.depth

    # Calculate the zoom level
    zoom = 12
    @show zoom
    m.zoom[] = zoom

    # And the z layers we will plot
    layer_range = max(min_zoom(m), zoom - depth):zoom
#
    area_layers = vec(collect(MapTiles.TileGrid(area, zoom, m.crs)))

    # Create the full set of tiles
    # Using an ordered set gives a smoother load than a Set
    new_tiles_set = OrderedSet{Tile}(area_layers)
    # Remove any tiles not in the new set
    remove_tiles!(m, new_tiles_set)

    to_add = setdiff(new_tiles_set, m.displayed_tiles)
    @show length(to_add)
    # replace
    empty!(m.displayed_tiles)
    union!(m.displayed_tiles, new_tiles_set)

    # Queue tiles to be downloaded & displayed
    foreach(tile -> put!(m.tiles.tile_queue, tile), to_add)
end
