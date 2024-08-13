module Tyler

using Colors: Colors, RGB, N0f8, Colorant
using Extents: Extents, Extent
using GeoInterface: GeoInterface
using GeometryBasics: GeometryBasics, GLTriangleFace, Point2f, Vec2f, Rect2f, Rect2, Rect, decompose, decompose_uv, Vec3d, Point2d, Point3d, Point4d
using HTTP: HTTP
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
using ImageIO, FileIO
import GeometryOps as GO


const CACHE_PATH = Ref("")

function __init__()
    # Initialize at init for relocatability
    CACHE_PATH[] = @get_scratch!("download-cache")
end

abstract type AbstractPlotConfig end
abstract type FetchingScheme end
abstract type AbstractMap end

include("downloader.jl")
include("tiles.jl")
include("map.jl")
include("3d-map.jl")
include("tyler-cam3d.jl")
include("tile-plotting.jl")
include("tile-fetching.jl")
include("provider/interpolations.jl")
include("provider/elevation/elevation-provider.jl")
include("provider/pointclouds/geotiles-pointcloud-provider.jl")
include("basemap.jl")

end
