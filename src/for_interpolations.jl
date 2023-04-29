
"""
    Interpolator <: AbstractProvider

    Interpolator(f; colormap=:thermal, options=Dict(:minzoom=1, :maxzoom=19))

Provides tiles by intolating them on the fly.

- `f`: an Interpolations.jl interpolator or similar.
- `colormap`: A `Symbol` or `Vector{RGBA{Float32}}`. Default is `:thermal`.
"""
struct Interpolator{F} <: AbstractProvider
    interpolator::F
    colormap::Vector{RGBAf}
    options::Dict
end
Interpolator(f; colormap=:thermal, options=Dict(:minzoom=>1, :maxzoom=>19)) =
    Interpolator(f, Makie.to_colormap(colormap), options)

function fetch_tile(interpolator::Interpolator, tile::Tile)
    (lon, lat) = _tile2positions(tile)
    z = permutedims(interpolator.interpolator.(lon, lat))
    return [_col(interpolator, i) for i in z]
end

# TODO just use Makie plotting for colors, 
# we just need to pass the args throught to it
_col(i::Interpolator, x) = RGBAf(Makie.interpolated_getindex(i.colormap, x))
_col(::Interpolator, x::RGBAf) = x

_lng2tile(lng, zoom) = floor((lng + 180) / 360 * 2^zoom)
_lat2tile(lat, zoom) = floor((1 - log(tan(lat * pi / 180) + 1 / cos(lat * pi / 180)) / pi) / 2 * 2^zoom)

_tile2lng(x, z) = (x / 2^z * 360) - 180
_tile2lat(y, z) = -180 / pi * atan(0.5 * (exp(pi - 2 * pi * y / 2^z) - exp(2 * pi * y / 2^z - pi)))

_tile2positions(tile::Tile) = _tile2positions(tile.x, tile.y, tile.z)
function _tile2positions(x, y, z) 
    rng = range(0.5 / 232, 231.5 / 232,232)
    lons = [_tile2lng(x + i, z) for i in rng, j in rng]
    lats = [_tile2lat(y + j, z) for i in rng, j in rng]
    return (lons, lats)
end
