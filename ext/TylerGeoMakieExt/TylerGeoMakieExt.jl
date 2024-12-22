module TylerGeoMakieExt

using Tyler, GeoMakie

using LinearAlgebra, OrderedCollections

import Tyler: tile_reloader, create_tileplot!, update_tile_plot!,
            Map, AbstractMap, ImageData, PlotConfig, DebugPlotConfig,
            SimpleTiling, Halo2DTiling, Extent

using Tyler: to_rect


using Makie

using Makie: AbstractAxis, Mat

# functions directly related to plotting
include("tile-plotting.jl")

# functions related to fetching tiles
include("tile-fetching.jl")

end