# Tyler

Install like this until deps are registered:

```julia
]add https://github.com/JuliaGeo/TileProviders.jl https://github.com/SimonDanisch/MapTiles.jl.git https://github.com/MakieOrg/Tyler.jl.git
```
```julia
using Tyler
using GLMakie
Tyler.Map(Rect2f(-0.0921, 51.5, 0.04, 0.025))
```
