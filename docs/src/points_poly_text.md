
## Add points, polygons and text to a map

Load packages
````@example plottypes
using Tyler, GLMakie
using Tyler.TileProviders
using Tyler.MapTiles
using Tyler.Extents
````

select a map provider

````@example plottypes
provider = TileProviders.Esri(:WorldImagery)
````

define a point to plot on the map

````@example plottypes
# point location to add to map
lat = 34.2013;
lon = -118.1714;
````
convert to point in web_mercator

````@example plottypes
pts = Point2f(MapTiles.project((lon,lat), MapTiles.wgs84, MapTiles.web_mercator))
````

set how much area to map in degrees and define an `Extent` for display in web_mercator

````@example plottypes
delta = 1
extent = Rect2f(lon - delta / 2, lat - delta / 2, delta, delta);
````

show map

````@example plottypes
m = Tyler.Map(extent; provider, size=(1000, 600))
````

![](map_plottypes.png)

now plot a point, polygon and text on the map

````@example plottypes
objscatter = scatter!(m.axis, pts; color = :red,
    marker = '⭐', markersize = 50)
# hide ticks, grid and lables
hidedecorations!(m.axis)
# hide frames
hidespines!(m.axis)
# Plot a plygon on the map
p1 = (lon-delta/8, lat-delta/8)
p2 = (lon-delta/8, lat+delta/8)
p3 = (lon+delta/8, lat+delta/8)
p4 = (lon+delta/8, lat-delta/8)

polyg = MapTiles.project.([p1, p2, p3, p4], Ref(MapTiles.wgs84), Ref(MapTiles.web_mercator))
polyg = Point2f.(polyg)
poly!(polyg; color = :transparent, strokecolor = :black, strokewidth = 5)

# Add text
pts2 = Point2f(MapTiles.project((lon,lat-delta/6), MapTiles.wgs84, MapTiles.web_mercator))
text!(pts2, text = "Basic Example"; fontsize = 30,
    color = :darkblue, align = (:center, :center)
    )
m
````
