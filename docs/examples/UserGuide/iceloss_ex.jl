using Tyler
using GLMakie
using Arrow
using DataFrames
using TileProviders
using Extents
using ColorSchemes
using Colors
using Dates

url = joinpath("src/assets/data/iceloss_subset.arrow")

## parameter for scaling figure size
scale = 1;

## load ice loss data [courtesy of Chad Greene @ JPL]
df = DataFrame(Arrow.Table(url));

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
cmap = ColorSchemes.thermal.colors;
nc = length(cmap);
alpha = zeros(nc);
cmap = RGBA.(cmap, alpha);
cmap0 = Observable(cmap);

## add frame
frame = Rect2f(extent.X[1], extent.Y[1], extent.X[2] - extent.X[1], extent.Y[2] - extent.Y[1]);

## show map
m = Tyler.Map(frame; provider, figure=Figure(resolution=(1912 * scale, 2284 * scale)));

## create initial scatter plot
n = nrow(df);
scatter!(m.axis, X, Y; color = Z, colormap = cmap0, colorrange = [0, n], markersize = 10);

# add color bar
a,b = extrema(df.Date);
a = year(a);
b = year(b);
Colorbar(m.figure[1,2]; colormap = cmap0, colorrange = [a,b], 
    ticklabelsize = 50 * scale, width = 100 * scale);

## hide ticks, grid and lables
hidedecorations!(m.axis);

## hide frames
hidespines!(m.axis);

## loop to create animation
for k = 1:15

    # reset apha
    i = 1;
    cmap = ColorSchemes.thermal.colors;
    alpha = zeros(length(cmap));
    cmap0[] = RGBA.(cmap, alpha);

    for i in 2:1:n
         # modify alpha
        alpha[1:maximum([1,round(Int64,i*nc/n)])] = alpha[1:maximum([1,round(Int64,i*nc/n)])] .* (1.05^-1.5);
        alpha[maximum([1,round(Int64,i*nc/n)])] = 1;
        cmap0[] = RGBA.(ColorSchemes.thermal.colors, alpha);
        sleep(0.001);
    end
end

# !!! info
#       Ice loss from the Greenland Ice Sheet: 1972-2022.
#       Contact person: Alex Gardner & Chad Greene

# ![type:video]("src/assets/iceloss.mp4)