
## Greenland ice loss example: animated &amp; interactive {#Greenland-ice-loss-example:-animated-and-interactive}

```julia
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
```


::: info

Ice loss from the Greenland Ice Sheet: 1972-2022.
- Contact person: Alex Gardner &amp; Chad Greene
  

:::

Load ice loss data [courtesy of Chad Greene @ JPL]

```julia
url = "https://github.com/JuliaGeo/JuliaGeoData/blob/365a09596bfca59e0977c20c2c2f566c0b29dbaa/assets/data/iceloss_subset.arrow?raw=true";
resp = HTTP.get(url);
df = DataFrame(Arrow.Table(resp.body));
first(df, 5)
```

<div v-html="`&lt;div&gt;&lt;div style = &quot;float: left;&quot;&gt;&lt;span&gt;5×3 DataFrame&lt;/span&gt;&lt;/div&gt;&lt;div style = &quot;clear: both;&quot;&gt;&lt;/div&gt;&lt;/div&gt;&lt;div class = &quot;data-frame&quot; style = &quot;overflow-x: scroll;&quot;&gt;&lt;table class = &quot;data-frame&quot; style = &quot;margin-bottom: 6px;&quot;&gt;&lt;thead&gt;&lt;tr class = &quot;header&quot;&gt;&lt;th class = &quot;rowNumber&quot; style = &quot;font-weight: bold; text-align: right;&quot;&gt;Row&lt;/th&gt;&lt;th style = &quot;text-align: left;&quot;&gt;X&lt;/th&gt;&lt;th style = &quot;text-align: left;&quot;&gt;Y&lt;/th&gt;&lt;th style = &quot;text-align: left;&quot;&gt;Date&lt;/th&gt;&lt;/tr&gt;&lt;tr class = &quot;subheader headerLastRow&quot;&gt;&lt;th class = &quot;rowNumber&quot; style = &quot;font-weight: bold; text-align: right;&quot;&gt;&lt;/th&gt;&lt;th title = &quot;SubArray{Float64, 1, Arrow.Primitive{Float64, Vector{Float64}}, Tuple{UnitRange{Int64}}, true}&quot; style = &quot;text-align: left;&quot;&gt;SubArray…&lt;/th&gt;&lt;th title = &quot;SubArray{Float64, 1, Arrow.Primitive{Float64, Vector{Float64}}, Tuple{UnitRange{Int64}}, true}&quot; style = &quot;text-align: left;&quot;&gt;SubArray…&lt;/th&gt;&lt;th title = &quot;Dates.DateTime&quot; style = &quot;text-align: left;&quot;&gt;DateTime&lt;/th&gt;&lt;/tr&gt;&lt;/thead&gt;&lt;tbody&gt;&lt;tr&gt;&lt;td class = &quot;rowNumber&quot; style = &quot;font-weight: bold; text-align: right;&quot;&gt;1&lt;/td&gt;&lt;td style = &quot;text-align: left;&quot;&gt;[-5.86725e6, -5.86687e6, -5.86648e6, -5.86609e6, -5.86753e6, -5.75864e6, -5.7174e6, -5.71703e6, -5.71665e6, -5.71924e6  …  -5.6051e6, -5.60477e6, -5.60444e6, -5.60411e6, -5.60378e6, -5.60345e6, -5.60312e6, -5.60279e6, -5.60246e6, -5.60213e6]&lt;/td&gt;&lt;td style = &quot;text-align: left;&quot;&gt;[1.17525e7, 1.17526e7, 1.17526e7, 1.17527e7, 1.17517e7, 1.1661e7, 1.15656e7, 1.15656e7, 1.15657e7, 1.1565e7  …  1.07214e7, 1.07214e7, 1.07214e7, 1.07215e7, 1.07215e7, 1.07215e7, 1.07215e7, 1.07216e7, 1.07216e7, 1.07216e7]&lt;/td&gt;&lt;td style = &quot;text-align: left;&quot;&gt;1972-10-15T00:00:00&lt;/td&gt;&lt;/tr&gt;&lt;tr&gt;&lt;td class = &quot;rowNumber&quot; style = &quot;font-weight: bold; text-align: right;&quot;&gt;2&lt;/td&gt;&lt;td style = &quot;text-align: left;&quot;&gt;[-5.8672e6, -5.86681e6, -5.86643e6, -5.86748e6, -5.76523e6, -5.71736e6, -5.71699e6, -5.71661e6, -5.7192e6, -5.71882e6  …  -5.60639e6, -5.60606e6, -5.60573e6, -5.6054e6, -5.60507e6, -5.60408e6, -5.60375e6, -5.60342e6, -5.60309e6, -5.60276e6]&lt;/td&gt;&lt;td style = &quot;text-align: left;&quot;&gt;[1.17521e7, 1.17522e7, 1.17522e7, 1.17513e7, 1.16579e7, 1.15652e7, 1.15652e7, 1.15653e7, 1.15646e7, 1.15647e7  …  1.07209e7, 1.07209e7, 1.0721e7, 1.0721e7, 1.0721e7, 1.07211e7, 1.07212e7, 1.07212e7, 1.07212e7, 1.07212e7]&lt;/td&gt;&lt;td style = &quot;text-align: left;&quot;&gt;1972-11-15T00:00:00&lt;/td&gt;&lt;/tr&gt;&lt;tr&gt;&lt;td class = &quot;rowNumber&quot; style = &quot;font-weight: bold; text-align: right;&quot;&gt;3&lt;/td&gt;&lt;td style = &quot;text-align: left;&quot;&gt;[-5.86715e6, -5.71732e6, -5.71694e6, -5.71657e6, -5.71765e6, -5.72354e6, -5.72316e6, -5.71865e6, -5.72633e6, -5.72729e6  …  -5.56852e6, -5.5695e6, -5.5639e6, -5.56258e6, -5.56271e6, -5.60087e6, -5.60441e6, -5.60372e6, -5.60339e6, -5.60306e6]&lt;/td&gt;&lt;td style = &quot;text-align: left;&quot;&gt;[1.17517e7, 1.15648e7, 1.15649e7, 1.15649e7, 1.15644e7, 1.15626e7, 1.15627e7, 1.15632e7, 1.15604e7, 1.15588e7  …  1.08169e7, 1.08165e7, 1.08143e7, 1.08107e7, 1.08083e7, 1.07224e7, 1.07211e7, 1.07208e7, 1.07209e7, 1.07209e7]&lt;/td&gt;&lt;td style = &quot;text-align: left;&quot;&gt;1972-12-15T00:00:00&lt;/td&gt;&lt;/tr&gt;&lt;tr&gt;&lt;td class = &quot;rowNumber&quot; style = &quot;font-weight: bold; text-align: right;&quot;&gt;4&lt;/td&gt;&lt;td style = &quot;text-align: left;&quot;&gt;[-5.71728e6, -5.7169e6, -5.71653e6, -5.71761e6, -5.71941e6, -5.71903e6, -5.63901e6, -5.62706e6, -5.59818e6, -5.59062e6, -5.59024e6, -5.58989e6, -5.59155e6, -5.56301e6, -5.60474e6, -5.60405e6]&lt;/td&gt;&lt;td style = &quot;text-align: left;&quot;&gt;[1.15645e7, 1.15645e7, 1.15645e7, 1.1564e7, 1.15631e7, 1.15631e7, 1.12759e7, 1.12427e7, 1.10848e7, 1.10753e7, 1.1075e7, 1.1075e7, 1.09937e7, 1.0808e7, 1.07211e7, 1.07208e7]&lt;/td&gt;&lt;td style = &quot;text-align: left;&quot;&gt;1973-01-15T00:00:00&lt;/td&gt;&lt;/tr&gt;&lt;tr&gt;&lt;td class = &quot;rowNumber&quot; style = &quot;font-weight: bold; text-align: right;&quot;&gt;5&lt;/td&gt;&lt;td style = &quot;text-align: left;&quot;&gt;[-5.71724e6, -5.71686e6, -5.71795e6, -5.59853e6, -5.59027e6, -5.58992e6, -5.59152e6, -5.60438e6]&lt;/td&gt;&lt;td style = &quot;text-align: left;&quot;&gt;[1.15641e7, 1.15641e7, 1.15636e7, 1.10848e7, 1.10753e7, 1.10753e7, 1.09934e7, 1.07208e7]&lt;/td&gt;&lt;td style = &quot;text-align: left;&quot;&gt;1973-02-15T00:00:00&lt;/td&gt;&lt;/tr&gt;&lt;/tbody&gt;&lt;/table&gt;&lt;/div&gt;`"></div>

select map provider

```julia
provider = TileProviders.Esri(:WorldImagery);
```


```ansi
[33m[1m┌ [22m[39m[33m[1mWarning: [22m[39mError while fetching tile on thread 1
[33m[1m│ [22m[39m  exception =
[33m[1m│ [22m[39m   RequestError: Operation timed out after 3106 milliseconds with 0 bytes received while requesting https://tile.opentopomap.org/10/511/340.png
[33m[1m│ [22m[39m   Stacktrace:
[33m[1m│ [22m[39m     [1] [0m[1m(::Downloads.var"#9#19"{IOBuffer, Base.DevNull, Nothing, Vector{Pair{String, String}}, Float64, Nothing, Bool, Nothing, Bool, Nothing, String, Bool, Bool})[22m[0m[1m([22m[90measy[39m::[0mDownloads.Curl.Easy[0m[1m)[22m
[33m[1m│ [22m[39m   [90m    @[39m [35mDownloads[39m [90m/opt/hostedtoolcache/julia/1.11.5/x64/share/julia/stdlib/v1.11/Downloads/src/[39m[90m[4mDownloads.jl:452[24m[39m
[33m[1m│ [22m[39m     [2] [0m[1mwith_handle[22m[0m[1m([22m[90mf[39m::[0mDownloads.var"#9#19"[90m{IOBuffer, Base.DevNull, Nothing, Vector{Pair{String, String}}, Float64, Nothing, Bool, Nothing, Bool, Nothing, String, Bool, Bool}[39m, [90mhandle[39m::[0mDownloads.Curl.Easy[0m[1m)[22m
[33m[1m│ [22m[39m   [90m    @[39m [35mDownloads.Curl[39m [90m/opt/hostedtoolcache/julia/1.11.5/x64/share/julia/stdlib/v1.11/Downloads/src/Curl/[39m[90m[4mCurl.jl:105[24m[39m
[33m[1m│ [22m[39m     [3] [0m[1m#8[22m
[33m[1m│ [22m[39m   [90m    @[39m [90m/opt/hostedtoolcache/julia/1.11.5/x64/share/julia/stdlib/v1.11/Downloads/src/[39m[90m[4mDownloads.jl:363[24m[39m[90m [inlined][39m
[33m[1m│ [22m[39m     [4] [0m[1marg_write[22m[0m[1m([22m[90mf[39m::[0mDownloads.var"#8#18"[90m{Base.DevNull, Nothing, Vector{Pair{String, String}}, Float64, Nothing, Bool, Nothing, Bool, Nothing, String, Bool, Bool}[39m, [90marg[39m::[0mIOBuffer[0m[1m)[22m
[33m[1m│ [22m[39m   [90m    @[39m [36mArgTools[39m [90m/opt/hostedtoolcache/julia/1.11.5/x64/share/julia/stdlib/v1.11/ArgTools/src/[39m[90m[4mArgTools.jl:134[24m[39m
[33m[1m│ [22m[39m     [5] [0m[1m#7[22m
[33m[1m│ [22m[39m   [90m    @[39m [90m/opt/hostedtoolcache/julia/1.11.5/x64/share/julia/stdlib/v1.11/Downloads/src/[39m[90m[4mDownloads.jl:362[24m[39m[90m [inlined][39m
[33m[1m│ [22m[39m     [6] [0m[1marg_read[22m
[33m[1m│ [22m[39m   [90m    @[39m [90m/opt/hostedtoolcache/julia/1.11.5/x64/share/julia/stdlib/v1.11/ArgTools/src/[39m[90m[4mArgTools.jl:76[24m[39m[90m [inlined][39m
[33m[1m│ [22m[39m     [7] [0m[1mrequest[22m[0m[1m([22m[90murl[39m::[0mString; [90minput[39m::[0mNothing, [90moutput[39m::[0mIOBuffer, [90mmethod[39m::[0mNothing, [90mheaders[39m::[0mVector[90m{Pair{String, String}}[39m, [90mtimeout[39m::[0mFloat64, [90mprogress[39m::[0mNothing, [90mverbose[39m::[0mBool, [90mdebug[39m::[0mNothing, [90mthrow[39m::[0mBool, [90mdownloader[39m::[0mDownloads.Downloader, [90minterrupt[39m::[0mNothing[0m[1m)[22m
[33m[1m│ [22m[39m   [90m    @[39m [35mDownloads[39m [90m/opt/hostedtoolcache/julia/1.11.5/x64/share/julia/stdlib/v1.11/Downloads/src/[39m[90m[4mDownloads.jl:361[24m[39m
[33m[1m│ [22m[39m     [8] [0m[1mrequest[22m
[33m[1m│ [22m[39m   [90m    @[39m [90m/opt/hostedtoolcache/julia/1.11.5/x64/share/julia/stdlib/v1.11/Downloads/src/[39m[90m[4mDownloads.jl:328[24m[39m[90m [inlined][39m
[33m[1m│ [22m[39m     [9] [0m[1m#3[22m
[33m[1m│ [22m[39m   [90m    @[39m [90m/opt/hostedtoolcache/julia/1.11.5/x64/share/julia/stdlib/v1.11/Downloads/src/[39m[90m[4mDownloads.jl:259[24m[39m[90m [inlined][39m
[33m[1m│ [22m[39m    [10] [0m[1marg_write[22m[0m[1m([22m[90mf[39m::[0mDownloads.var"#3#4"[90m{Nothing, Vector{Pair{String, String}}, Float64, Nothing, Bool, Nothing, Downloads.Downloader, String}[39m, [90marg[39m::[0mIOBuffer[0m[1m)[22m
[33m[1m│ [22m[39m   [90m    @[39m [36mArgTools[39m [90m/opt/hostedtoolcache/julia/1.11.5/x64/share/julia/stdlib/v1.11/ArgTools/src/[39m[90m[4mArgTools.jl:134[24m[39m
[33m[1m│ [22m[39m    [11] [0m[1m#download#2[22m
[33m[1m│ [22m[39m   [90m    @[39m [90m/opt/hostedtoolcache/julia/1.11.5/x64/share/julia/stdlib/v1.11/Downloads/src/[39m[90m[4mDownloads.jl:258[24m[39m[90m [inlined][39m
[33m[1m│ [22m[39m    [12] [0m[1mdownload[22m
[33m[1m│ [22m[39m   [90m    @[39m [90m/opt/hostedtoolcache/julia/1.11.5/x64/share/julia/stdlib/v1.11/Downloads/src/[39m[90m[4mDownloads.jl:247[24m[39m[90m [inlined][39m
[33m[1m│ [22m[39m    [13] [0m[1mdownload_tile_data[22m[0m[1m([22m[90mdl[39m::[0mTyler.ByteDownloader, [90mprovider[39m::[0mTileProviders.Provider, [90murl[39m::[0mString[0m[1m)[22m
[33m[1m│ [22m[39m   [90m    @[39m [32mTyler[39m [90m~/work/Tyler.jl/Tyler.jl/src/[39m[90m[4mdownloader.jl:19[24m[39m
[33m[1m│ [22m[39m    [14] [0m[1mfetch_tile[22m
[33m[1m│ [22m[39m   [90m    @[39m [90m~/work/Tyler.jl/Tyler.jl/src/provider/[39m[90m[4mshared.jl:10[24m[39m[90m [inlined][39m
[33m[1m│ [22m[39m    [15] [0m[1m(::Tyler.var"#20#21"{Tyler.ByteDownloader, TileProviders.Provider, MapTiles.Tile})[22m[0m[1m([22m[0m[1m)[22m
[33m[1m│ [22m[39m   [90m    @[39m [32mTyler[39m [90m~/work/Tyler.jl/Tyler.jl/src/[39m[90m[4mtile-cache.jl:93[24m[39m
[33m[1m│ [22m[39m    [16] [0m[1mget![22m[0m[1m([22m[90mdefault[39m::[0mTyler.var"#20#21"[90m{Tyler.ByteDownloader, TileProviders.Provider, MapTiles.Tile}[39m, [90mlru[39m::[0mLRUCache.LRU[90m{String, Union{Nothing, Matrix{ColorTypes.RGB{FixedPointNumbers.N0f8}}}}[39m, [90mkey[39m::[0mString[0m[1m)[22m
[33m[1m│ [22m[39m   [90m    @[39m [33mLRUCache[39m [90m~/.julia/packages/LRUCache/ZH7qB/src/[39m[90m[4mLRUCache.jl:169[24m[39m
[33m[1m│ [22m[39m    [17] [0m[1mrun_loop[22m[0m[1m([22m[90mdl[39m::[0mTyler.ByteDownloader, [90mtile_queue[39m::[0mChannel[90m{MapTiles.Tile}[39m, [90mfetched_tiles[39m::[0mLRUCache.LRU[90m{String, Union{Nothing, Matrix{ColorTypes.RGB{FixedPointNumbers.N0f8}}}}[39m, [90mprovider[39m::[0mTileProviders.Provider, [90mdownloaded_tiles[39m::[0mChannel[90m{Tuple{MapTiles.Tile, Union{Nothing, Matrix{ColorTypes.RGB{FixedPointNumbers.N0f8}}}}}[39m[0m[1m)[22m
[33m[1m│ [22m[39m   [90m    @[39m [32mTyler[39m [90m~/work/Tyler.jl/Tyler.jl/src/[39m[90m[4mtile-cache.jl:91[24m[39m
[33m[1m│ [22m[39m    [18] [0m[1m(::Tyler.var"#8#11"{TileProviders.Provider, Channel{MapTiles.Tile}, Channel{Tuple{MapTiles.Tile, Union{Nothing, Matrix{ColorTypes.RGB{FixedPointNumbers.N0f8}}}}}, LRUCache.LRU{String, Union{Nothing, Matrix{ColorTypes.RGB{FixedPointNumbers.N0f8}}}}, Tyler.ByteDownloader})[22m[0m[1m([22m[0m[1m)[22m
[33m[1m│ [22m[39m   [90m    @[39m [32mTyler[39m [90m~/work/Tyler.jl/Tyler.jl/src/[39m[90m[4mtile-cache.jl:27[24m[39m
[33m[1m└ [22m[39m[90m@ Tyler ~/work/Tyler.jl/Tyler.jl/src/tile-cache.jl:106[39m
```


Greenland extent

```julia
extent = Extent(X = (-54., -48.), Y = (68.8, 72.5));
```


```ansi
Extent(X = (-54.0, -48.0), Y = (68.8, 72.5))
```


extract data

```julia
cnt = [length(foo) for foo in df.X];
X =  reduce(vcat,df.X);
Y =  reduce(vcat,df.Y);
Z = [repeat([i],c) for (i, c) = enumerate(cnt)];
Z = reduce(vcat,Z);
```


make a colormap

```julia
nc = length(Makie.to_colormap(:thermal));
n = nrow(df);
alpha = zeros(nc);
alpha[1:maximum([1,round(Int64,1*nc/n)])] = alpha[1:maximum([1,round(Int64,1*nc/n)])] .* (1.05^-1.5);
alpha[maximum([1,round(Int64,1*nc/n)])] = 1;
cmap = Colors.alphacolor.(Makie.to_colormap(:thermal), alpha);
cmap = Observable(cmap);
```


show map

```julia
fig = Figure(; size = (1200,600))
ax = Axis(fig[1,1])
m = Tyler.Map(extent; provider, figure=fig, axis=ax)
```

![](lpmnlbo.png){width=1200px height=600px}

create initial scatter plot

```julia
scatter!(ax, X, Y; color = Z, colormap = cmap, colorrange = [0, n], markersize = 10);
m
```

![](zcsdolk.png){width=1200px height=600px}

add colorbar

```julia
a,b = extrema(df.Date);
a = year(a);
b = year(b);
Colorbar(fig[1,2]; colormap = cmap, colorrange = [a,b],
    height=Relative(0.5), width = 15)
# hide ticks, grid and lables
hidedecorations!(ax);
# hide frames
hidespines!(ax);
m
```

![](ueotfqp.png){width=1200px height=600px}

loop to create animation

```julia
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
```

<video src="https://github.com/JuliaGeo/JuliaGeoData/raw/main/assets/videos/iceloss.mp4" controls="controls" autoplay="autoplay" ></video>

