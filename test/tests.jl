begin
    lat, lon = (52.395593, 4.884704)
    delta = 0.02
    ext = Rect2f(lon - delta / 2, lat - delta / 2, delta, delta)
    subset = "AHN1_T" # Takes reasonably long to load (~1-5mb compressed per tile)
    # subset = "AHN4_T" # Takes _really_ long to load, even from disk (~300mb compressed points per tile)
    provider = GeoTilePointCloudProvider(subset=subset)
    m1 = Tyler.Map3D(ext; provider=provider)
    wait(m1)
    unique_plots = unique(Tyler.tile_key.((m1.provider,), keys(m1.current_tiles)))
    @test length(unique_plots) == length(m1.plots)
end
