# don't shift 3d plots
move_in_front!(plot, amount, ::Rect3) = nothing
function move_in_front!(plot, amount, ::Rect2)
    if !hasproperty(plot, :depth_shift)
        translate!(plot, 0, 0, amount)
    else
        plot.depth_shift = -amount / 100f0
    end
end

move_to_back!(plot, amount, ::Rect3) = nothing
function move_to_back!(plot, amount, ::Rect2)
    if !hasproperty(plot, :depth_shift)
        translate!(plot, 0, 0, -amount)
    else
        plot.depth_shift = amount / 100f0
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

config = PlotConfig(
    preprocess = (data) -> data .+ 1,
    postprocess = (plot) -> translate!(plot, 0, 0, 1),
    color = :red
)
lat, lon = (52.395593, 4.884704)
delta = 0.1
extent = Extent(; X=(lon - delta / 2, lon + delta / 2), Y=(lat - delta / 2, lat + delta / 2))
Tyler.Map(extent; provider=Tyler.TileProviders.Esri(:WorldImagery), plot_config=config)
```
"""
PlotConfig(; preprocess=identity, postprocess=identity, plot_attributes...) = PlotConfig(Dict{Symbol,Any}(plot_attributes), preprocess, postprocess)


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
        # If overlap
        if bounds2d in other_bounds2d || other_bounds2d in bounds2d
            if haskey(m.current_tiles, tile)
                # the new plot has priority since it's in the newest current tile set
                remove_plot!(m, other_key)
            elseif haskey(m.current_tiles, other_tile)
                delete!(m.should_get_plotted, key)
                # the existing plot has priority so we skip the new plot
                return true
            else
                # If both are not in current_tiles, we remove the plot farthest away from the current zoom level
                if abs(tile.z - m.zoom[]) <= abs(other_tile.z - m.zoom[])
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
        available_to_remove = setdiff(p_tiles, keys(m.current_tiles))
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

function create_tile_plot!(m::AbstractMap, tile::Tile, data)
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
        mplot = create_tileplot!(cfg, m.axis, data_processed, bounds, (tile, m.crs))
    else
        mplot = pop!(m.unused_plots)
        update_tile_plot!(mplot, cfg, m.axis, data_processed, bounds, (tile, m.crs))
    end

    if haskey(m.current_tiles, tile)
        move_in_front!(mplot, abs(m.zoom[] - tile.z), bounds)
    else
        move_to_back!(mplot, abs(m.zoom[] - tile.z), bounds)
    end

    # Always move new plots to the front
    mplot.visible = true
    get_postprocess(cfg)(mplot)
    m.plots[key] = (mplot, tile, bounds)
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

function create_tileplot!(config::PlotConfig, axis::AbstractAxis, data::ElevationData, bounds::Rect, tile_crs)
    # not so elegant with empty array, we may want to make this a bit nicer going forward
    color = isempty(data.color) ? (;) : (color=data.color,)
    mini, maxi = extrema(bounds)
    p = Makie.surface!(
        axis.scene,
        (mini[1], maxi[1]), (mini[2], maxi[2]), data.elevation;
        color...,
        shading=Makie.NoShading,
        inspectable=false,
        colorrange=data.elevation_range,
        config.attributes...
    )
    return p
end

function update_tile_plot!(plot::Surface, ::PlotConfig, ::AbstractAxis, data::ElevationData, bounds::Rect, tile_crs)
    mini, maxi = extrema(bounds)
    plot.args[1].val = (mini[1], maxi[1])
    plot.args[2].val = (mini[2], maxi[2])
    plot[3] = data.elevation
    if !isempty(data.color)
        plot.color = data.color
    end
    return
end

############################
#### Image Data plotting
####

const ImageData = AbstractMatrix{<:Colorant}

function create_tileplot!(config::PlotConfig, axis::AbstractAxis, data::ImageData, bounds::Rect, tile_crs)
    mini, maxi = extrema(bounds)
    plot = Makie.image!(
        axis.scene,
        (mini[1], maxi[1]), (mini[2], maxi[2]), rotr90(data);
        inspectable=false,
        config.attributes...
    )
    return plot
end

function update_tile_plot!(plot::Makie.Image, ::PlotConfig, axis::AbstractAxis, data::ImageData, bounds::Rect, tile_crs)
    mini, maxi = extrema(bounds)
    plot[1] = (mini[1], maxi[1])
    plot[2] = (mini[2], maxi[2])
    plot[3] = rotr90(data)
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

function create_tileplot!(config::PlotConfig, axis::AbstractAxis, data::PointCloudData, ::Rect, tile_crs)
    p = Makie.scatter!(
        axis.scene, data.points;
        color=data.color,
        marker=Makie.FastPixel(),
        markersize=data.msize,
        markerspace=:data,
        fxaa=false,
        inspectable=false,
        config.attributes...
    )
    return p
end

function update_tile_plot!(plot::Makie.Scatter, ::PlotConfig, ::AbstractAxis, data::PointCloudData, bounds::Rect, tile_crs)
    plot.color.val = data.color
    plot[1] = data.points
    plot.markersize = data.msize
    return
end

struct MeshScatterPlotconfig <: AbstractPlotConfig
    plcfg::PlotConfig
end
MeshScatterPlotconfig(args...; attr...) = MeshScatterPlotconfig(PlotConfig(args...; attr...))
get_preprocess(config::AbstractPlotConfig) = get_preprocess(config.plcfg)
get_postprocess(config::AbstractPlotConfig) = get_postprocess(config.plcfg)

function create_tileplot!(config::MeshScatterPlotconfig, axis::AbstractAxis, data::PointCloudData, ::Rect, tile_crs)
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

function update_tile_plot!(plot::Makie.MeshScatter, ::MeshScatterPlotconfig, ::AbstractAxis, data::PointCloudData, bounds::Rect, tile_crs)
    plot.color = data.color
    plot[1] = data.points
    plot.markersize = data.msize
    return
end



############################
#### Debug tile plotting (image only for now)
####

struct DebugPlotConfig <: AbstractPlotConfig
    attributes::Dict{Symbol,Any}
end

DebugPlotConfig(; plot_attributes...) = DebugPlotConfig(Dict{Symbol,Any}(plot_attributes))

function create_tileplot!(config::DebugPlotConfig, axis::AbstractAxis, data::ImageData, bounds::Rect, tile_crs)
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

function update_tile_plot!(plot::Makie.Poly, ::DebugPlotConfig, axis::AbstractAxis, data::ImageData, bounds::Rect, tile_crs)
    plot[1] = bounds
    plot.color = reverse(data; dims=1)
    return
end
