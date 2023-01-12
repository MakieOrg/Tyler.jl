using Tyler
using Test

@testset "Tyler.jl" begin
    # Write your tests here.
end

@testset "" begin
    tiles = MapTiles.TileGrid(extent(rect), 15, wgs84)

tile = first(tiles)


translate!(plot, xmin, ymin, 0)
scale!(plot, xmax - xmin, ymax - ymin, 0)

provider = MapTiles.OpenStreetMapProvider(variant="standard")
    fig = Figure()
    ax = Axis(fig[1, 1]; aspect=DataAspect())
    display(fig)
    for tile in tiles
        bounds = MapTiles.extent(tile, web_mercator)
        xmin, xmax = bounds.X
        ymin, ymax = bounds.Y
        img = MapTiles.fetchrastertile(provider, tile)
        plot = Tyler.create_tileplot!(ax, img)
        Tyler.place_tile!(tile, plot, web_mercator)
    end
    fig
end
