@testset "TileCache retry fields" begin
    lat, lon = (52.395593, 4.884704)
    delta = 0.01
    ext = Rect2f(lon - delta / 2, lat - delta / 2, delta, delta)
    m = Tyler.Map(ext; provider=Tyler.TileProviders.OpenStreetMap(:Mapnik), max_parallel_downloads=1)
    try
        @test m.tiles.max_retries == 3
        @test m.tiles.retry_counts isa Tyler.ThreadSafeDicts.ThreadSafeDict{String,Int}
        display(m); wait(m)
        @test !isempty(m.tiles.fetched_tiles)
    finally
        close(m)
    end
end

@testset "display then wait splits cleanly" begin
    # Regression: previously `Base.display(::AbstractMap)` called `wait(map)`
    # internally, which inserted plots while the screen was still initializing
    # and crashed some AMD drivers. display and wait are now separate —
    # exercise both in order and verify tiles end up plotted.
    lat, lon = (52.395593, 4.884704)
    delta = 0.01
    ext = Rect2f(lon - delta / 2, lat - delta / 2, delta, delta)
    m = Tyler.Map(ext; provider=Tyler.TileProviders.OpenStreetMap(:Mapnik))
    try
        display(m)
        wait(m)
        @test !isempty(m.plots)
        @test !isempty(m.foreground_tiles)
    finally
        close(m)
    end
end

@testset "Map3D SimpleTiling" begin
    lat, lon = (52.395593, 4.884704)
    delta = 0.02
    ext = Rect2f(lon - delta / 2, lat - delta / 2, delta, delta)
    m = Tyler.Map3D(ext; provider=Tyler.TileProviders.OpenStreetMap(:Mapnik), fetching_scheme=Tyler.SimpleTiling())
    try
        display(m); wait(m)
        @test !isempty(m.plots)
        @test !isempty(m.foreground_tiles)
        # Every foreground tile should either be plotted or dropped — never linger.
        foreground_keys = Set(Tyler.tile_key.((m.provider,), keys(m.foreground_tiles)))
        @test issubset(foreground_keys, Set(keys(m.plots)))
    finally
        close(m)
    end
end
