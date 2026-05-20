using Tyler, Rasters, Proj, GLMakie
using Tyler: AbstractProvider, ElevationProvider, ElevationData, MapTiles, TileProviders
using Tyler.MapTiles: Tile, web_mercator
using Tyler.Makie: RGBf, RGBAf
using Rasters: Raster, X, Y, Near, Extents
using Rasters.GeoFormatTypes: EPSG

# Reuse ElevationProvider for terrain+satellite; blend a user Raster on top.
struct RasterOverlayProvider{R,C} <: AbstractProvider
    elevation::ElevationProvider
    raster::R
    colormap::C  # value -> RGBAf; returned alpha is the blend weight
end

RasterOverlayProvider(raster, colormap; color_provider=TileProviders.Esri(:WorldImagery)) =
    RasterOverlayProvider(ElevationProvider(color_provider), raster, colormap)

for f in (:options, :min_zoom, :max_zoom)
    @eval TileProviders.$f(p::RasterOverlayProvider) = TileProviders.$f(p.elevation)
end
TileProviders.geturl(p::RasterOverlayProvider, x::Integer, y::Integer, z::Integer) =
    TileProviders.geturl(p.elevation, x, y, z)
for f in (:get_tile_format, :file_ending, :get_downloader)
    @eval Tyler.$f(p::RasterOverlayProvider) = Tyler.$f(p.elevation)
end

function Tyler.fetch_tile(p::RasterOverlayProvider, dl::Tyler.AbstractDownloader, tile::Tile)
    data = Tyler.fetch_tile(p.elevation, dl, tile)
    text, rext = MapTiles.extent(tile, web_mercator), Rasters.extent(p.raster)
    Extents.intersects(text, rext) || return data
    color = copy(data.color); h, w = size(color)
    for i in 1:h, j in 1:w
        x = text.X[1] + (j - 0.5f0) / w * (text.X[2] - text.X[1])
        y = text.Y[2] - (i - 0.5f0) / h * (text.Y[2] - text.Y[1])  # row 1 is north
        (rext.X[1] ≤ x ≤ rext.X[2] && rext.Y[1] ≤ y ≤ rext.Y[2]) || continue
        c = p.colormap(p.raster[X=Near(x), Y=Near(y)])
        color[i, j] = (1 - c.alpha) * RGBf(color[i, j]) + c.alpha * RGBf(c.r, c.g, c.b)
    end
    return ElevationData(data.elevation, color, data.elevation_range)
end

# ── Demo: 1 km checkerboard over the Vienna area ──────────────────────────────
xmin, ymin = 1.4724467114597391e6, 5.931869112841214e6
xmax, ymax = 1.505842579930229e6,  5.98091713865471e6
xs, ys = xmin:1000:xmax, ymin:1000:ymax     # 1 km grid in Web Mercator (EPSG:3857)
checker = Float32[(i + j) % 2 for i in eachindex(ys), j in eachindex(xs)]
raster = Raster(checker, (Y(collect(ys)), X(collect(xs))); crs = EPSG(3857))

provider = RasterOverlayProvider(raster,
    v -> v > 0.5 ? RGBAf(1, 0, 0, 0.7) : RGBAf(0, 0, 1, 0.7))

tx = Proj.Transformation("EPSG:3857", "EPSG:4326"; always_xy=true)
ll, ur = tx(xmin, ymin), tx(xmax, ymax)
m = Tyler.Map3D(Tyler.Extent(X=(ll[1], ur[1]), Y=(ll[2], ur[2])); provider=provider)
