using Test
using Tyler
using GLMakie
using Extents
using GeoInterface

# Default
london = Rect2f(-0.0921, 51.5, 0.04, 0.025)
m = Tyler.Map(london); m.figure.scene
s = display(m) # waits until all tiles are displayed
@test isempty(m.tiles.tile_queue)
@test length(m.current_tiles) == 25
@test length(m.tiles.fetched_tiles) == 48

london = Rect2f(-0.0921, 51.5, 0.04, 0.025)
m = Tyler.Map(london; scale=1, provider=Tyler.TileProviders.Google(), crs=Tyler.MapTiles.WGS84()) # waits until all tiles are displayed
s = display(m) # waits until all tiles are displayed
@test isempty(m.tiles.tile_queue)
@test length(m.current_tiles) == 35
@test length(m.tiles.fetched_tiles) == 66

# test Extent input
london = Extents.Extent(X=(-0.0921, -0.0521), Y=(51.5, 51.525))
m = Tyler.Map(london; scale=1) # waits until all tiles are displayed
display(m)
@test isempty(m.tiles.tile_queue)
@test length(m.current_tiles) == 25
@test length(m.tiles.fetched_tiles) == 48

@testset "Interfaces" begin
    from = Tyler.MapTiles.WebMercator()
    to = Tyler.MapTiles.WGS84()
    # Uncomment when ≈ works in Extents.jl
    # @test map(zip(Extents.extent(m)...)) do b
    #     Tyler.MapTiles.project(b, from, to)
    # end ≈ Extents.extent(london)
    @test Extents.extent(m) isa Extents.Extent
    @test GeoInterface.crs(m) == Tyler.MapTiles.WebMercator()
end

# Reference tests?
# provider = TileProviders.NASAGIBS()
# m = Tyler.Map(Rect2f(0, 50, 40, 20), 5; provider=provider, min_tiles=8, max_tiles=32)
# wait(m)

# provider = TileProviders.Google(:satelite)
# m = Tyler.Map(london; provider=provider, coordinate_system=Tyler.wgs84)
