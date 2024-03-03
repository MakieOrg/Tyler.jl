## Tyler.jl

A package for downloading map tiles on demand from different data source providers.

> [!CAUTION]
> This package is currently in the initial phase of development. It needs support. Sponsorships are welcome!

## Installation

In the Julia REPL type:
```julia
] add Tyler
```
The `]` character starts the Julia [package manager](https://docs.julialang.org/en/v1/stdlib/Pkg/). Hit backspace key to return to Julia prompt.

Or, explicitly use `Pkg` 

```julia
using Pkg
Pkg.add(["Tyler.jl"])
```

## Demo: London

````@example london
using Tyler, GLMakie
m = Tyler.Map(Rect2f(-0.0921, 51.5, 0.04, 0.025))
wait(m)
save("london.png", current_figure()) # hide
nothing # hide
````

![](london.png)

::: info

A `Rect2f` definition takes as input the origin, first two entries, and the width and hight, last two numbers.

:::

## Tile provider
We can use a different tile provider as well as any style `theme` from Makie as follows:

````@example provider

using GLMakie, Tyler
using Tyler.TileProviders

provider = TileProviders.OpenTopoMap()
london = Rect2f(-0.0921, 51.5, 0.04, 0.025)

with_theme(theme_dark()) do
    m = Tyler.Map(london; provider)
    hidedecorations!(m.axis)
    hidespines!(m.axis)
    wait(m)
end
save("londonProvider.png", current_figure()) # hide
nothing # hide
````

![](londonProvider.png)

## Providers list

More providers are available. See the following list:

````@example provider
providers = TileProviders.list_providers()
````

::: info

For some providers additional configuration steps are necessary, look at the `TileProviders.jl` [documentation](https://juliageo.org/TileProviders.jl/dev/) for more information.

:::

## Figure size & aspect ratio

Although, the figure size can be controlled by passing additional arguments to `Map`, it's better to define a Figure first and then continue with a normal Makie's figure creation workflow, namely

````@example provider

using GLMakie, Tyler
using Tyler.TileProviders

provider = TileProviders.OpenTopoMap()
london = Rect2f(-0.0921, 51.5, 0.04, 0.025)

with_theme(theme_dark()) do
    fig = Figure(; size =(1200,600))
    ax = Axis(fig[1,1]) # aspect = DataAspect()
    m = Tyler.Map(london; provider, figure=fig, axis=ax)
    hidedecorations!(ax)
    hidespines!(ax)
    wait(m)
    fig
end
save("londonFigure.png", current_figure()) # hide
nothing # hide
````

![](londonFigure.png)

Next, we could add any other plot type on top of the `ax` axis defined above.