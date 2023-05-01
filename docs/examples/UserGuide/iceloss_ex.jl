# # Greenland ice loss example: animated & interactive

using Tyler
using GLMakie
using Arrow
using DataFrames
using TileProviders
using Extents
using Colors
using Dates
using HTTP

url = "https://github.com/JuliaGeo/JuliaGeoData/blob/365a09596bfca59e0977c20c2c2f566c0b29dbaa/assets/data/iceloss_subset.arrow?raw=true";

## parameter for scaling figure size
scale = 1;

## load ice loss data [courtesy of Chad Greene @ JPL]
resp = HTTP.get(url);
df = DataFrame(Arrow.Table(resp.body));

## select map provider
provider = TileProviders.Esri(:WorldImagery);

## Greenland extent
extent = Extent(X = (-54., -48.), Y = (68.8, 72.5));
        
## extract data
cnt = [length(foo) for foo in df.X];
X =  reduce(vcat,df.X);
Y =  reduce(vcat,df.Y);
Z = [repeat([i],c) for (i, c) = enumerate(cnt)];
Z = reduce(vcat,Z);

## make color map
nc = length(Makie.to_colormap(:thermal));
n = nrow(df);
alpha = zeros(nc);
alpha[1:maximum([1,round(Int64,1*nc/n)])] = alpha[1:maximum([1,round(Int64,1*nc/n)])] .* (1.05^-1.5);
alpha[maximum([1,round(Int64,1*nc/n)])] = 1;
cmap = Colors.alphacolor.(Makie.to_colormap(:thermal), alpha);
cmap = Observable(cmap);

## show map
m = Tyler.Map(extent; provider, figure=Figure(resolution=(1912 * scale, 2284 * scale)));

## create initial scatter plot
scatter!(m.axis, X, Y; color = Z, colormap = cmap, colorrange = [0, n], markersize = 10);

## add color bar
a,b = extrema(df.Date);
a = year(a);
b = year(b);
Colorbar(m.figure[1,2]; colormap = cmap, colorrange = [a,b], ticklabelsize = 50 * scale, width = 100 * scale);

## hide ticks, grid and lables
hidedecorations!(m.axis);

## hide frames
hidespines!(m.axis);

## wait for tiles to fully load
wait(m)

## ------ uncomment to create interactive-animated figure -----
## The Documenter does not allow creations of interactive plots

## loop to create animation 
# if interactive 
#     for k = 1:15 
#         # reset apha
#         alpha[:] = zeros(nc);
#         cmap[] = Colors.alphacolor.(cmap[], alpha)

#         for i in 2:1:n 
#             # modify alpha
#             alpha[1:maximum([1,round(Int64,i*nc/n)])] = alpha[1:maximum([1,round(Int64,i*nc/n)])] .* (1.05^-1.5);
#             alpha[maximum([1,round(Int64,i*nc/n)])] = 1;
#             cmap[] = Colors.alphacolor.(cmap[], alpha);
#             sleep(0.001);
#         end 
#     end
# end
## -----------------------------------------------------------

# !!! info
#       Ice loss from the Greenland Ice Sheet: 1972-2022.
#       Contact person: Alex Gardner & Chad Greene

# ![type:video]("https://github.com/JuliaGeo/JuliaGeoData/raw/main/assets/videos/iceloss.mp4")