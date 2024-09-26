```@meta
CollapsedDocStrings = true
```

# Base maps

A "base map" is essentially a static image composed of map tiles, accessible through the [`basemap`](@ref) function.  

This function returns a tuple of `(x, y, image)`, where `x` and `y` are the dimensions of the image, and `image` is the image itself.  
The image, and axes, are always in the Web Mercator coordinate system.

While Tyler does not currently work with CairoMakie, this method is a way to add a basemap to a CairoMakie plot, though it will not update on zoom.

```@docs; canonical=false
basemap
```

## Examples


Below are some cool examples of using basemaps.

#### Cover example of London

````@example coverlondon
using Tyler

xs, ys, img = basemap(
    TileProviders.OpenStreetMap(),
    Extent(X=(-0.5, 0.5), Y=(51.25, 51.75)),
    (1024, 1024)
)
````

````@example coverlondon
image(xs, ys, img; axis = (; aspect = DataAspect()))
````

Note that the image is in the Web Mercator projection, as are the axes we see here.

#### NASA GIBS tileset, plotted as a `meshimage` on a `GeoAxis`

````@example nasagibs
const BACKEND = Makie.current_backend() # hide
using Tyler, TileProviders, GeoMakie, CairoMakie

provider = TileProviders.NASAGIBS(:ViirsEarthAtNight2012)

xs, ys, img = basemap(provider, Extent(X=(-90, 90), Y=(-90, 90)), (1024, 1024))
````

````@example nasagibs
meshimage(
    xs, ys, img; 
    source = "+proj=webmerc", # REMEMBER: `img` is always in Web Mercator...
    axis = (; type = GeoAxis, dest = "+proj=ortho +lat_0=0 +lon_0=0"),
    npoints = 1024,
)
````

````@example nasagibs
BACKEND.activate!() # hide
````


### OpenSnowMap on polar stereographic projection

````@example opensnowmap
using Tyler, GeoMakie

meshimage(
    basemap(
        TileProviders.OpenSnowMap(),
        Extent(X=(-180, 180), Y=(50, 90)),
        (1024, 1024)
    )...;
    source = "+proj=webmerc",
    axis = (; type = GeoAxis, dest = "+proj=stere +lat_0=90 +lat_ts=71 +lon_0=-45"),
)
````
