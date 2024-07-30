using GeometryBasics, GLMakie, Tyler
using Tyler: ElevationProvider, GeoTilePointCloudProvider
begin
    lat, lon = (52.395593, 4.884704)
    delta = 0.01
    ext = Rect2f(lon-delta/2, lat-delta/2, delta, delta)
    m1 = Tyler.Map(ext)
    display(m1.figure.scene)
end


begin
    # lat, lon = (40.697211, -74.037523)
    lat, lon = (52.395593, 4.884704)
    # lat, lon = (53.208252, 5.169539)
    # lat, lon = (55.648466, 12.566546)
    # lat, lon = (47.087441, 13.377214)
    delta = 0.1
    ext = Rect2f(lon-delta/2, lat-delta/2, delta, delta)
    m = Tyler.Map3D(ext; provider=ElevationProvider())
    display(m.figure.scene)
end


begin
    lat, lon = (52.395593, 4.884704)
    delta = 0.01
    ext = Rect2f(lon - delta / 2, lat - delta / 2, delta, delta)
    cfg = Tyler.PlotConfig(
        preprocess=pc -> map(point-> point .* Point3f(1, 1, 5), pc),
        postprocess=p -> translate!(p, 0, 0, 40),
        color=(:black, 0.1), transparency=true
    )
    provider = GeoTilePointCloudProvider()
    m1 = Tyler.Map3D(ext; provider=provider, plot_config=cfg)
    m2 = Tyler.Map3D(ext; figure=m1.figure, axis=m1.axis)
    # m1 = Tyler.Map3D(ext; plot_config=Tyler.DebugPlotConfig())
    display(m1.figure.scene)
end
