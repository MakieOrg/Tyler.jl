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

"""
    basemap(provider::TileProviders.Provider, bbox::Extent; size, res, min_zoom_level = 0, max_zoom_level = 16)::(xs, ys, img)
"""
function basemap(provider::TileProviders.AbstractProvider, boundingbox::Union{Rect2{<: Real}, Extent}; size = nothing, res = nothing, min_zoom_level = 0, max_zoom_level = 16)
    bbox = Extents.extent(boundingbox)
    # First, handle keyword arguments
    @assert (isnothing(size) || isnothing(res)) "You must provide either `size` or `res`, but not both."
    @assert (isnothing(size) && isnothing(res)) "You must provide either the `size` or `res` keywords."
    _size = if isnothing(size) 
        # convert resolution to size using bbox and round(Int, x)
        (round(Int, (bbox.X[2] - bbox.X[1]) / first(res)), round(Int, (bbox.Y[2] - bbox.Y[1]) / last(res)))
    else
        (first(size), last(size))
    end
    return basemap(provider, bbox, _size; min_zoom_level, max_zoom_level)
end

function basemap(provider::TileProviders.AbstractProvider, boundingbox::Union{Rect2{<: Real}, Extent}, size::Tuple{Int, Int}; min_zoom_level = 0, max_zoom_level = 16)
    bbox = Extents.extent(boundingbox)
    # Obtain the optimal Z-index that covers the bbox at the desired resolution.
    optimal_z_index = clamp(z_index(bbox, (X=size[2], Y=size[1]), MapTiles.WGS84()), min_zoom_level, max_zoom_level)
    # Generate a `TileGrid` from our zoom level and bbox.
    tilegrid = MapTiles.TileGrid(bbox, optimal_z_index, MapTiles.WGS84())
    # Compute the dimensions of the tile grid, so we can feed them into a 
    # Raster later.
    tilegrid_extent = Extents.extent(tilegrid, MapTiles.WGS84())
    tilegrid_size = tile_widths .* length.(tilegrid.grid.indices)
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
        img = ImageMagick.readblob(result.body)
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
    xs = (..)(tilegrid_extent.X...)
    ys = (..)(tilegrid_extent.Y...)
    # image(ras; axis = (; aspect = DataAspect()))
    return (xs, ys, image_receptacle)
end

# We also use this in some Makie converts to allow `image` to work
Makie.used_attributes(trait::Makie.ImageLike, provider::TileProviders.AbstractProvider, bbox::Union{Rect2, Extent}, size::Union{Int, Tuple{Int, Int}}) = (:min_zoom_level, :max_zoom_level)

function Makie.convert_arguments(trait::Makie.ImageLike, provider::TileProviders.AbstractProvider, bbox::Extent, size::Union{Int, Tuple{Int, Int}}; min_zoom_level = 0, max_zoom_level = 16)
    return Makie.convert_arguments(trait, basemap(provider, bbox, (first(size), last(size)); min_zoom_level, max_zoom_level)...)
end

function Makie.convert_arguments(trait::Makie.ImageLike, provider::TileProviders.AbstractProvider, bbox::Rect2, size::Union{Int, Tuple{Int, Int}}; min_zoom_level = 0, max_zoom_level = 16)
    return Makie.convert_arguments(trait, provider, Extents.extent(bbox), (first(size), last(size)); min_zoom_level, max_zoom_level)
end


