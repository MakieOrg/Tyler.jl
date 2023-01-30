# # Basic feature exampe

# ## Add points, polygons and text to a map

# load packages
using Tyler, GLMakie
using TileProviders
using MapTiles

# select a map provider
provider = TileProviders.Esri(:WorldImagery)

## Plot a point on the map

# point location to add to map
lat = 34.2013;
lon = -118.1714;

# convert to point in web_mercator
pts = Point2f(MapTiles.project((lon,lat), MapTiles.wgs84, MapTiles.web_mercator))

# set how much area to map in degrees
delta = 1;

# create rectangle for display extents in web_mercator
frame = Rect2f(lon - delta/2, lat-delta/2, delta, delta)

# show map
m = Tyler.Map(frame;
    provider, min_tiles=8, max_tiles=16, figure=Figure(resolution=(1000, 600)))
    
objscatter = scatter!(m.axis, pts; color = :red, marker = '⭐', markersize = 50)

# hide ticks, grid and lables
hidedecorations!(m.axis) 

# hide frames
hidespines!(m.axis)

## Plot a plygon on the map 
p1 = (lon-delta/8, lat-delta/8)
p2 = (lon-delta/8, lat+delta/8)
p3 = (lon+delta/8, lat+delta/8)
p4 = (lon+delta/8, lat-delta/8)

polyg = MapTiles.project.([p1, p2, p3, p4], Ref(MapTiles.wgs84), Ref(MapTiles.web_mercator))
polyg = Point2f.(polyg)
poly!(polyg, color = :transparent, strokecolor = :black, strokewidth = 5)

## Add text
pts2 = Point2f(MapTiles.project((lon,lat-delta/6), MapTiles.wgs84, MapTiles.web_mercator))
text!(pts2, text = "Basic Example", fontsize = 30, color = :darkblue, align = (:center, :center))