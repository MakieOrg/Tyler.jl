using DelimitedFiles
using GeometryBasics
using GeoInterface, TileProviders
import GeoDataFrames as GDF
using GeoDataFrames
import GeoFormatTypes as GFT
using Statistics, LinearAlgebra
using Makie: Point2d
using ThreadSafeDicts: ThreadSafeDict
using MapTiles
using Extents
import GeometryOps as OP

function generate_mapping(tilegrid, mid_points, geom_df)
    mapping = ThreadSafeDict{Tuple{Int,Int},String}()
    Threads.@threads for tile in tilegrid
        tb = MapTiles.extent(tile, Tyler.web_mercator)
        wx = (tb.X[2] - tb.X[1])
        wy = (tb.Y[2] - tb.Y[1])
        tile_mid = Point2d(tb.X[1] + wx / 2, tb.Y[1] + wy / 2)
        val, idx = findmin(x -> norm(tile_mid .- x), mid_points)
        if val < max(wx, wy)
            mapping[(tile.x, tile.y)] = geom_df.GT_AHNSUB[idx]
        end
    end
    return mapping
end

function get_tiles(area, point_rects, tiles)
    tilenames = String[]
    for (i, points) in enumerate(point_rects)
        if any(p -> p in area, points)
            push!(tilenames, tiles.GT_AHNSUB[i])
        end
    end
    return tilenames
end

path = joinpath(@__DIR__, "netherlands", "AHN_subunits_GeoTiles", "AHN_subunits_GeoTiles.shp")
df = GDF.read(path)
geometry = reproject(df.geometry, GFT.EPSG(28992), GFT.EPSG(3857))
mid_points = [mean(Point2d.(GeoInterface.coordinates(p)[1])) for p in geometry]
bounds = Rect2d(mid_points)
tilegrid = TileGrid(Extents.extent(bounds), 15, MapTiles.web_mercator)

mapping = generate_mapping(tilegrid, mid_points, df)

mkeys = collect(keys(mapping))
mvalues = collect(values(mapping))
k1 = first.(mkeys)
k2 = last.(mkeys)
matrix = hcat(k1, k2, mvalues)

DelimitedFiles.writedlm("mapping.csv", matrix, ',')

matrix = DelimitedFiles.readdlm("mapping.csv", ',')
mapping2 = Dict((r[1], r[2]) => r[3] for r in eachrow(matrix))
@assrt mapping2 == mapping
