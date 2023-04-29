
lng2tile(lng, zoom) = floor((lng+180)/360*2^zoom)
lat2tile(lat, zoom) = floor((1-log(tan(lat*pi/180)+1/cos(lat*pi/180))/pi)/2*2^zoom)

tile2lng(x, z) = (x/2^z*360)-180
tile2lat(y, z) = - 180/pi*atan(0.5*(exp(pi-2*pi*y/2^z)-exp(2*pi*y/2^z-pi)))

tile2positions(tile::Tile) = tile2positions(tile.x,tile.y,tile.z)
function tile2positions(x,y,z) 
    rng=range(0.5/232,231.5/232,232)
    lons=[tile2lng(x+i,z) for i in rng, j in rng]
    lats=[tile2lat(y+j,z) for i in rng, j in rng]
    (lons,lats)
end

struct Interpolator <: AbstractProvider
    interpolator::Function
end

function fetch_tile(provider::Interpolator, tile::Tile)
    (lon, lat) = tile2positions(tile)
    z = permutedims(provider.interpolator.(lon, lat))
    return [col(i) for i in z]
end
