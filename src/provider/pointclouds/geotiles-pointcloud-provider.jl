"""
    GeoTilePointCloudProvider(subset="AHN1_T")

The PointCloud provider downloads from [geotiles.citg.tudelft](https://geotiles.citg.tudelft.nl), which spans most of the netherlands.
You can specify the subset to download from, which can be one of the following:
- AHN1_T (default): The most corse dataset, but also the fastest to download (1-5mb compressed per tile)
- AHN2_T: More detailed dataset (~70mb per tile)
- AHN3_T: ~250mb per tile
- AHN4_T: 300-500mb showing much detail, takes a long time to load each tile (over 1 minute per tile). Use `max_plots=5` to limit the number of tiles loaded at once.
"""
struct GeoTilePointCloudProvider <: TileProviders.AbstractProvider
    baseurl::String
    subset::String
    lookup
    projs::Vector{Proj.Transformation}
end
function GeoTilePointCloudProvider(; baseurl="https://geotiles.citg.tudelft.nl", subset="AHN1_T")
    projs = [Proj.Transformation(GFT.EPSG(28992), GFT.EPSG(3857)) for i in 1:Threads.maxthreadid()]
    return GeoTilePointCloudProvider(baseurl, subset, get_ahn_sub_mapping(), projs)
end

# TileProviders interface
TileProviders.options(::GeoTilePointCloudProvider) = nothing
TileProviders.min_zoom(::GeoTilePointCloudProvider) = 16
TileProviders.max_zoom(::GeoTilePointCloudProvider) = 16
function TileProviders.geturl(p::GeoTilePointCloudProvider, x::Integer, y::Integer, z::Integer)
    if z == TileProviders.min_zoom(p) && haskey(p.lookup, (x, y))
        return string(p.baseurl, "/", p.subset, "/", p.lookup[(x, y)], ".LAZ")
    end
    return nothing
end

# Tyler interface
get_tile_format(::GeoTilePointCloudProvider) = PointCloudData
file_ending(::GeoTilePointCloudProvider) = ".laz"
function get_downloader(::GeoTilePointCloudProvider)
    cache_dir = joinpath(CACHE_PATH[], "GeoTilePointCloudProvider")
    return PathDownloader(cache_dir)
end

function load_tile_data(provider::GeoTilePointCloudProvider, path::String)
    pc = LAS(path)
    isempty(pc.points) && return nothing
    proj = provider.projs[Threads.threadid()]
    points = get_points(pc, Point3f(pc.coord_offset), Point3f(pc.coord_scale), proj)
    extrema = Point3f.(proj.(Point3f[pc.coord_min, pc.coord_max]))
    if !ismissing(PointClouds.IO.color_channels(pc.points[1]))
        color = map(pc.points) do p
            c = PointClouds.IO.color_channels(p)
            return RGB(N0f8(c[1]), N0f8(c[2]), N0f8(c[3]))
        end
    else
        color = last.(points) # z as fallback
    end
    best_markersize = Dict(
        "AHN1_T" => 9.0,
        "AHN2_T" => 5.0,
        "AHN3_T" => 4.0,
        "AHN4_T" => 2.0
    )
    bb = Rect3d(extrema[1], extrema[2] .- extrema[1])
    return PointCloudData(points, color, bb, best_markersize[provider.subset])
end

# Geotile utils

const AHN_SUB_MAPPING = Dict{Tuple{Int,Int},String}()

function read_mapping(path)
    open(path, "r") do io
        n = read(io, Int)
        keys = Matrix{UInt16}(undef, n, 2)
        read!(io, keys)
        strings = Vector{String}(undef, n)
        for i in 1:n
            strings[i] = readuntil(io, Char(0))
        end
        return Dict(Tuple(Int.(keys[i, :])) => strings[i] for i in 1:n)
    end
end

function get_ahn_sub_mapping()
    if isempty(AHN_SUB_MAPPING)
        path = joinpath(@__DIR__, "mapping.bin")
        dict = read_mapping(path)
        merge!(AHN_SUB_MAPPING, dict)
    end
    return AHN_SUB_MAPPING
end

function get_points(las, offset, scale, proj)
    return map(las.points) do p
        point = Point3f(offset .+ Point3f(PointClouds.IO.coordinates(Integer, p)) .* scale)
        Point3f(proj(point.data))
    end
end