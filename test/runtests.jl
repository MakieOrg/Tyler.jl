using Test
using Tyler, MapTiles, Extents
using GLMakie, OSMMakie, LightOSM
using MapTiles: wgs84
using TileProviders
using MapTiles: web_mercator

london = Rect2f(-0.0921, 51.5, 0.04, 0.025)
m = Tyler.Map(london)

area = (
    minlat = 51.5015, minlon = -0.0921, # bottom left corner
    maxlat = 51.5154, maxlon = -0.0662 # top right corner
)
download_osm_network(:bbox; # rectangular area
    area..., # splat previously defined area boundaries
    network_type=:drive, # download motorways
    save_to_file_location="london_drive.json"
);

osm = graph_from_file("london_drive.json";
    graph_type=:light, # SimpleDiGraph
    weight_type=:distance
)
# use min and max latitude to calculate approximate aspect ratio for map projection
autolimitaspect = map_aspect(area.minlat, area.maxlat)

# plot it
london = Rect2f(-0.0921, 51.5, 0.04, 0.025)
rect = Rect2f(0, 50, 20, 20)
provider = TileProviders.NASAGIBS()
m = Tyler.Map(rect, 5; provider=provider, coordinate_system=Tyler.wgs84)
p = osmplot!(m.axis, osm)
translate!(p, 0, 0, 100)

begin
    rect = Rect2f(0, 50, 20, 20)

    tiles = MapTiles.TileGrid(Extents.extent(rect), 5, wgs84)

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

function debug_tile!(map::Tyler.Map, tile::Tile)
    plot = linesegments!(map.axis, Rect2f(0, 0, 1, 1), color=:red, linewidth=1)
    Tyler.place_tile!(tile, plot, web_mercator)
end

for tile in m.displayed_tiles
    debug_tile!(m, tile)
end
