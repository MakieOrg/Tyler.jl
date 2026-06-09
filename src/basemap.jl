#=
# Static basemaps

This file provides the ability to get static base maps from Tyler.

Its main entry point is the `basemap` function, which returns a tuple 
`(x, y, z)` of the image data (`z`) and its axes (`x` and `y`).

This file also contains definitions for `convert_arguments` that make
the following syntax "just work":
```julia
image(TileProviders.Google(), Rect2f(-0.0921, 51.5, 0.04, 0.025), (1000, 1000); axis= (; aspect = DataAspect()))
```

You do still have to provide the extent and image size, but this is substantially better than nothing.

=#

export basemap


"""
    _z_index(extent::Extent, res::NamedTuple, crs::WebMercator) => Int

Calculate a z value from `extent` and pixel resolution `res` for `crs`.
The rounded mean calculated z-index for X and Y resolutions is returned.

`res` should be `(X=xres, Y=yres)` to match the extent.

We assume tiles are the standard 256*256 pixels. Note that this is not an
enforced standard, and that retina tiles are 512*512.
"""
function _z_index(extent::Union{Rect,Extent}, res::NamedTuple, crs; tile_size = 256)
    # Calculate the number of tiles at each z and get the one
    # closest to the resolution `res`
    target_ntiles = prod(map(r -> r / tile_size, res))
    tiles_at_z = map(1:24) do z
        length(TileGrid(extent, z, crs))
    end
    return findmin(x -> abs(x - target_ntiles), tiles_at_z)[2]
end

# Normalize `size`/`res` style values to an `(x, y)` tuple,
# accepting `(; X, Y)` named tuples in any field order.
_xy(val::NamedTuple) = (val.X, val.Y)
_xy(val) = (first(val), last(val))

"""
    basemap(provider::TileProviders.Provider, bbox::Extent; size, res, z, min_zoom_level, max_zoom_level)::(xs, ys, img)

Download the most suitable basemap for the given bounding box and size, return a tuple of `(x_interval, y_interval, image)`.
All returned coordinates and images are in the **Web Mercator** coordinate system (since that's how tiles are defined).

The input bounding box must be in the **WGS84** (long/lat) coordinate system.

## Example

```julia
basemap(TileProviders.Google(), Extent(X = (-0.0921, -0.0521), Y = (51.5, 51.525)), size   = (1000, 1000))
```

## Keyword arguments

`size`, `res` and `z` are mutually exclusive, and you must provide exactly one of them.

`size` should be a tuple `(xsize, ysize)` (a named tuple `(X = xsize, Y = ysize)` also works),
and `res` should be a tuple of the form `(X = xres, Y = yres)` to match the extent.

Note that `size` and `res` are **approximate**: they are only used to pick a zoom level,
and the returned image covers the full grid of tiles at that zoom level which intersects
the bounding box.  The actual image is therefore usually larger than requested.

`z` is the tile zoom level.  If provided, it is used directly instead of being computed
from `size` or `res`.

`min_zoom_level = 0` and `max_zoom_level = 16` are the minimum and maximum zoom levels
to consider when computing a zoom level from `size` or `res`.  They are ignored if `z`
is provided explicitly.
"""
function basemap(provider::TileProviders.AbstractProvider, boundingbox::Union{Rect2{<: Real}, Extent};
        size = nothing, res = nothing, z = nothing, min_zoom_level = 0, max_zoom_level = 16
    )
    bbox = Extents.extent(boundingbox)
    # First, handle keyword arguments
    @assert count(!isnothing, (size, res, z)) == 1 "You must provide exactly one of the `size`, `res` or `z` keywords.  Current values: size = $(size), res = $(res), z = $(z)"
    zoom = if !isnothing(z)
        z
    else
        _size = if isnothing(size)
            # convert resolution to size using bbox and round(Int, x)
            _res = _xy(res)
            (round(Int, (bbox.X[2] - bbox.X[1]) / _res[1]), round(Int, (bbox.Y[2] - bbox.Y[1]) / _res[2]))
        else
            _xy(size)
        end
        # Obtain the optimal Z-index that covers the bbox at the desired resolution.
        clamp(_z_index(bbox, (X=_size[1], Y=_size[2]), MapTiles.WGS84()), min_zoom_level, max_zoom_level)
    end
    return _basemap(provider, bbox, zoom)
end

function _basemap(provider::TileProviders.AbstractProvider, boundingbox::Union{Rect2{<: Real}, Extent}, zoom::Int)
    bbox = Extents.extent(boundingbox)
    # Generate a `TileGrid` from our zoom level and bbox.
    tilegrid = MapTiles.TileGrid(bbox, zoom, MapTiles.WGS84())
    # Compute the dimensions of the tile grid, so we can feed them into a 
    # Raster later.
    tilegrid_extent = Extents.extent(tilegrid, MapTiles.WebMercator())
    #= TODO:
    Here we assume all tiles are 256x256.  
    It's easy to compute this though, by either:
    - Making a sample query for the tile (0, 0, 0) (but you are not guaranteed this exists)
    - Some function that returns the tile size for a given provider / dispatch form
    =#
    tile_widths = (256, 256)
    tilegrid_size = tile_widths .* length.(tilegrid.grid.indices)
    # Warn if the resulting image would be very large - it's easy to ask for
    # something enormous by accident, e.g. via a too-fine `res`.
    image_megabytes = prod(tilegrid_size) * sizeof(RGBAf) / 1024^2
    if image_megabytes > 100
        @warn """
        The requested basemap will be $(tilegrid_size[1])×$(tilegrid_size[2]) pixels \
        ($(round(image_megabytes, digits = 1)) MB, $(length(tilegrid)) tiles to download).
        If this is not what you intended, pass a smaller `size`, a coarser `res`, \
        a smaller `z`, or a smaller `max_zoom_level`.
        """
    end
    # We need to know the start and end indices of the tile grid, so we can 
    # place the tiles in the right place.
    tile_start_idxs = minimum(first.(Tuple.(tilegrid.grid))), minimum(last.(Tuple.(tilegrid.grid)))
    tile_end_idxs = maximum(first.(Tuple.(tilegrid.grid))), maximum(last.(Tuple.(tilegrid.grid)))
    # Using the size information, we initiate an `RGBA{Float32}` image array.
    # You can later convert to whichever size / type you want by simply broadcasting.
    image_receptacle = fill(RGBAf(0,0,0,1), tilegrid_size)
    # Now, we iterate over the tiles, and read and then place them into the array.
    for tile in tilegrid
        # Download the tile
        url = TileProviders.geturl(provider, tile.x, tile.y, tile.z)
        result = HTTP.get(url)
        # Read into an in-memory array (Images.jl layout)
        img = FileIO.load(FileIO.query(IOBuffer(result.body)))
        # The thing with the y indices is that they go in the reverse of the natural order.
        # So, we simply subtract the y index from the end index to get the correct placement.
        image_start_relative = (
            tile.x - tile_start_idxs[1], 
            tile_end_idxs[2] - tile.y,
        )
        # The absolute start is simply the relative start times the tile width.
        image_start_absolute = (image_start_relative .* tile_widths)
        # The indices for the view into the receptacle are the absolute start 
        # plus one, to the absolute end.
        idxs = (:).(image_start_absolute .+ 1, image_start_absolute .+ tile_widths)
        @debug image_start_relative image_start_absolute idxs
        # Place the tile into the receptacle.  Note that we rotate the image to 
        # be in the correct orientation.
        image_receptacle[idxs...] .= rotr90(img) # change to Julia memory layout
    end
    # Now, we have a complete image.
    # We can also produce the image's axes:
    # Note that this is in the Web Mercator coordinate system.
    return (tilegrid_extent.X, tilegrid_extent.Y, image_receptacle)
end

# We also use this in some Makie converts to allow `image` to work
Makie.used_attributes(trait::Makie.ImageLike, provider::TileProviders.AbstractProvider, bbox::Union{Rect2, Extent}, size::Union{Int, Tuple{Int, Int}}) = (:min_zoom_level, :max_zoom_level)

function Makie.convert_arguments(trait::Makie.ImageLike, provider::TileProviders.AbstractProvider, bbox::Extent, size::Union{Int, Tuple{Int, Int}}; min_zoom_level = 0, max_zoom_level = 16)
    return Makie.convert_arguments(trait, basemap(provider, bbox; size = (first(size), last(size)), min_zoom_level, max_zoom_level)...)
end

function Makie.convert_arguments(trait::Makie.ImageLike, provider::TileProviders.AbstractProvider, bbox::Rect2, size::Union{Int, Tuple{Int, Int}}; min_zoom_level = 0, max_zoom_level = 16)
    return Makie.convert_arguments(trait, provider, Extents.extent(bbox), (first(size), last(size)); min_zoom_level, max_zoom_level)
end


