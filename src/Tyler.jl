module Tyler

using Colors: Colors, RGB, N0f8, Colorant
using Extents: Extents, Extent
using GeoInterface: GeoInterface
using GeometryBasics: GeometryBasics, GLTriangleFace, Point2f, Vec2f, Rect2f, Rect2, Rect, decompose, decompose_uv, Vec3d, Point2d
using HTTP: HTTP
using ImageMagick: ImageMagick
using LRUCache: LRUCache, LRU
using MapTiles: MapTiles, Tile, TileGrid, web_mercator, wgs84, CoordinateReferenceSystemFormat
using Makie: Makie, Observable, Figure, Axis, LScene, RGBAf, on, isopen, meta, mesh!, translate!, scale!, Plot
using OrderedCollections: OrderedCollections, OrderedSet
using ThreadSafeDicts: ThreadSafeDicts, ThreadSafeDict
using TileProviders: TileProviders, AbstractProvider, geturl, min_zoom, max_zoom
using Makie
using Makie: AbstractAxis
using LinearAlgebra, GeometryBasics
using GeometryBasics
using Proj
using Statistics, DelimitedFiles
using PointClouds
using ArchGDAL
import GeoFormatTypes as GFT
using Downloads
using Scratch

const CACHE_PATH = Ref("")

function __init__()
    # Initialize at init for relocatability
    CACHE_PATH[] = @get_scratch!("download-cache")
end

abstract type AbstractPlotConfig end
abstract type FetchingScheme end
abstract type AbstractMap end

include("downloader.jl")
include("interpolations.jl")
include("tiles.jl")
include("map.jl")
include("2d-map.jl")
include("3d-map.jl")
include("tile-plotting.jl")
include("provider/elevation/elevation-provider.jl")
include("provider/pointclouds/geotiles-pointcloud-provider.jl")

function z_index(extent::Union{Rect,Extent}, res::Tuple, crs)
    # Calculate the number of tiles at each z and get the one
    # closest to the resolution `res`
    target_ntiles = prod(map(r -> r / 256, res))
    tiles_at_z = map(1:24) do z
        length(TileGrid(extent, z, crs))
    end
    return findmin(x -> abs(x - target_ntiles), tiles_at_z)[2]
end

function grow_extent(area::Union{Rect,Extent}, factor)
    Extent(map(Extents.bounds(area)) do axis_bounds
        span = axis_bounds[2] - axis_bounds[1]
        pad = factor * span / 2
        return (axis_bounds[1] - pad, axis_bounds[2] + pad)
    end)
end

end
