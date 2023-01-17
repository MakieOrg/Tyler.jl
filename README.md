# Tyler

[![Latest Docs](https://img.shields.io/badge/docs-latest-blue.svg)](https://makieorg.github.io/Tyler.jl/dev/)

[Tyler.jl](https://makieorg.github.io/Tyler.jl/dev/) is package for displaying tiled maps interactively, with [Makie.jl](https://github.com/MakieOrg/Makie.jl).

Install like this until deps are registered:

```julia
]add https://github.com/JuliaGeo/TileProviders.jl https://github.com/JuliaGeo/MapTiles.jl https://github.com/MakieOrg/Tyler.jl.git
```
```julia
using Tyler, GLMakie
tyler = Tyler.Map(Rect2f(-0.0921, 51.5, 0.04, 0.025))
```
<img width="749" alt="image" src="https://user-images.githubusercontent.com/1010467/212502640-b44454b1-2d05-4469-b509-d895b30b145a.png">

## Integration with OSMMakie & Google satelite provider

https://user-images.githubusercontent.com/1010467/212502607-640a2238-0f24-4efd-8ce9-fafba46f80bd.mp4
