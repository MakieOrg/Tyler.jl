using GeometryBasics, GLMakie, Tyler, TileProviders
using Tyler: ElevationProvider, GeoTilePointCloudProvider

begin
    lat, lon = (52.395593, 4.884704)
    delta = 0.01
    ext = Rect2f(lon-delta/2, lat-delta/2, delta, delta)
    m1 = Tyler.Map(ext; download_threads=3, fetching_scheme=Tyler.SimpleTiling())
    display(m1.figure.scene)
end

begin
    lat, lon = (52.395593, 4.884704)
    delta = 0.01
    ext = Rect2f(lon - delta / 2, lat - delta / 2, delta, delta)
    m1 = Tyler.Map(ext; download_threads=1)
    display(m1.figure.scene)
end

for (key, (pl, tile, rect)) in m1.plots
    if haskey(m1.current_tiles, tile)
    else
        lines!(m1.axis.scene, Rect2f(boundingbox(pl)); color=:black, depth_shift=-0.1f0)
    end
end
using MapTiles, TileProviders

m.plots
m.current_tiles
new_tiles = Tyler.get_tiles_for_area(m1, m1.fetching_scheme, m1.axis.finallimits[])

for (tile, _) in m1.current_tiles
    key = TileProviders.geturl(m1.provider, tile.x, tile.y, tile.z)
    if haskey(m1.plots, key)
        pl, tile, rect = m1.plots[key]
        lines!(m1.axis.scene, rect; depth_shift=-0.2f0, color=:red, linewidth=2)
    else
        println("not plotted")
    end
end
using ArchGDAL, ImageShow
path = download("https://elevation3d.arcgis.com/arcgis/rest/services/WorldElevation3D/Terrain3D/ImageServer/tile/13/2879/4400")
dataset = ArchGDAL.read(path)

files = readdir(joinpath(Tyler.CACHE_PATH[], "ElevationProvider"), join=true)
file = files[1]
using ArchGDAL
using ImageShow
ArchGDAL.imread(files[8])
dataset = ArchGDAL.read(files[])
ArchGDAL.imread(files[8])
path = joinpath(Tyler.CACHE_PATH[], "ElevationProvider", "7140221712337353296.tiff")
using GMT, Colors
G = gmtread(path; gdal=true, grid=true)
Gray.(collect(G)./255)
TiffImages.load(path)
ArchGDAL.readraster(path)
begin
    # lat, lon = (40.697211, -74.037523)
    lat, lon = (52.395593, 4.884704)
    # lat, lon = (53.208252, 5.169539)
    # lat, lon = (55.648466, 12.566546)
    lat, lon = (47.087441, 13.377214)
    delta = 0.1
    ext = Rect2f(lon-delta/2, lat-delta/2, delta, delta)
    m = Tyler.Map3D(ext; provider=ElevationProvider())
    display(m.figure.scene)
end


m.axis.scene.plots[1] |> Makie.data_limits
m.axis.scene.plots[1] |> Makie.boundingbox

ext = MapTiles.project_extent(Extents.extent(ext), Tyler.wgs84, m.crs)

HyperRectangle{2,Float64}([1.4810655658345383e6, 5.95143750227259e6], [16158.279261035612, 15891.41651593335])
using GeoArrays
geoarray = GeoArrays.read(path)
Gray.(collect(geoarray) ./ 255)
dataset = ArchGDAL.read(path)
ArchGDAL.getdriver(dataset)
using GDAL_jll
run(`$(gdal_translate_path()) -of COG $(path) output.tif`)
begin
    lat, lon = (52.395593, 4.884704)
    delta = 0.01
    ext = Rect2f(lon - delta / 2, lat - delta / 2, delta, delta)
    cfg = Tyler.PlotConfig(
        preprocess=pc -> map(point-> point .* Point3f(1, 1, 5), pc),
        postprocess=p -> translate!(p, 0, 0, 40),
    )
    subset="AHN1_T" # Takes reasonably long to load (~1-5mb compressed per tile)
    subset="AHN4_T" # Takes _really_ long to load, even from disk (~300mb compressed points per tile)
    provider = GeoTilePointCloudProvider(subset=subset)
    image = TileProviders.Esri(:WorldImagery)
    m1 = Tyler.Map3D(ext; provider=provider, plot_config=cfg)
    m2 = Tyler.Map3D(ext; figure=m1.figure, axis=m1.axis, provider=image)
    # m1 = Tyler.Map3D(ext; plot_config=Tyler.DebugPlotConfig())
    display(m1.figure.scene)
end

function cleanup_queue!(queue, to_keep)
    lock(queue) do
        queued = queue.data
        filter!(queued) do tile
            if !(tile in to_keep)
                Base._increment_n_avail(queue, -1)
                return false
            else
                return true
            end
        end
    end
end

channel = Channel{Int}(Inf) do ch
    for el in ch
        println("got $el")
        sleep(0.5)
    end
end
foreach(i-> put!(channel, i), 1:1000)

cleanup_queue!(channel, [])
