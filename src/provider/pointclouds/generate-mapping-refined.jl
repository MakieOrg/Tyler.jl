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
using Extents, Tyler
import GeometryOps as GO

p = Point2f[(0, 0), (1, 0), (1, 1), (0, 1)]
GO.intersects(Polygon(p), Polygon(map(x -> x .- 1.1, p)))

function generate_mapping(web_tile_polys, geom_polys, n_neibhbours, geom_df)
    mapping = ThreadSafeDict{Tuple{Int,Int},String}()
    Threads.@threads for (i, poly) in tuple.(1:length(web_tile_polys), web_tile_polys)
        nclose_idx = n_neibhbours[i]
        isempty(nclose_idx) && continue
        GO.difference(Polygon(p), Polygon(map(x -> x .- 0.5, p)); target=PolygonTrait()) |> GO.area
        npoly_indices = findall(x -> GO.intersects(x, poly), geom_polys[nclose_idx])
        poly_indices = nclose_idx[npoly_indices]
        if length(poly_indices) > 1
            sort!(poly_indices; by= x -> GO.area(GO.intersection(poly,geom_polys[x])), rev=true)
        end
        tile = tilegrid[i]
        idx = poly_indices[1]
        mapping[(tile.x, tile.y)] = geom_df.GT_AHNSUB[idx]
    end
    return mapping
end

function get_ntiles(middle, midpoints, n)
    findall(x -> norm(x .- middle) < n, midpoints)
end
path = joinpath(@__DIR__, "netherlands", "AHN_subunits_GeoTiles", "AHN_subunits_GeoTiles.shp")
df = GDF.read(path)
geometry = reproject(df.geometry, GFT.EPSG(28992), GFT.EPSG(3857))
geo_polys = [Polygon(Point2d.(GeoInterface.coordinates(p)[1])) for p in geometry]
mid_points = [mean(coordinates(p)) for p in geo_polys]
bounds = mapreduce(x -> Rect2f(decompose(Point2f, x)), Base.union, geo_polys)

tilegrid = TileGrid(Extents.extent(bounds), 16, MapTiles.web_mercator)
web_tile_polys = map(tilegrid) do tile
    tile_ext = Tyler.to_rect(MapTiles.extent(tile, Tyler.web_mercator))
    return Polygon(decompose(Point2d, tile_ext)[[1, 3, 4, 2]])
end
first_poly = geo_polys[1]
rect = Rect2f(coordinates(first_poly))
n_neighbours = norm(widths(rect)) * 2
all_n_neighbours = map(web_tile_polys) do poly
    nclose_idx = get_ntiles(mean(coordinates(poly)), mid_points, n_neighbours)
    return nclose_idx
end

mapping = generate_mapping(web_tile_polys, geo_polys, all_n_neighbours, df)

mkeys = collect(keys(mapping))
mvalues = collect(values(mapping))
k1 = first.(mkeys)
k2 = last.(mkeys)
matrix = hcat(k1, k2)

open(joinpath(@__DIR__, "mapping.bin"), "w") do io
    write(io, length(mkeys))
    write(io, UInt16.(matrix))
    for s in mkeys
        write(io, s)
        write(io, UInt8(0))
    end
end

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

read_mapping(joinpath(@__DIR__, "mapping.bin"))
