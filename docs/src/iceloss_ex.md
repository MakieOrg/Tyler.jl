## Greenland ice loss example: animated & interactive

````@example ice
using Tyler
using Tyler.TileProviders
using Tyler.Extents
using Dates
using HTTP
using Arrow
using DataFrames
using GLMakie
using GLMakie.Colors
GLMakie.activate!()
````

::: info

Ice loss from the Greenland Ice Sheet: 1972-2022.

- Contact person: Alex Gardner & Chad Greene

:::

Load ice loss data [courtesy of Chad Greene @ JPL]

````@example ice
url = "https://github.com/JuliaGeo/JuliaGeoData/blob/365a09596bfca59e0977c20c2c2f566c0b29dbaa/assets/data/iceloss_subset.arrow?raw=true";
resp = HTTP.get(url);
df = DataFrame(Arrow.Table(resp.body));
first(df, 5)
````
select map provider

````@example ice
provider = TileProviders.Esri(:WorldImagery);
nothing # hide
````

Greenland extent

````@example ice
extent = Extent(X = (-54., -48.), Y = (68.8, 72.5));
````
extract data

````@example ice
cnt = [length(foo) for foo in df.X];
X =  reduce(vcat,df.X);
Y =  reduce(vcat,df.Y);
Z = [repeat([i],c) for (i, c) = enumerate(cnt)];
Z = reduce(vcat,Z);
nothing # hide
````

make a colormap

````@example ice
nc = length(Makie.to_colormap(:thermal));
n = nrow(df);
alpha = zeros(nc);
alpha[1:maximum([1,round(Int64,1*nc/n)])] = alpha[1:maximum([1,round(Int64,1*nc/n)])] .* (1.05^-1.5);
alpha[maximum([1,round(Int64,1*nc/n)])] = 1;
cmap = Colors.alphacolor.(Makie.to_colormap(:thermal), alpha);
cmap = Observable(cmap);
nothing # hide
````
show map

````@example ice
fig = Figure(; size = (1200,600))
ax = Axis(fig[1,1])
m = Tyler.Map(extent; provider, figure=fig, axis=ax);
wait(m)
save("ice_loss1.png", current_figure()) # hide
nothing # hide
````

![](ice_loss1.png)

create initial scatter plot

````@example ice
scatter!(ax, X, Y; color = Z, colormap = cmap, colorrange = [0, n], markersize = 10);
save("ice_loss2.png", current_figure()) # hide
nothing # hide
````
![](ice_loss2.png)

add colorbar

````@example ice
a,b = extrema(df.Date);
a = year(a);
b = year(b);
Colorbar(fig[1,2]; colormap = cmap, colorrange = [a,b],
    height=Relative(0.5), width = 15)
# hide ticks, grid and lables
hidedecorations!(ax);
# hide frames
hidespines!(ax);
# wait for tiles to fully load
wait(m)
save("ice_loss3.png", current_figure()) # hide
nothing # hide
````
![](ice_loss3.png)

loop to create animation 
````julia
for k = 1:15 
    # reset apha
    alpha[:] = zeros(nc);
    cmap[] = Colors.alphacolor.(cmap[], alpha)
    for i in 2:1:n 
        # modify alpha
        alpha[1:maximum([1,round(Int64,i*nc/n)])] = alpha[1:maximum([1,round(Int64,i*nc/n)])] .* (1.05^-1.5);
        alpha[maximum([1,round(Int64,i*nc/n)])] = 1;
        cmap[] = Colors.alphacolor.(cmap[], alpha);
        sleep(0.001);
    end 
end
````

```@raw html
<video src="https://github.com/JuliaGeo/JuliaGeoData/raw/main/assets/videos/iceloss.mp4" controls="controls" autoplay="autoplay" ></video>
```