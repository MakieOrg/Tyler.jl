

struct Halo2DTiling <: FetchingScheme
    depth::Int
    halo::Float64
    pixel_scale::Float64
end

Halo2DTiling(; depth=8, halo=0.2, pixel_scale=2.0) = Halo2DTiling(depth, halo, pixel_scale)

function tile_key(provider::AbstractProvider, tile::Tile)
    return TileProviders.geturl(provider, tile.x, tile.y, tile.z)
end

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
struct Map{Ax<:Makie.AbstractAxis} <: AbstractMap
    provider::AbstractProvider
    figure::Figure
    axis::Ax
    plot_config::AbstractPlotConfig
    # The tile downloader + cacher
    tiles::TileCache
    # The tiles for the current zoom level - we may plot many more than this
    current_tiles::ThreadSafeDict{Tile, Bool}
    # The plots we have created but are not currently visible and can be reused
    unused_plots::Vector{Makie.Plot}
    # All tile plots we're currently plotting
    plots::ThreadSafeDict{String,Tuple{Makie.Plot,Tile, Rect}}
    # All tiles we currently wish to be plotting, but may not yet be downloaded + displayed
    should_be_plotted::ThreadSafeDict{String, Tile}
    display_task::Base.RefValue{Task}

    crs::CoordinateReferenceSystemFormat
    zoom::Observable{Int}
    fetching_scheme::FetchingScheme
    max_zoom::Int
end

setup_axis!(::Makie.AbstractAxis, ext_target) = nothing

function setup_axis!(axis::Axis, ext_target)
    X = ext_target.X
    Y = ext_target.Y
    axis.autolimitaspect = 1
    Makie.limits!(axis, (X[1], X[2]), (Y[1], Y[2]))
    axis.elements[:background].depth_shift[] = 0.1f0
    translate!(axis.elements[:background], 0, 0, -1000)
    axis.elements[:background].color = :transparent
    axis.xgridvisible = false
    axis.ygridvisible = false
    return
end

function Map(extent, extent_crs=wgs84;
        resolution=(1000, 1000),
        figure=Makie.Figure(; size=resolution),
        axis=Makie.Axis(figure[1, 1]; aspect=Makie.DataAspect()),
        plot_config=PlotConfig(),
        provider=TileProviders.OpenStreetMap(:Mapnik),
        crs=MapTiles.web_mercator,
        cache_size_gb=5,
        download_threads=min(1, Threads.nthreads() ÷ 3),
        fetching_scheme=Halo2DTiling(),
        max_zoom=TileProviders.max_zoom(provider)
    )

    # Extent
    # if extent input is a HyperRectangle then convert to type Extent
    extent isa Extent || (extent = Extents.extent(extent))
    ext_target = MapTiles.project_extent(extent, extent_crs, crs)
    setup_axis!(axis, ext_target)

    tiles = TileCache(provider; cache_size_gb=cache_size_gb, download_threads=download_threads)
    downloaded_tiles = tiles.downloaded_tiles

    plots = ThreadSafeDict{String,Tuple{Makie.Plot,Tile,Rect}}()
    should_be_plotted = ThreadSafeDict{String,Tile}()
    current_tiles = ThreadSafeDict{Tile, Bool}()
    unused_plots = Makie.Plot[]
    display_task = Base.RefValue{Task}()

    map = Map(
        provider,

        figure,
        axis,
        plot_config,
        tiles,
        current_tiles,
        unused_plots,
        plots,
        should_be_plotted,
        display_task,

        crs,
        Observable(1),
        fetching_scheme, max_zoom
    )

    map.zoom[] = 0

    display_task[] = @async for (tile, data) in downloaded_tiles
        try
            if isnothing(data)
                # download went wrong or provider doesn't have tile.
                # That means we won't plot this tile and it should not be in the queue anymore
                delete!(map.should_be_plotted, tile_key(map.provider, tile))
            else
                create_tile_plot!(map, tile, data)
            end
        catch e
            @warn "error while creating tile" exception = (e, Base.catch_backtrace())
        end
    end

    tile_reloader(map, ext_target)
    return map
end

# Wait for all tiles to be loaded
function Base.wait(map::AbstractMap)
    # The download + plot loops need a screen to do their work!
    if isnothing(Makie.getscreen(map.figure.scene))
        display(map.figure)
    end
    screen = Makie.getscreen(map.figure.scene)
    isnothing(screen) &&
        error("No screen after display. Wrong backend? Only WGLMakie and GLMakie are supported.")
    return wait(map.tiles)
end

function tile_reloader(map::Map{Axis}, first_area)
    axis = map.axis
    update_tiles!(map, first_area)
    throttled = Makie.Observables.throttle(0.2, axis.finallimits)
    on(axis.scene, throttled) do extent
        update_tiles!(map, extent)
        return
    end
end

function get_tiles_for_area(m::Map{Axis}, scheme::Halo2DTiling, area::Union{Rect,Extent})
    area = typeof(area) <: Rect ? Extents.extent(area) : area
    # `depth` determines the number of layers below the current
    # layer to load. Tiles are downloaded in order from lowest to highest zoom.
    depth = scheme.depth

    # Calculate the zoom level
    zoom = calculate_optimal_zoom(m, area)
    m.zoom[] = zoom

    # And the z layers we will plot
    layer_range = max(min_zoom(m), zoom - depth):zoom
    # Get the tiles around the mouse first
    xpos, ypos = Makie.mouseposition(m.axis.scene)
    xspan = (area.X[2] - area.X[1]) * 0.01
    yspan = (area.Y[2] - area.Y[1]) * 0.01
    mouse_area = Extents.Extent(; X=(xpos - xspan, xpos + xspan), Y=(ypos - yspan, ypos + yspan))
    # Make a halo around the mouse tile to load next, intersecting area so we don't download outside the plot
    mouse_halo_area = grow_extent(mouse_area, 10)
    # Define a halo around the area to download last, so pan/zoom are filled already
    halo_area = grow_extent(area, scheme.halo) # We don't mind that the middle tiles are the same, the OrderedSet will remove them
    # Define all the tiles in the order they will load in
    background_areas = if Extents.intersects(mouse_halo_area, area)
        mha = Extents.intersection(mouse_halo_area, area)
        if Extents.intersects(mouse_area, area)
            [Extents.intersection(mouse_area, area), mha, halo_area]
        else
            [mha, halo_area]
        end
    else
        [halo_area]
    end

    foreground = OrderedSet{Tile}(MapTiles.TileGrid(area, zoom, m.crs))
    background = OrderedSet{Tile}()
    for z in layer_range
        z == zoom && continue
        for ext in background_areas
            union!(background, MapTiles.TileGrid(ext, z, m.crs))
        end
    end
    return foreground, background
end

struct SimpleTiling <: FetchingScheme
end

function get_tiles_for_area(m::Map, ::SimpleTiling, area::Union{Rect,Extent})
    area = typeof(area) <: Rect ? Extents.extent(area) : area
    diag = norm(widths(to_rect(area)))
    # Calculate the zoom level
    zoom = optimal_zoom(m, diag)
    m.zoom[] = zoom
    return OrderedSet{Tile}(MapTiles.TileGrid(area, zoom, m.crs)), OrderedSet{Tile}()
end

function plotted_tiles(m::Map)
    return getindex.(values(m.plots), 2)
end

function queue_plot!(m::Map, tile)
    key = tile_key(m.provider, tile)
    isnothing(key) && return
    m.should_be_plotted[key] = tile
    put!(m.tiles.tile_queue, tile)
    return
end

function update_tiles!(m::Map, arealike)
    # Using an ordered set gives a smoother load than a Set
    new_tiles_set, background_tiles = get_tiles_for_area(m, m.fetching_scheme, arealike)
    # Remove any tiles not in the new set
    currently_plotted = values(m.should_be_plotted)

    to_add = setdiff(new_tiles_set, currently_plotted)
    # We don't add any background tile to the current_tiles, so they stay shifted to the back
    # They get added async, so at this point `to_add` won't be in currently_plotted yet
    will_be_plotted = union(new_tiles_set, currently_plotted)
    # update_tileset!(m, new_tiles_set)

    # replace
    empty!(m.current_tiles)
    for tile in new_tiles_set
        m.current_tiles[tile] = true
    end
    # Move all plots to the back, that aren't in the newest tileset anymore
    for (key, (plot, tile, bounds)) in m.plots
        if haskey(m.current_tiles, tile)
            move_in_front!(plot, abs(m.zoom[] - tile.z), bounds)
        else
            move_to_back!(plot, abs(m.zoom[] - tile.z), bounds)
        end
    end
    # Queue tiles to be downloaded & displayed
    to_add_background = setdiff(background_tiles, will_be_plotted)
    # Remove any item from queue, that isn't in the new set
    cleanup_queue!(m, union(to_add, to_add_background))
    # The unique is needed to avoid tiles referencing the same tile
    # TODO, we should really consider to disallow this for tile providers, currently only allowed because of the PointCloudProvider
    foreach(tile -> queue_plot!(m, tile), unique(t-> tile_key(m.provider, t), to_add))
    foreach(tile -> queue_plot!(m, tile), unique(t-> tile_key(m.provider, t),to_add_background))
end

GeoInterface.crs(map::Map) = map.crs
Extents.extent(map::Map) = Extents.extent(map.axis.finallimits[])

TileProviders.max_zoom(map::Map) = map.max_zoom
TileProviders.min_zoom(map::Map) = Int(min_zoom(map.provider))

function get_resolution(map::Map)
    screen = Makie.getscreen(map.axis.scene)
    return isnothing(screen) ? size(map.axis.scene) .* 1.5 : size(screen.framebuffer)
end

function calculate_optimal_zoom(map::Map, area)
    screen = Makie.getscreen(map.axis.scene)
    res = isnothing(screen) ? size(map.axis.scene) : size(screen.framebuffer)
    return clamp(z_index(area, res, map.crs), min_zoom(map), max_zoom(map))
end
