using GLMakie
using Tyler
using Tyler.TileProviders
using Tyler.Extents
# https://github.com/JuliaGeo/TileProviders.jl/issues/9

mars = Provider("https://api.nasa.gov/mars-wmts/catalog/Mars_Viking_MDIM21_ClrMosaic_global_232m/1.0.0//default/default028mm/{z}/{y}/{x}.jpg")

moon =  Provider("https://trek.nasa.gov/tiles/Moon/EQ/LRO_WAC_Mosaic_Global_303ppd_v02/1.0.0/default/default028mm/{z}/{y}/{x}.jpg")

mexico = Rect2f(-99.20618766110033, 19.425887652841997, 0.03, 0.02)
provider = TileProviders.OpenTopoMap()

fig1 = Figure(; figure_padding=0, size= (600,600))
ax1 = Axis(fig1[1,1]; ygridcolor=:silver, xgridcolor=:white,
     xgridwidth=2, ygridwidth=2)
m1 = Tyler.Map(mexico; provider=provider, figure=fig1, axis=ax1)
wait(m1)
hidedecorations!(ax1; grid=false)
hidespines!(ax1)
img_mexico = copy(Makie.colorbuffer(fig1))

berlin = Rect2f(13.38075834982224,52.5043667460351, 0.04, 0.025)
fig2 = Figure(; figure_padding=0, size= (600,600))
ax1 = Axis(fig2[1,1]; ygridcolor=:silver, xgridcolor=:white,
     xgridwidth=2, ygridwidth=2)
m1 = Tyler.Map(berlin; figure=fig2, axis=ax1)
wait(m1)
hidedecorations!(ax1; grid=false)
hidespines!(ax1)
img_berlin = copy(Makie.colorbuffer(fig2))

london = Rect2f(-0.0921, 51.5, 0.04, 0.025)
provider = TileProviders.OpenTopoMap()
fig3 = Figure(; figure_padding=0, size= (600,600))
ax1 = Axis(fig3[1,1]; ygridcolor=:silver, xgridcolor=:white,
     xgridwidth=2, ygridwidth=2)
m1 = Tyler.Map(london; provider=provider, figure=fig3, axis=ax1)
wait(m1)
hidedecorations!(ax1; grid=false)
hidespines!(ax1)
img_london = copy(Makie.colorbuffer(fig3))

# using CairoMakie
# CairoMakie.activate!()
fig = with_theme(theme_minimal()) do
    fig = Figure(;figure_padding=0, size=(1000, 1000))
    ax = Axis3(fig[1, 1]; aspect=(1, 1, 1),
        elevation=π/6, perspectiveness=0.5)
    # transformations into planes
    image!(ax, -3.2 .. 3.2, -3.2 .. 3.2, rotr90(img_mexico);
        transformation=(:yz, 3.5))
    image!(ax, -3.2 .. 3.2, -3.2 .. 3.2, rotr90(img_berlin);
        transformation=(:xy, -3.5))
    image!(ax, -3.2 .. 3.2, -3.2 .. 3.2, rotr90(img_london);
        transformation=(:xz, 3.5))
    xlims!(ax, -3.4, 3.4)
    ylims!(ax, -3.4, 3.4)
    zlims!(ax, -3.4, 3.4)
    hidedecorations!(ax; grid=false)
    hidespines!(ax)
    fig
end
mkpath(joinpath(@__DIR__, "src", "assets"))
#save(joinpath(@__DIR__, "src", "assets", "logo_raw.svg"), fig; pt_per_unit=0.75)
save(joinpath(@__DIR__, "src", "assets", "logo_raw.png"), fig; px_per_unit=2)
#save(joinpath(@__DIR__, "src", "assets", "favicon_raw.png"), fig; px_per_unit=0.25)