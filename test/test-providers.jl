using GeometryBasics, GLMakie, Tyler, TileProviders
using Tyler: ElevationProvider, GeoTilePointCloudProvider
using MapTiles

begin
    lat, lon = (52.395593, 4.884704)
    delta = 0.01
    ext = Rect2f(lon-delta/2, lat-delta/2, delta, delta)
    m1 = Tyler.Map(ext; download_threads=3)
    display(m1.figure.scene)
end

begin
    lat, lon = (52.395593, 4.884704)
    delta = 0.01
    ext = Rect2f(lon - delta / 2, lat - delta / 2, delta, delta)
    m1 = Tyler.Map(ext; download_threads=1)
    display(m1.figure.scene)
end
begin
    # lat, lon = (40.697211, -74.037523)
    lat, lon = (52.377428, 4.898387)
    # lat, lon = (53.208252, 5.169539)
    # lat, lon = (55.648466, 12.566546)
    # lat, lon = (47.087441, 13.377214)
    delta = 0.1
    ext = Rect2f(lon-delta/2, lat-delta/2, delta, delta)
    # cfg = Tyler.PlotConfig(preprocess=pc -> map(p -> p .* 2, pc))
    m = Tyler.Map3D(ext; provider=ElevationProvider())#, plot_config=cfg)
    display(m.figure.scene)
end

for i in 1:1000
    rotate_cam!(m.axis.scene, 0, 0.01, 0)
    sleep(1/60)
end

for (key, (pl, tile, bb)) in m.plots
    if haskey(m.current_tiles, tile)
        pl = linesegments!(m.axis.scene, bb, color=:blue, linewidth=3, depth_shift=-0.2f0)
        translate!(pl, 0, 0, 0.01)
    end
end
m.unused_plots
begin
    GLMakie.closeall()
    lat, lon = (52.395593, 4.884704)
    delta = 0.01
    ext = Rect2f(lon - delta / 2, lat - delta / 2, delta, delta)
    subset="AHN1_T" # Takes reasonably long to load (~1-5mb compressed per tile)
    subset="AHN4_T" # Takes _really_ long to load, even from disk (~300mb compressed points per tile)
    provider = GeoTilePointCloudProvider(subset=subset)
    image = ElevationProvider()
    cfg = Tyler.PlotConfig(postprocess=p -> translate!(p, 0, 0, 0.001))
    m1 = Tyler.Map3D(ext; provider=provider)
    m2 = Tyler.Map3D(ext; figure=m1.figure, axis=m1.axis, provider=image)
    display(m1.figure.scene)
end


for (k, (pl, tile, bb)) in m1.plots
    translate!(pl, 0, 0, 0.001)
end


m1.tiles.tile_queue
Tyler.cleanup_queue!(m1, Tyler.OrderedSet{Tyler.Tile}())

tc = m1.tiles
for (key, pcd) in tc.fetched_tiles
    tc.fetched_tiles[key] = Tyler.PointCloudData(pcd.points, pcd.color, pcd.bounds, 0.6)
end

begin
    GLMakie.closeall()
    # Tyler.SCALE_ADD[] = Point3d(0, 0, 0)
    # Tyler.SCALE_DIV[] = 1.0
    Tyler.SCALE_ADD[] = Point3d(6870080, 6870080, 0)
    Tyler.SCALE_DIV[] = 10_0000.0
    lat, lon = (52.395593, 4.884704)
    delta = 0.01
    ext = Rect2f(lon - delta / 2, lat - delta / 2, delta, delta)
    subset = "AHN1_T" # Takes reasonably long to load (~1-5mb compressed per tile)
    # subset = "AHN4_T" # Takes _really_ long to load, even from disk (~300mb compressed points per tile)
    provider = GeoTilePointCloudProvider(subset=subset)
    cfg = Tyler.PlotConfig(marker=FastPixel(3))#Makie.FastPixel(1))
    image = TileProviders.Esri(:WorldImagery)
    m1 = Tyler.Map3D(ext; provider=provider, plot_config=cfg)
    # m2 = Tyler.Map3D(ext; figure=m1.figure, axis=m1.axis)
    # m1 = Tyler.Map3D(ext; plot_config=Tyler.DebugPlotConfig())
    # m1.axis.scene.camera_controls.far[] = 10000
    update_cam!(m1.axis.scene)
    display(m1.figure.scene)
end

bb = reduce(union, boundingbox.(first.(values(m1.plots))))


for i in 1:100
    rotate_cam!(m1.axis.scene, 0, 0.001, 0)
    sleep(1/60)
end
