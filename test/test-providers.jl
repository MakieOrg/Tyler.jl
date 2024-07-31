using GeometryBasics, GLMakie, Tyler
using Tyler: ElevationProvider, GeoTilePointCloudProvider

begin
    lat, lon = (52.395593, 4.884704)
    delta = 0.01
    ext = Rect2f(lon-delta/2, lat-delta/2, delta, delta)
    m1 = Tyler.Map(ext; download_threads=3, fetching_scheme=Tyler.SimpleTiling())
    display(m1.figure.scene)
end
m1.axis.scene.plots |> length
begin
    lat, lon = (52.395593, 4.884704)
    delta = 0.01
    ext = Rect2f(lon - delta / 2, lat - delta / 2, delta, delta)
    m1 = Tyler.Map(ext; download_threads=1)
    display(m1.figure.scene)
end
m1.zoom[]

for (key, (pl, tile, rect)) in m1.plots
    if haskey(m1.current_tiles, tile)
    else
        @show pl.depth_shift[]
        lines!(m1.axis.scene, Rect2f(boundingbox(pl)); color=:black, depth_shift=-0.1f0)
    end
end
using MapTiles, TileProviders


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

for tile in new_tiles
    rect = Tyler.to_rect(MapTiles.extent(tile, m1.crs))
    lines!(m1.axis.scene, rect; depth_shift=-0.2f0, color=:red, linewidth=2)
end

for (key, (pl, tile, rect)) in m1.plots
    if tile in m1.current_tiles
        pl.depth_shift[] = 0.0f0
    else
        pl.depth_shift[] = 0.1f0
    end
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
