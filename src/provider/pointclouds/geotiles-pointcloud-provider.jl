

struct GeoTilePointCloudProvider <: TileProviders.AbstractProvider
    baseurl::String
    subset::String
    lookup
    projs::Vector{Proj.Transformation}
end

get_tile_format(::GeoTilePointCloudProvider) = PointCloudData
TileProviders.options(::GeoTilePointCloudProvider) = nothing
TileProviders.min_zoom(::GeoTilePointCloudProvider) = 16
TileProviders.max_zoom(::GeoTilePointCloudProvider) = 16

const AHN_SUB_MAPPING = Dict{Tuple{Int,Int},String}()

function get_ahn_sub_mapping()
    if isempty(AHN_SUB_MAPPING)
        path = joinpath(@__DIR__, "mapping.csv")
        matrix = DelimitedFiles.readdlm(path, ',')
        merge!(AHN_SUB_MAPPING, Dict((r[1], r[2]) => r[3] for r in eachrow(matrix)))
    end
    return AHN_SUB_MAPPING
end

function GeoTilePointCloudProvider(; baseurl="https://geotiles.citg.tudelft.nl", subset="AHN1_T")

    projs = [Proj.Transformation(GFT.EPSG(28992), GFT.EPSG(3857)) for i in 1:Threads.nthreads()]
    return GeoTilePointCloudProvider(baseurl, subset, get_ahn_sub_mapping(), projs)
end

function TileProviders.geturl(p::GeoTilePointCloudProvider, x::Integer, y::Integer, z::Integer)
    println("$((x, y, z))> $(haskey(p.lookup, (x, y)))")
    if z == TileProviders.min_zoom(p) && haskey(p.lookup, (x, y))
        return string(p.baseurl, "/", p.subset, "/", p.lookup[(x, y)], ".LAZ")
    end
    return nothing
end

function get_points(las, offset, scale, proj)
    return map(las.points) do p
        point = Point3f(offset .+ Point3f(p.coords) .* scale)
        Point3f(proj(point.data))
    end
end

CACHE_PATH = joinpath(@__DIR__, "netherlands", "cache-ahn1")

function fetch_tile(provider::GeoTilePointCloudProvider, tile::Tile)
    url = TileProviders.geturl(provider, tile.x, tile.y, tile.z)
    isnothing(url) && return nothing
    dir = joinpath(CACHE_PATH, provider.subset)
    isdir(dir) || mkpath(dir)
    path = joinpath(dir, "$(tile.x)_$(tile.y)_$(tile.z).laz")
    if !isfile(path)
        Downloads.download(url, path)
    end
    pc = LAS(path)
    isempty(pc.points) && return nothing
    proj = provider.projs[Threads.threadid()]
    points = get_points(pc, Point3f(pc.coord_offset), Point3f(pc.coord_scale), proj)
    extrema = Point3f.(proj.(Point3f[pc.coord_min, pc.coord_max]))
    diag_len = norm(extrema[2] .- extrema[1])
    approx_points_in_diag = sqrt(length(pc.points)) * sqrt(2)
    msize = (diag_len / approx_points_in_diag) .* 1.5
    if hasproperty(pc.points[1], :color_channels)
        color = map(pc.points) do p
            c = map(x -> N0f8(x / 255), p.color_channels)
            return RGB(c[1], c[2], c[3])
        end
    else
        color = last.(points) # z as fallback
    end
    return PointCloudData(points, color, Rect3d(extrema[1], extrema[2] .- extrema[1]), msize)
end
