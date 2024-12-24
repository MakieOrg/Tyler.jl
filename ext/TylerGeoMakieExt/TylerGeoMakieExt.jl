module TylerGeoMakieExt

using Tyler, GeoMakie

using LinearAlgebra, OrderedCollections

import Tyler: tile_reloader, create_tileplot!, update_tile_plot!,
            Map, AbstractMap, ImageData, PlotConfig, DebugPlotConfig,
            SimpleTiling, Halo2DTiling

using Tyler: to_rect


using Makie, Makie.GeometryBasics

using Makie: AbstractAxis, Mat

using Extents
using TileProviders, MapTiles

function Tyler.setup_axis!(axis::GeoAxis, ext_target, crs)
    X = ext_target.X
    Y = ext_target.Y

    # Set the axis's limits
    rect = Rect2f((X[1], Y[1]), (X[2] - X[1], Y[2] - Y[1]))
    transf = GeoMakie.create_transform(axis.source[], crs)
    transformed_limits = Makie.apply_transform(transf, rect)

    tXmin, tYmin = transformed_limits.origin
    tXmax, tYmax = transformed_limits.origin .+ transformed_limits.widths

    axis.limits[] = (tXmin, tXmax, tYmin, tYmax)
    Makie.reset_limits!(axis)

    # axis.elements[:background].depth_shift[] = 0.1f0
    # translate!(axis.elements[:background], 0, 0, -1000)
    # axis.elements[:background].color = :transparent
    # axis.xgridvisible = false
    # axis.ygridvisible = false
    return
end

# functions directly related to plotting
include("tile-plotting.jl")

# functions related to fetching tiles
include("tile-fetching.jl")

end