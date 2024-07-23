using Shapefile, Proj, GLMakie, Extents, Tyler, MapTiles, Downloads
using LASDatasets, GeoInterface
import GeoDataFrames as GDF
using GeoDataFrames
import GeoFormatTypes as GFT


function get_tiles(area, point_rects, tiles)
    tilenames = String[]
    for (i, points) in enumerate(point_rects)
        if any(p-> p in area, points)
            push!(tilenames, tiles.GT_AHN[i])
        end
    end
    return tilenames
end

function all_points(geometry)
    points = NTuple{4, Point2f}[]
    for poly in geometry
        coord = (Point2f.(GeoInterface.coordinates(poly)[1]))
        proj(p) = Point2f(MapTiles.project(reverse(p), MapTiles.wgs84, MapTiles.web_mercator))
        push!(points, (proj.(unique(coord))...,))
    end
    return points
end


const CACHE = Dict{String, Any}()

function download_tile(name, url="https://geotiles.citg.tudelft.nl/AHN1/u/",
                       cache=joinpath(@__DIR__, "cache"))
    get!(CACHE, name) do
        path = joinpath(cache, name * ".laz")
        if !isfile(path)
            @show "$url$name.laz"
            # Downloads.download("$url$name.laz", path)
            return nothing
        end
        pc = LASDatasets.load_pointcloud(path)
        points = Point3f.(reproject(pc.position, GFT.EPSG(28992), GFT.EPSG(3857)))
        return points
    end
end

begin
    lat, lon = (52.395593, 4.884704)
    delta = 0.5
    extent = Extent(; X=(lon - delta / 2, lon + delta / 2), Y=(lat - delta / 2, lat + delta / 2))
    m = Tyler.Map3D(extent)
    display(m.figure.scene)
end


path = joinpath("GeoTyler", "AHN_AHN_GeoTiles", "AHN_AHN_GeoTiles.shp")
df = GDF.read(path)
geometry = reproject(df.geometry, GFT.EPSG(28992), GFT.EPSG(4326))
points = all_points(geometry)
tiles = get_tiles(Tyler.get_extent(m), points, df)
cache=joinpath(@__DIR__, "cache")
# for name in tiles
#     url = "https://geotiles.citg.tudelft.nl/AHN1/u/$(name).laz"
#     path = joinpath(cache, name * ".laz")
#     try
#         if !isfile(path)
#             @time Downloads.download(url, path)
#         end
#     catch e
#         println(e)
#     end
# end
for name in tiles
    download_tile(name)
end

@profview download_tile(tiles[6])

plots = map(tiles) do tile
    println("Downloading: $(tile)")
    @time tile = download_tile(tile)
    if !isnothing(tile)
        return scatter!(m.axis, tile; color=last.(tile), markersize=2, markerspace=:data, marker=Makie.FastPixel())
    end
    return nothing
end


Downloads.download("$url$name.laz", path)
