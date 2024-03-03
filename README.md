[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](https://makieorg.github.io/Tyler.jl/blob/main/LICENSE)
[![Latest Docs](https://img.shields.io/badge/docs-latest-blue.svg)](https://makieorg.github.io/Tyler.jl/dev/)
[![Downloads](https://shields.io/endpoint?url=https://pkgs.genieframework.com/api/v1/badge/Tyler&label=Downloads)](https://pkgs.genieframework.com?packages=Tyler)

## What is Tyler.jl ?

[Tyler.jl](https://makieorg.github.io/Tyler.jl/dev/) is package for displaying tiled maps interactively, with [Makie.jl](https://github.com/MakieOrg/Makie.jl).

<img src="/docs/src/assets/logo.png" align="right" style="padding-left:10px;" width="200"/>

> [!TIP]
> Visit the latest documentation at https://makieorg.github.io/Tyler.jl/dev/

> [!IMPORTANT]
> Become a Sponsor. [Support](https://makie.org/support/) this project.

## Install

Install `Tyler` and `GLMakie`

```julia
]add Tyler, GLMakie
```
```julia
using Tyler, GLMakie
tyler = Tyler.Map(Rect2f(-0.0921, 51.5, 0.04, 0.025))
```
<img width="749" alt="image" src="https://user-images.githubusercontent.com/1010467/212502640-b44454b1-2d05-4469-b509-d895b30b145a.png">

## Integration with OSMMakie & Google satelite provider

https://user-images.githubusercontent.com/1010467/212502607-640a2238-0f24-4efd-8ce9-fafba46f80bd.mp4
