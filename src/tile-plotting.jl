# don't shift 3d plots
move_in_front!(plot, bounds::Rect3) = nothing
function move_in_front!(plot, bounds::Rect2)
    if !hasproperty(plot, :depth_shift)
        translate!(plot, 0, 0, 0)
    else
        plot.depth_shift = 0f0
    end
end

move_to_back!(plot, ::Rect3) = nothing
function move_to_back!(plot, ::Rect2)
    if !hasproperty(plot, :depth_shift)
        translate!(plot, 0, 0, -100)
    else
        plot.depth_shift = 0.1f0
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

function create_tile_plot!(map::AbstractMap, tile::Tile, data)
    # For providers which have to map the same data to different tiles
    # Or providers that have e.g. additional parameters like a date
    # the url is a much better key than the tile itself
    # TODO, should we instead have custom tiles for certain provider?
    key = TileProviders.geturl(map.provider, tile.x, tile.y, tile.z)
    # This can happen for tile providers with overlapping data that doesn't map 1:1 to tiles
    haskey(map.plots, key) && return

    cfg = map.plot_config
    data_processed = cfg.preprocess(data)
    bounds = get_bounds(tile, data_processed, map.crs)
    if bounds isa Rect3
        # for 3d meshes, we need to remove any plot in the same area
        # for 2d plots, we simply move the plot to the back
        for (key, (plot, tile, cbounds)) in map.plots
            if bounds in cbounds
                delete!(map.plots, key)
                push!(map.unused_plots, plot)
                plot.visible = false
            end
        end
    end
    # Cull unused plots
    if length(map.plots) > 200
        # remove the oldest plot
        plotted_tiles = getindex.(values(map.plots), 2)
        available_to_remove = setdiff(plotted_tiles, keys(map.current_tiles))
        sort!(available_to_remove, by=tile-> abs(tile.z - map.zoom[]))
        n_avail = length(available_to_remove)
        to_remove = available_to_remove[1:(n_avail - 200)]
        for tile in to_remove
            plot_key = remove_unused!(map, tile)
            if !isnothing(plot_key)
                plot_key[1].visible = false
                push!(map.unused_plots, plot_key[1])
                delete!(map.plots, plot_key[2])
            end
        end
    end

    if isempty(map.unused_plots)
        mplot = create_tileplot!(cfg, map.axis, data_processed, bounds, (tile, map.crs))
    else
        mplot = pop!(map.unused_plots)
        update_tile_plot!(mplot, cfg, map.axis, data_processed, bounds, (tile, map.crs))
    end

    if bounds isa Rect2
        if haskey(map.current_tiles, tile)
            move_in_front!(mplot, bounds)
        else
            move_to_back!(mplot, bounds)
        end
    end
    # Always move new plots to the front
    mplot.visible = true
    cfg.postprocess(mplot)
    map.plots[key] = (mplot, tile, bounds)
    # TODO, why do get some of the current_tiles stuck on a wrong depth_shift value?
    for (key, (plot, tile, bounds)) in map.plots
        if haskey(map.current_tiles, tile)
            move_in_front!(plot, bounds)
        else
            move_to_back!(plot, bounds)
        end
    end
    return
end

############################
#### Elevation Data plotting
####

struct ElevationData
    elevation::AbstractMatrix{<: Number}
    color::AbstractMatrix{<: Colorant}
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
    @show mini maxi
    p = Makie.surface!(
        axis.scene,
        (mini[1], maxi[1]), (mini[2], maxi[2]), data.elevation;
        color...,
        shading=Makie.NoShading,
        inspectable=false,
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

function create_tileplot!(config::PlotConfig, axis::AbstractAxis, data::PointCloudData, bounds::Rect, tile_crs)
    p = Makie.scatter!(
        axis.scene, data.points;
        color=data.color,
        marker=Makie.FastPixel(),
        markersize=data.msize, markerspace=:data,
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
