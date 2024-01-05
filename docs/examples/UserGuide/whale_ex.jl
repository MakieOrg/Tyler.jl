# # Whale shark exampe trajectory

# ## Using the full stack of Makie should just work.

using Tyler, GLMakie
using CSV, DataFrames
using DataStructures: CircularBuffer
using TileProviders
using MapTiles
using Downloads: download

mkpath("assets")#hide
function to_web_mercator(lo,lat)
    return Point2f(MapTiles.project((lo,lat), MapTiles.wgs84, MapTiles.web_mercator))
end

url = "https://raw.githubusercontent.com/MakieOrg/Tyler.jl/master/docs/src/assets/data/whale_shark_128786.csv"
d = download(url)
whale = CSV.read(d, DataFrame)
lon = whale[!, :lon]
lat = whale[!, :lat]
steps = size(lon,1)
points = to_web_mercator.(lon,lat)

lomn, lomx = extrema(lon)
lamn, lamx = extrema(lat)
δlon = abs(lomn - lomx)
δlat = abs(lamn - lamx)

provider = TileProviders.NASAGIBS(:ViirsEarthAtNight2012)

set_theme!(theme_black())
m = Tyler.Map(Rect2f(Rect2f(lomn - δlon/2, lamn-δlat/2, 2δlon, 2δlat));
    provider, figure=Figure(; size=(1000, 600)))
wait(m)

nt = 30
trail = CircularBuffer{Point2f}(nt)
fill!(trail, points[1]) # add correct values to the circular buffer
trail = Observable(trail) # make it an observable
whale = Observable(points[1])

c = to_color(:dodgerblue)
trailcolor = [RGBAf(c.r, c.g, c.b, (i/nt)^2.5) for i in 1:nt] # fading tail

objline = lines!(m.axis, trail; color = trailcolor, linewidth=3)
objscatter = scatter!(m.axis, whale; markersize = 15, color = :orangered,
    strokecolor=:grey90, strokewidth=1)
hidedecorations!(m.axis)
#limits!(ax, minimum(lon), maximum(lon), minimum(lat), maximum(lat))
## the animation is done by updating the Observable values
## change assets->(your folder) to make it work in your local env
record(m.figure, joinpath("assets", "whale_shark_128786.mp4")) do io
    for i in 2:steps
        push!(trail[], points[i])
        whale[] = points[i]
        trail[] = trail[]
        recordframe!(io)  # record a new frame
    end
end
set_theme!()

# !!! info
#       Whale shark movements in Gulf of Mexico.
#
#       Contact person: Eric Hoffmayer

# ![type:video](./assets/whale_shark_128786.mp4)
