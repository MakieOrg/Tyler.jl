# don't shift 3d plots
move_in_front!(plot, amount, ::Rect3) = nothing
function move_in_front!(plot, amount, ::Rect2)
    if !hasproperty(plot, :depth_shift)
        translate!(plot, 0, 0, amount)
    else
        plot.depth_shift = -amount / 10000f0
    end
end

move_to_back!(plot, amount, ::Rect3) = nothing
function move_to_back!(plot, amount, ::Rect2)
    if !hasproperty(plot, :depth_shift)
        translate!(plot, 0, 0, -amount)
    else
        plot.depth_shift = amount / 10000f0
    end
end

function move_z(m::AbstractMap, plot, tile::Tile, bounds::Rect3)
    # 3D elevation tiles: bias finer-LOD foreground tiles toward the camera
    # via depth_shift, so at LOD boundaries the finer tile always wins the
    # depth test. Without this, the slight triangle-interpolation mismatch
    # between a z=N tile's edge (257 samples) and the adjacent z=N+1 tiles'
    # edges (514 samples) shows up as the speckled / zigzag artifact along
    # the boundary that looks like z-fighting.
    #
    # Only apply depth_shift to Surface plots — Scatter (pointclouds) and
    # other 3D plot types don't have the same LOD-boundary mismatch problem
    # and on AMD drivers we've seen depth_shift writes on FastPixel scatter
    # plots correlate with GPU context loss.
    z_ref = m.zoom[]
    if haskey(m.foreground_tiles, tile)
        plot.visible = true
        if plot isa Makie.Surface
            plot.depth_shift = Float32(z_ref - tile.z) / 10000f0
        end
    elseif z_ref >= tile.z
        plot.visible = true
        if plot isa Makie.Surface
            plot.depth_shift = Float32(z_ref - tile.z + 30) / 10000f0
        end
    else
        plot.visible = false
    end
    return
end
function move_z(m::AbstractMap, plot, tile::Tile, bounds::Rect2)
    # Keep every plot visible and rely on depth_shift to layer them: finer
    # tiles in front, coarser tiles behind. The previous version hid any
    # tile with z > m.zoom[], which caused a visible blink on zoom-out — the
    # just-foreground finer tiles vanished before the coarser ones could
    # take their place. Leaving them visible as a high-res overlay until
    # cull_plots! reclaims them removes the blink entirely.
    plot.visible = true
    z_ref = m.zoom[]
    if haskey(m.foreground_tiles, tile)
        plot.depth_shift = 0f0
    elseif tile.z > z_ref
        # Was foreground before a zoom-out — keep as fine overlay on top so
        # the new (coarser) foreground doesn't blink to lower-res while it
        # takes over the screen.
        move_to_back!(plot, -(tile.z - z_ref), bounds)
    else
        # Coarser fallback — push behind everything finer.
        move_to_back!(plot, 30 - tile.z, bounds)
    end
end

struct PlotConfig <: AbstractPlotConfig
    attributes::Dict{Symbol, Any}
    preprocess::Function
    postprocess::Function
end

"""
    PlotConfig(; preprocess=identity, postprocess=identity, plot_attributes...)

Creates a `PlotConfig` object to influence how tiles are being plotted.
* preprocess(tile_data): Function to preprocess the data before plotting. For a tile provider returning image data, preprocess will be called on the image data before plotting.
* postprocess(tile_data): Function to mutate the plot object after creation. Can be used like this: `(plot)-> translate!(plot, 0, 0, 1)`.
* plot_attributes: Additional attributes to pass to the plot

## Example

```julia
using Tyler, GLMakie
using Colors

config = Tyler.PlotConfig(
    preprocess = (data) -> RGBf.(Colors.red.(data), 0, 0), # extract only the red channel of the data
    postprocess = (plot) -> translate!(plot, 0, 0, 1),
)
lat, lon = (52.395593, 4.884704)
delta = 0.1
extent = Extent(; X=(lon - delta / 2, lon + delta / 2), Y=(lat - delta / 2, lat + delta / 2))
Tyler.Map(extent; provider=Tyler.TileProviders.Esri(:WorldImagery), plot_config=config)
```
"""
PlotConfig(; preprocess=identity, postprocess=identity, plot_attributes...) =
    PlotConfig(Dict{Symbol,Any}(plot_attributes), preprocess, postprocess)


function get_bounds(tile::Tile, data, crs)
    bounds = MapTiles.extent(tile, crs)
    return to_rect(bounds)
end

function remove_plot!(m::Map, key::String)
    if !haskey(m.plots, key)
        @warn "deleting non-existing plot"
        delete!(m.should_get_plotted, key)
        return
    end
    plot, _, _ = m.plots[key]
    plot.visible = false
    delete!(m.plots, key)
    delete!(m.should_get_plotted, key)
    push!(m.unused_plots, plot)
end

get_preprocess(config) = identity
get_preprocess(config::PlotConfig) = config.preprocess
get_postprocess(config) = identity
get_postprocess(config::PlotConfig) = config.postprocess


function filter_overlapping!(m::Map, bounds::Rect2, tile, key)
    return false
    # dont filter for 2d plots
end

function filter_overlapping!(m::Map, bounds::Rect3, tile, key)
    # for 3d meshes, we need to remove any plot in the same 2d area
    bounds2d = Rect2d(bounds)
    for (other_key, (plot, other_tile, other_bounds)) in copy(m.plots)
        other_bounds2d = Rect2d(other_bounds)
        # If overlap (one contains the other — parent/child case)
        if bounds2d in other_bounds2d || other_bounds2d in bounds2d
            new_in_fg   = haskey(m.foreground_tiles, tile)
            other_in_fg = haskey(m.foreground_tiles, other_tile)
            if new_in_fg && other_in_fg
                # Both wanted (e.g. SSE mixed-LOD): keep the finer tile,
                # remove the coarser. This avoids z-fighting between a child
                # and its still-rendered parent when both are simultaneously
                # in the foreground set.
                if tile.z > other_tile.z
                    remove_plot!(m, other_key)
                elseif other_tile.z > tile.z
                    delete!(m.should_get_plotted, key)
                    return true
                else
                    # same zoom and overlapping: latest wins (the previous
                    # behaviour for matching-LOD updates)
                    remove_plot!(m, other_key)
                end
            elseif new_in_fg
                # only the new tile is in the current set — it wins
                remove_plot!(m, other_key)
            elseif other_in_fg
                # only the existing plot is in the current set — keep it
                delete!(m.should_get_plotted, key)
                return true
            else
                # Neither wanted: keep whichever is closer to m.zoom[],
                # falling back to finer if tied.
                d_new = abs(tile.z - m.zoom[])
                d_old = abs(other_tile.z - m.zoom[])
                if d_new < d_old || (d_new == d_old && tile.z >= other_tile.z)
                    remove_plot!(m, other_key)
                else
                    delete!(m.should_get_plotted, key)
                    return true
                end
            end
        end
    end
    return false
end

function cull_plots!(m::Map)
    if length(m.plots) >= (m.max_plots - 1)
        # remove the oldest plot
        p_tiles = plotted_tiles(m)
        available_to_remove = setdiff(p_tiles, keys(m.foreground_tiles))
        sort!(available_to_remove, by=tile -> abs(tile.z - m.zoom[]))
        n_avail = length(available_to_remove)
        need_to_remove = min(n_avail, length(m.plots) - m.max_plots)
        to_remove = available_to_remove[1:need_to_remove]
        for tile in to_remove
            plot_key = remove_unused!(m, tile)
            if !isnothing(plot_key)
                remove_plot!(m, plot_key[2])
            end
        end
    end
end

function create_tyler_plot!(m::AbstractMap, tile::Tile, data)
    # For providers which have to map the same data to different tiles
    # Or providers that have e.g. additional parameters like a date
    # the url is a much better key than the tile itself
    # TODO, should we instead have custom tiles for certain provider?
    key = tile_key(m.provider, tile)
    # This can happen for tile providers with overlapping data that doesn't map 1:1 to tiles
    if haskey(m.plots, key)
        delete!(m.should_get_plotted, key)
        return
    end

    cfg = m.plot_config
    data_processed = get_preprocess(cfg)(data)
    bounds = get_bounds(tile, data_processed, m.crs)

    this_got_filtered = filter_overlapping!(m, bounds, tile, key)
    this_got_filtered && return # skip plotting if it overlaps with a more important plot

    # Cull plots over plot limit
    cull_plots!(m)

    if isempty(m.unused_plots)
        mplot = create_tileplot!(cfg, m.axis, m, data_processed, bounds, (tile, m.crs))
    else
        mplot = pop!(m.unused_plots)
        update_tile_plot!(mplot, cfg, m.axis, m, data_processed, bounds, (tile, m.crs))
    end

    # Always move new plots to the front
    mplot.visible = true
    get_postprocess(cfg)(mplot)
    m.plots[key] = (mplot, tile, bounds)
    # Tile arrivals can land between two update_tiles! calls, so depth_shift
    # starts at Makie's default (0) and would tie with the foreground tiles
    # until the next update_tiles!. Set the correct shift immediately based
    # on the current m.zoom + foreground_tiles.
    move_z(m, mplot, tile, bounds)
    return
end

############################
#### Elevation Data plotting
####

struct ElevationData
    elevation::AbstractMatrix{<: Number}
    color::AbstractMatrix{<: Colorant}
    elevation_range::Vec2d
end

function Base.map(f::Function, data::ElevationData)
    return ElevationData(
        map(f, data.elevation),
        data.color,
        data.elevation_range
    )
end

function get_bounds(tile::Tile, data::ElevationData, crs)
    ext = MapTiles.extent(tile, crs)
    mini, maxi = extrema(data.elevation)
    origin = Vec3d(ext.X[1], ext.Y[1], mini)
    w = Vec3d(ext.X[2] - ext.X[1], ext.Y[2] - ext.Y[1], maxi - mini)
    return Rect3d(origin, w)
end

# Currently a no-op. Proper terrain skirts require *additional* downward
# geometry below each tile's edge, not modification of edge vertices: lowering
# the boundary row/col turns every tile edge into a visible V-notch where the
# surface dips and rises again. With Makie.surface!'s grid geometry there is
# no way to add extra triangles, so for now we rely on adjacent same-LOD tiles
# sharing exact boundary samples (no crack) and accept small cracks at the
# rare LOD-transition boundaries in SSE mode. A proper skirt implementation
# would switch elevation tiles from surface! to mesh! with explicit skirt
# triangles — left for a future change.
with_skirt(elev::AbstractMatrix{<:Real}) = elev

function create_tileplot!(
    config::PlotConfig, axis::AbstractAxis, m, data::ElevationData, bounds::Rect, tile_crs
)
    # not so elegant with empty array, we may want to make this a bit nicer going forward
    color = isempty(data.color) ? (;) : (color=data.color,)
    mini, maxi = extrema(bounds)
    uv_transform = isempty(data.color) ? Makie.automatic : Mat{2,3,Float32}(0, 1, 1, 0, 0, 0)
    p = Makie.surface!(
        axis.scene,
        (mini[1], maxi[1]), (mini[2], maxi[2]), with_skirt(data.elevation);
        color...,
        uv_transform = uv_transform,
        shading=Makie.NoShading,
        inspectable=false,
        colorrange=data.elevation_range,
        config.attributes...
    )
    return p
end

function update_tile_plot!(
    plot::Surface, ::PlotConfig, ::AbstractAxis, m, data::ElevationData, bounds::Rect, tile_crs
)
    mini, maxi = extrema(bounds)
    cd = !isempty(data.color) ? (color=data.color,) : (;)
    Makie.update!(plot, (mini[1], maxi[1]), (mini[2], maxi[2]), with_skirt(data.elevation); cd...)
    return
end

############################
#### Image Data plotting
####

const ImageData = AbstractMatrix{<:Colorant}

function create_tileplot!(
    config::PlotConfig, axis::AbstractAxis, m, data::ImageData, bounds::Rect, (tile, crs)
)
    mini, maxi = extrema(bounds)
    plot = Makie.image!(
        axis.scene,
        (mini[1], maxi[1]), (mini[2], maxi[2]), data;
        uv_transform=Mat{2,3,Float32}(0, 1, 1, 0, 0, 0),
        inspectable=false,
        config.attributes...
    )
    translate!(plot, 0, 0, -10)
    return plot
end

function update_tile_plot!(
    plot::Makie.Image, ::PlotConfig, axis::AbstractAxis, m, data::ImageData, bounds::Rect, tile_crs
)
    mini, maxi = extrema(bounds)
    Makie.update!(plot, (mini[1], maxi[1]), (mini[2], maxi[2]), data)
    return
end

############################
#### PointCloudData Data plotting
####

struct PointCloudData
    points::AbstractVector{<:Point3}
    color::AbstractVector{<:Union{Colorant, Number}}
    bounds::Rect3d
    msize::Float32
end

get_bounds(::Tile, data::PointCloudData, crs) = data.bounds

function Base.map(f::Function, data::PointCloudData)
    return PointCloudData(
        map(f, data.points),
        data.color,
        data.bounds,
        data.msize
    )
end

function create_tileplot!(
    config::PlotConfig, axis::AbstractAxis, m, data::PointCloudData, ::Rect, tile_crs
)
    # CRITICAL: `markerspace=:data` combined with FastPixel marker crashes
    # GLMakie's draw_pixel_scatter shader path on AMD drivers (and produces
    # severe artifacts on other drivers / in CI). The shader needs to convert
    # data-space marker size to pixel size every frame using the projection
    # matrix, and with web-mercator coordinates in the millions of metres the
    # Float32 precision loss produces NaN/Inf gl_PointSize → GPU context loss.
    # `:pixel` keeps marker size in screen-space (so zooming doesn't change
    # the visual point size) but avoids the unstable per-frame conversion.
    p = Makie.scatter!(
        axis.scene, data.points;
        color=data.color,
        marker=Makie.FastPixel(),
        markersize=data.msize,
        markerspace=:pixel,
        fxaa=false,
        inspectable=false,
        transparency=true,
        config.attributes...
    )
    return p
end

function update_tile_plot!(
    plot::Makie.Scatter, ::PlotConfig, ::AbstractAxis, m, data::PointCloudData, bounds::Rect, tile_crs
)
    Makie.update!(plot, data.points; color=data.color, markersize=data.msize)
    return
end

struct MeshScatterPlotconfig <: AbstractPlotConfig
    plcfg::PlotConfig
end
MeshScatterPlotconfig(args...; attr...) = MeshScatterPlotconfig(PlotConfig(args...; attr...))
get_preprocess(config::AbstractPlotConfig) = get_preprocess(config.plcfg)
get_postprocess(config::AbstractPlotConfig) = get_postprocess(config.plcfg)

function create_tileplot!(
    config::MeshScatterPlotconfig, axis::AbstractAxis, m, data::PointCloudData, ::Rect, tile_crs
)
    m = Rect3f(Vec3f(0), Vec3f(1))
    p = Makie.meshscatter!(
        axis.scene, data.points;
        color=data.color,
        marker=m,
        markersize=data.msize,
        inspectable=false,
        config.plcfg.attributes...
    )
    return p
end

function update_tile_plot!(
    plot::Makie.MeshScatter, ::MeshScatterPlotconfig, ::AbstractAxis, m, data::PointCloudData, bounds::Rect, tile_crs
)
    Makie.update!(plot, data.points; color=data.color, markersize=data.msize)
    return
end


############################
#### Debug tile plotting (image only for now)
####

struct DebugPlotConfig <: AbstractPlotConfig
    attributes::Dict{Symbol,Any}
end
DebugPlotConfig(; plot_attributes...) =
    DebugPlotConfig(Dict{Symbol,Any}(plot_attributes))

function create_tileplot!(
    config::DebugPlotConfig, axis::AbstractAxis, m, data::ImageData, bounds::Rect, tile_crs
)
    plot = Makie.poly!(
        axis.scene,
        bounds;
        color=reverse(data; dims=1),
        strokewidth=2,
        strokecolor=:black,
        inspectable=false,
        stroke_depth_shift=-0.01f0,
        config.attributes...
    )
    return plot
end

function update_tile_plot!(
    plot::Makie.Poly, ::DebugPlotConfig, axis::AbstractAxis, m, data::ImageData, bounds::Rect, tile_crs
)
    update!(plot, bounds; color=reverse(data; dims=1))
    return
end
