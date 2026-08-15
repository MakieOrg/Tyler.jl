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

Tiles are fetched through the provider's regular Tyler download machinery, so any
provider that works with `Tyler.Map` works here.  Image providers return a
`Matrix{RGBAf}`; elevation providers like [`Tyler.ElevationProvider`](@ref) return a
`Matrix{Float32}` of elevation values instead (only the elevation is returned for now -
any color information is dropped).

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

"""
    Tyler.tile_matrix(data)::AbstractMatrix

Convert the data fetched for a single tile (as returned by `Tyler.fetch_tile`) to a
matrix in Julia's column-major `(x, y)` memory layout, with `y` increasing northwards,
ready to be stitched into a [`basemap`](@ref).

Methods are provided for:
- `AbstractMatrix{<: Colorant}` (image tiles): rotated from the Images.jl row-major
  layout to `(x, y)` via `rotr90`.
- `Tyler.ElevationData`: returns only the elevation matrix, for now; any color
  information the provider fetched is dropped.

This function is the hook that makes [`basemap`](@ref) work with custom tile types:
if your provider's `fetch_tile` returns some other type, add a method of this function
for it (and one of [`Tyler.base_fill`](@ref), which provides the fill value for areas
not covered by any tile and thereby the element type of the basemap array).

This function is considered API, but is not exported.
"""
tile_matrix(data::AbstractMatrix{<: Colorant}) = rotr90(data)
tile_matrix(data::ElevationData) = data.elevation
tile_matrix(data) = error("`basemap` cannot handle tiles of type $(typeof(data)).  Supported tile types are images (`AbstractMatrix{<: Colorant}`) and `Tyler.ElevationData`.  To add support for a new tile type, define a method for `Tyler.tile_matrix`.")

"""
    Tyler.base_fill(data)

Return the value used to fill areas of a [`basemap`](@ref) not covered by any tile,
given the data fetched for a single tile.  The type of this value also determines the
element type of the array that `basemap` returns, so every value a
[`Tyler.tile_matrix`](@ref) for the same tile type produces must be convertible to it.

Methods are provided for:
- `AbstractMatrix{<: Colorant}` (image tiles): opaque black, `RGBAf(0, 0, 0, 1)`.
- `Tyler.ElevationData`: `NaN32`.

Extend this alongside [`Tyler.tile_matrix`](@ref) to make `basemap` work with custom
tile types.

This function is considered API, but is not exported.
"""
base_fill(::AbstractMatrix{<: Colorant}) = RGBAf(0, 0, 0, 1)
base_fill(::ElevationData) = NaN32

function _basemap(provider::TileProviders.AbstractProvider, boundingbox::Union{Rect2{<: Real}, Extent}, zoom::Int)
    bbox = Extents.extent(boundingbox)
    # Generate a `TileGrid` from our zoom level and bbox.
    tilegrid = MapTiles.TileGrid(bbox, zoom, MapTiles.WGS84())
    tilegrid_extent = Extents.extent(tilegrid, MapTiles.WebMercator())
    # Use the provider's own downloader and tile loader, so that any provider
    # Tyler supports (e.g. `ElevationProvider`) works here too.
    downloader = get_downloader(provider)
    xrange, yrange = tilegrid.grid.indices
    image = nothing
    tile_widths = (0, 0)
    for tile in tilegrid
        data = fetch_tile(provider, downloader, tile)
        isnothing(data) && continue # the provider has no tile here
        matrix = tile_matrix(data)
        if isnothing(image)
            # The first fetched tile tells us the tile size and element type,
            # so we don't have to assume 256×256 image tiles
            # (e.g. elevation tiles are 257×257, retina tiles 512×512).
            tile_widths = size(matrix)
            full_size = tile_widths .* length.((xrange, yrange))
            fill_value = base_fill(data)
            # Warn before allocating if the result would be very large - it's
            # easy to ask for something enormous by accident, e.g. via a too-fine `res`.
            image_megabytes = prod(full_size) * sizeof(fill_value) / 1024^2
            if image_megabytes > 100
                @warn """
                The requested basemap will be $(full_size[1])×$(full_size[2]) pixels \
                ($(round(image_megabytes, digits = 1)) MB, $(length(tilegrid)) tiles to download).
                If this is not what you intended, pass a smaller `size`, a coarser `res`, \
                a smaller `z`, or a smaller `max_zoom_level`.
                """
            end
            image = fill(fill_value, full_size)
        end
        # Tile y indices run north to south, against the axis direction,
        # so flip them relative to the grid when placing the tile.
        offset = (tile.x - first(xrange), last(yrange) - tile.y) .* tile_widths
        image[(:).(offset .+ 1, offset .+ tile_widths)...] .= matrix
    end
    isnothing(image) && error("The provider $(provider) returned no tiles for the bounding box $(bbox) at zoom level $(zoom).")
    # Return the image together with its axes.
    # Note that these are in the Web Mercator coordinate system.
    return (tilegrid_extent.X, tilegrid_extent.Y, image)
end

# We also use this in some Makie converts to allow `image` to work
Makie.used_attributes(trait::Makie.ImageLike, provider::TileProviders.AbstractProvider, bbox::Union{Rect2, Extent}, size::Union{Int, Tuple{Int, Int}}) = (:min_zoom_level, :max_zoom_level)

function Makie.convert_arguments(trait::Makie.ImageLike, provider::TileProviders.AbstractProvider, bbox::Extent, size::Union{Int, Tuple{Int, Int}}; min_zoom_level = 0, max_zoom_level = 16)
    return Makie.convert_arguments(trait, basemap(provider, bbox; size = (first(size), last(size)), min_zoom_level, max_zoom_level)...)
end

function Makie.convert_arguments(trait::Makie.ImageLike, provider::TileProviders.AbstractProvider, bbox::Rect2, size::Union{Int, Tuple{Int, Int}}; min_zoom_level = 0, max_zoom_level = 16)
    return Makie.convert_arguments(trait, provider, Extents.extent(bbox), (first(size), last(size)); min_zoom_level, max_zoom_level)
end


