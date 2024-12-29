module Tyler

using ArchGDAL
using Downloads
using FileIO
using GeometryBasics
using ImageIO
using LinearAlgebra
using Makie
using PointClouds
using Proj
using Scratch
using Statistics

import GeoFormatTypes as GFT
import GeometryOps as GO

using Colors: Colors, RGB, N0f8, Colorant
using Extents: Extents, Extent
using GeoInterface: GeoInterface
using GeometryBasics: GeometryBasics, GLTriangleFace, Point2f, Vec2f, Rect2f, Rect2, Rect, Vec3d, Point2d, Point3d, Point4d
using GeometryBasics: decompose, decompose_uv
using HTTP: HTTP
using LRUCache: LRUCache, LRU
using Makie: AbstractAxis, AbMakie, Observable, Figure, Axis, LScene, RGBAf, Fi
using Makie: on, isopen, meta, mesh!, translate!, scale!, Plot
using MapTiles: MapTiles, Tile, TileGrid, web_mercator, wgs84, CoordinateReferenceSystemFormat
using OrderedCollections: OrderedCollections, OrderedSet
using ThreadSafeDicts: ThreadSafeDicts, ThreadSafeDict
using TileProviders: TileProviders, AbstractProvider, geturl, min_zoom, max_zoom

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
include("tile-plottharedl")
include("tile-fetching.jl")
include("provider/shared.jl")
include("provider/interpolations.jl")
include("provider/elevation/elevation-provider.jl")
include("provider/pointclouds/geotiles-pointcloud-provider.jl")

end
