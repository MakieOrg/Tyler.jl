# # Using Interpolation On The Fly

using Tyler, GLMakie
using Interpolations: interpolate, Gridded, Linear

nodes=(-180.0:180.0, -90.0:90.0)
array=[cosd(8*lon)+sind(8*lat) for lon in nodes[1], lat in nodes[2]]
array=(array.-minimum(array))./(maximum(array)-minimum(array))

itp = interpolate(nodes, array, Gridded(Linear()))
options = Dict(:min_zoom => 1,:max_zoom => 19)
provider=Tyler.Interpolator(itp,options)

b = Rect2f(-20.0, -20.0, 40.0, 40.0)
m = Tyler.Map(b, provider=provider)

# !!! info
#       Sine Waves

# !!! tip
#       Try `b = Rect2f(-180.0, -89.9, 360.0, 179.8)`
