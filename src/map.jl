"""
    Map(extent, [extent_crs=wgs84]; kw...)
    Map(map::Map; ...) # layering another provider on top of an existing map

Tylers main object, it plots tiles onto a Makie.jl `Axis`,
downloading and plotting more tiles as you zoom and pan.
When layering providers over each other with `Map(map::Map; ...)`, you can use `toggle_visibility!(map)` to hide/unhide them.

# Arguments

- `extent`: the initial extent of the map, as a `GeometryBasics.Rect`
    or an `Extents.Extent` in the projection of `extent_crs`.
- `extent_crs`: Any `GeoFormatTypes` compatible crs, the default is wsg84.

# Keywords

- `size`: The figure size.
- `figure`: an existing `Makie.Figure` object.
- `crs`: The providers coordinate reference system.
- `provider`: a TileProviders.jl `Provider`.
- `max_parallel_downloads`: limits the attempted simultaneous downloads, with a default of `16`.
- `cache_size_gb`: limits the cache for storing tiles, with a default of `5`.
- `fetching_scheme=Halo2DTiling()`: The tile fetching scheme. Can be SimpleTiling(), Halo2DTiling(), or Tiling3D().
- `scale`: a tile scaling factor. Low number decrease the downloads but reduce the resolution.
    The default is `0.5`.
- `plot_config`: A `PlotConfig` object to change the way tiles are plotted.
- `max_zoom`: The maximum zoom level to display, with a default of `TileProviders.max_zoom(provider)`.
- `max_plots=400:` The maximum number of plots to keep displayed at the same time.
"""
struct Map{Ax<:Makie.AbstractAxis} <: AbstractMap
    provider::AbstractProvider
    figure::Figure
    axis::Ax
    plot_config::AbstractPlotConfig
    # The tile downloader + cacher
    tiles::TileCache
    # The tiles for the current zoom level - we may plot many more than this
    foreground_tiles::ThreadSafeDict{Tile,Bool}
    # The plots we have created but are not currently visible and can be reused
    unused_plots::Vector{Makie.Plot}
    # All tile plots we're currently plotting
    plots::ThreadSafeDict{String,Tuple{Makie.Plot,Tile,Rect}}
    # All tiles we currently wish to be plotting, but may not yet be downloaded + displayed
    should_get_plotted::ThreadSafeDict{String,Tile}
    display_task::Base.RefValue{Task}

    crs::CoordinateReferenceSystemFormat
    zoom::Observable{Int}
    fetching_scheme::FetchingScheme
    max_zoom::Int
    max_plots::Int
    scale::Float64
end
"""
    Map(m::Map; kw...)
Layering constructor to show another provider on top of an existing map.

## Example
```julia
lat, lon = (52.395593, 4.884704)
delta = 0.01
ext = Rect2f(lon - delta / 2, lat - delta / 2, delta, delta)
m1 = Tyler.Map(ext)
m2 = Tyler.Map(m1; provider=TileProviders.Esri(:WorldImagery), plot_config=Tyler.PlotConfig(alpha=0.5, postprocess=(p-> translate!(p, 0, 0, 1f0))))
m1
```
"""
function Map(m::Map; kw...)
    ax = m.axis
    # Make a copy of the lscene, so we can easier separate the plots.
    ax2 = Axis(ax.parent, ax.layoutobservables, ax.blockscene)
    ax2.scene = Scene(ax.scene; camera=ax.scene.camera, camera_controls=ax.scene.camera_controls)
    setfield!(ax2, :elements, ax.elements)
    setfield!(ax2, :targetlimits, ax.targetlimits)
    setfield!(ax2, :finallimits, ax.finallimits)
    setfield!(ax2, :block_limit_linking, ax.block_limit_linking)
    setfield!(ax2.scene, :float32convert, ax.scene.float32convert)
    return Map(nothing, nothing; figure=m.figure, axis=ax2, kw...)
end
function Map(extent, extent_crs=wgs84;
    size=(1000, 1000),
    figure=Makie.Figure(; size=size),
    axis=(; type = Axis, aspect = DataAspect()),
    plot_config=PlotConfig(),
    provider=TileProviders.OpenStreetMap(:Mapnik),
    crs=MapTiles.web_mercator,
    cache_size_gb=5,
    max_parallel_downloads=1,
    fetching_scheme=Halo2DTiling(),
    max_zoom=TileProviders.max_zoom(provider),
    max_plots=400,
    scale=1)

    # Extent
    # if extent input is a HyperRectangle then convert to type Extent
    ext_target = nothing
    if !isnothing(extent) && !isnothing(extent_crs)
        extent isa Extent || (extent = Extents.extent(extent))
        ext_target = MapTiles.project_extent(extent, extent_crs, crs)
        figure, axis = setup_figure_and_axis!(figure, axis, ext_target, crs)
        setup_attribution!(figure, get_attribution(provider))
    end

    tiles = TileCache(provider; cache_size_gb=cache_size_gb, max_parallel_downloads=max_parallel_downloads)
    downloaded_tiles = tiles.downloaded_tiles

    plots = ThreadSafeDict{String,Tuple{Makie.Plot,Tile,Rect}}()
    should_get_plotted = ThreadSafeDict{String,Tile}()
    foreground_tiles = ThreadSafeDict{Tile,Bool}()
    unused_plots = Makie.Plot[]
    display_task = Base.RefValue{Task}()

    map = Map(
        provider, figure,
        axis,
        plot_config,
        tiles,
        foreground_tiles,
        unused_plots,
        plots,
        should_get_plotted,
        display_task, crs,
        Observable(1),
        fetching_scheme, max_zoom, max_plots, Float64(scale)
    )

    map.zoom[] = 0
    closed = Threads.Atomic{Bool}(false)

    display_task[] = @async for (tile, data) in downloaded_tiles
        closed[] && break
        try
            if isnothing(data)
                # download went wrong or provider doesn't have tile.
                # That means we won't plot this tile and it should not be in the queue anymore
                delete!(map.should_get_plotted, tile_key(map.provider, tile))
            else
                create_tyler_plot!(map, tile, data)
            end
        catch e
            @warn "error while creating tile" exception = (e, Base.catch_backtrace())
        end
    end

    tile_reloader(map)

    on(axis.scene.events.window_open) do open
        if !open && !closed[]
            closed[] = true
            # remove all queued tiles!
            cleanup_queue!(map, OrderedSet{Tile}())
            close(map)
        end
    end
    return map
end

function setup_figure_and_axis!(figure::Makie.Figure, axis, ext_target, crs)
    setup_axis!(axis, ext_target, crs)
    return figure, axis
end
function setup_figure_and_axis!(figure::Makie.Figure, axis_kws_nt::NamedTuple, ext_target, crs)
    axis_kws = Dict(pairs(axis_kws_nt))
    AxisType = pop!(axis_kws, :type, Axis)

    axis = AxisType(figure[1, 1]; axis_kws...)

    setup_axis!(axis, ext_target, crs)

    return figure, axis
end
function setup_figure_and_axis!(figure::GridPosition, axis, ext_target, crs)
    error("""
    You have tried to construct a `Map` at a given grid position, 
    but with a materialized axis of type $(typeof(axis)).  
    
    You can only do this if you let Tyler construct the axis, 
    by passing its parameters as a NamedTuple 
    (like `axis = (; type = Axis, ...)`).
    """)
end
function setup_figure_and_axis!(gridposition::GridPosition, axis_kws_nt::NamedTuple, ext_target, crs)
    figure = _get_parent_figure(gridposition)

    axis_kws = Dict(pairs(axis_kws_nt))
    AxisType = pop!(axis_kws, :type, Axis)

    axis = AxisType(gridposition; axis_kws...)

    setup_axis!(axis, ext_target, crs)

    return figure, axis
end

_get_parent_layout(gp::Makie.GridPosition) = _get_parent_layout(gp.layout)
_get_parent_layout(gp::Makie.GridSubposition) = _get_parent_layout(gp.layout)
_get_parent_layout(gl::Makie.GridLayout) = gl

_get_parent_figure(fig::Makie.Figure) = fig
_get_parent_figure(gl::Makie.GridLayout) = _get_parent_figure(gl.parent)
_get_parent_figure(gp::Makie.GridPosition) = _get_parent_figure(_get_parent_layout(gp.layout))
_get_parent_figure(gp::Makie.GridSubposition) = _get_parent_figure(_get_parent_layout(gp.layout))

setup_axis!(::Makie.AbstractAxis, ext_target, crs) = nothing
function setup_axis!(axis::Axis, ext_target, crs)
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

function setup_attribution!(figure, attribution)
    Box(figure[1,1], color=(:white, 0.85),
        tellheight=false, tellwidth=false,
        valign=0, halign=0.5,
        height=15, cornerradius=2,
        strokewidth=0, strokecolor=:transparent
        )
    Label(figure[1,1], rich("Powered by ", color=:grey15,
        rich("Tyler.jl ", color="deepskyblue3", font=:bold),
            rich("| Map data - "*attribution, color=:grey8, font=:regular), fontsize=12);
        tellheight=false, tellwidth=false, valign=0, halign=0.5)
end

toggle_visibility!(m::Map) = m.axis.scene.visible[] = !m.axis.scene.visible[]

function tile_reloader(map::Map{Axis})
    axis = map.axis
    throttled = Makie.Observables.throttle(0.2, axis.finallimits)
    on(axis.scene, throttled; update=true) do extent
        update_tiles!(map, extent)
        return
    end
end

function plotted_tiles(m::Map)
    return getindex.(values(m.plots), 2)
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

# Package interface methods

GeoInterface.crs(map::Map) = map.crs
Extents.extent(map::Map) = Extents.extent(map.axis.finallimits[])

TileProviders.max_zoom(map::Map) = map.max_zoom
TileProviders.min_zoom(map::Map) = Int(min_zoom(map.provider))

function get_attribution(provider)
    _attribution = if haskey(provider.options, :attribution)
        return provider.options[:attribution]
    else
        return ""
    end
    return _attribution
end

# Base methods

Base.showable(::MIME"image/png", ::AbstractMap) = true

function Base.show(io::IO, m::MIME"image/png", map::AbstractMap)
    wait(map)
    Makie.show(io, m, map.figure.scene)
end

function Base.display(map::AbstractMap)
    wait(map)
    Base.display(map.figure.scene)
end

function Base.close(m::Map)
    cleanup_queue!(m, OrderedSet{Tile}())
    empty!(m.foreground_tiles)
    empty!(m.unused_plots)
    empty!(m.plots)
    empty!(m.should_get_plotted)
    close(m.tiles)
end
function Base.wait(m::AbstractMap; timeout=50)
    # The download + plot loops need a screen to do their work!
    if isnothing(Makie.getscreen(m.figure.scene))
        screen = display(m.figure.scene)
    end
    screen = Makie.getscreen(m.figure.scene)
    isnothing(screen) && error("No screen after display.")
    wait(m.tiles; timeout=timeout)
    start = time()
    while true
        tile_keys = Set(tile_key.((m.provider,), keys(m.foreground_tiles)))
        if all(k -> haskey(m.plots, k), tile_keys)
            break
        end
        if time() - start > timeout
            @warn "Timeout waiting for all tiles to be plotted"
            break
        end
        sleep(0.01)
    end
    return m
end