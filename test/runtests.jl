using Tyler
using Test
using GLMakie

Tyler.Map(Rect2f(-0.0921, 51.5, 0.04, 0.025))

begin
    tiles = MapTiles.TileGrid(extent(rect), 15, wgs84)
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
