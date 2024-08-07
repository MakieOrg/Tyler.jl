
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
    current_tiles::ThreadSafeDict{Tile,Bool}
    # The plots we have created but are not currently visible and can be reused
    unused_plots::Vector{Makie.Plot}
    # All tile plots we're currently plotting
    plots::ThreadSafeDict{String,Tuple{Makie.Plot,Tile,Rect}}
    # All tiles we currently wish to be plotting, but may not yet be downloaded + displayed
    should_be_plotted::ThreadSafeDict{String,Tile}
    display_task::Base.RefValue{Task}

    crs::CoordinateReferenceSystemFormat
    zoom::Observable{Int}
    fetching_scheme::FetchingScheme
    max_zoom::Int
    max_plots::Int
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

function Map3D(m::Map; kw...)
    ax = m.axis
    # Make a copy of the lscene, so we can easier separate the plots.
    ax2 = LScene(ax.parent, ax.layoutobservables, ax.blockscene)
    ax2.scene = Scene(ax.scene; camera=ax.scene.camera, camera_controls=ax.scene.camera_controls)
    return Map3D(nothing, nothing; figure=m.figure, axis=ax2, kw...)
end

toggle_visibility!(m::Map) = m.axis.scene.visible[] = !m.axis.scene.visible[]

function Map(extent, extent_crs=wgs84;
    size=(1000, 1000),
    figure=Makie.Figure(; size=size),
    axis=Makie.Axis(figure[1, 1]; aspect=Makie.DataAspect()),
    plot_config=PlotConfig(),
    provider=TileProviders.OpenStreetMap(:Mapnik),
    crs=MapTiles.web_mercator,
    cache_size_gb=5,
    download_threads=min(1, Threads.nthreads() ÷ 3),
    fetching_scheme=Halo2DTiling(),
    max_zoom=TileProviders.max_zoom(provider),
    max_plots=400)

    # Extent
    # if extent input is a HyperRectangle then convert to type Extent
    ext_target = nothing
    if !isnothing(extent) && !isnothing(extent_crs)
        extent isa Extent || (extent = Extents.extent(extent))
        ext_target = MapTiles.project_extent(extent, extent_crs, crs)
        setup_axis!(axis, ext_target)
    end

    tiles = TileCache(provider; cache_size_gb=cache_size_gb, download_threads=download_threads)
    downloaded_tiles = tiles.downloaded_tiles

    plots = ThreadSafeDict{String,Tuple{Makie.Plot,Tile,Rect}}()
    should_be_plotted = ThreadSafeDict{String,Tile}()
    current_tiles = ThreadSafeDict{Tile,Bool}()
    unused_plots = Makie.Plot[]
    display_task = Base.RefValue{Task}()

    map = Map(
        provider, figure,
        axis,
        plot_config,
        tiles,
        current_tiles,
        unused_plots,
        plots,
        should_be_plotted,
        display_task, crs,
        Observable(1),
        fetching_scheme, max_zoom, max_plots
    )

    map.zoom[] = 0
    closed = Threads.Atomic{Bool}(false)

    display_task[] = @async for (tile, data) in downloaded_tiles
        closed[] && break
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

    on(axis.scene.events.window_open) do open
        if !open && !closed[]
            closed[] = true
            # remove all queued tiles!
            cleanup_queue!(map, OrderedSet{Tile}())
        end
    end
    return map
end

# Wait for all tiles to be loaded
function Base.wait(map::AbstractMap)
    # The download + plot loops need a screen to do their work!
    if isnothing(Makie.getscreen(map.figure.scene))
        display(map.figure.scene)
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

GeoInterface.crs(map::Map) = map.crs
Extents.extent(map::Map) = Extents.extent(map.axis.finallimits[])

TileProviders.max_zoom(map::Map) = map.max_zoom
TileProviders.min_zoom(map::Map) = Int(min_zoom(map.provider))

Base.showable(::MIME"image/png", ::AbstractMap) = true

function Base.show(io::IO, m::MIME"image/png", map::AbstractMap)
    wait(map)
    Makie.show(io, m, map.figure.scene)
end

function Base.display(map::AbstractMap)
    wait(map)
    Base.display(map.figure.scene)
end


function remove_unused!(m::AbstractMap, tile::Tile)
    return remove_unused!(m, tile_key(m.provider, tile))
end

function remove_unused!(m::AbstractMap, key::String)
    plot_tile = get(m.plots, key, nothing)
    if !isnothing(plot_tile)
        plot, tile, bounds = plot_tile
        move_to_back!(plot, abs(m.zoom[] - tile.z), bounds)
        return plot, key
    end
    return nothing
end

function cleanup_queue!(m::AbstractMap, to_keep::OrderedSet{Tile})
    queue = m.tiles.tile_queue
    lock(queue) do
        queued = queue.data
        filter!(queued) do tile
            if !(tile in to_keep)
                Base._increment_n_avail(queue, -1)
                return false
            else
                return true
            end
        end
    end
end
