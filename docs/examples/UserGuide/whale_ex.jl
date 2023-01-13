# # Whale shark exampe trajectory

# ## Using the full stack of Makie should just work.

using Tyler, GLMakie
using CSV, DataFrames
using DataStructures: CircularBuffer
mkpath("assets")#hide

#m = Tyler.Map(Rect2f(-0.0921, 51.5, 0.04, 0.025))

whale = CSV.read("./data/whale_shark_128786.csv", DataFrame)
lon = whale[!, :lon]
lat = whale[!, :lat]
steps = size(lon,1)

nt = 30
trail = CircularBuffer{Point2f}(nt)
fill!(trail, Point2f(lon[1], lat[1])) # add correct values to the circular buffer
trail = Observable(trail) # make it an observable
whale = Observable(Point2f(lon[1], lat[1]))

c = to_color(:dodgerblue)
trailcolor = [RGBAf(c.r, c.g, c.b, (i/nt)^2.5) for i in 1:nt] # fading tail

with_theme(theme_dark(), resolution = (1200,700)) do
    fig = Figure()
    ax = Axis(fig[1,1])
    lines!(ax, trail; color = trailcolor, linewidth=3)
    scatter!(ax, whale; ##image = collect(img_w), 
        ##marker= Rect, markersize = reverse(size(img_w))./12,
        ##rotations = rot
        markersize = 15,
        color = :orangered
        )
    limits!(ax, minimum(lon), maximum(lon), minimum(lat), maximum(lat))
    ## the animation is done by updating the Observable values
    ## change assets->(your folder) to make it work in your local env
    record(fig, joinpath("assets", "whale_shark_128786.mp4"),
        framerate = 16, profile = "main") do io
        for i in 2:steps
            push!(trail[], Point2f(lon[i], lat[i]))
            whale[] = Point2f(lon[i],lat[i])
            ## rot[] = Vec2f(lon[i-1]-lon[i], lat[i-1] - lat[i])
            trail[] = trail[]
            recordframe!(io)  # record a new frame
        end
    end
    nothing # hide
end

# !!! info
#       Whale shark movements in Gulf of Mexico.
#       Contact person: Eric Hoffmayer

# ![type:video](./assets/whale_shark_128786.mp4)