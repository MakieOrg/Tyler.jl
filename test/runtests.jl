using Test
using Tyler
using GLMakie

# Default
london = Rect2f(-0.0921, 51.5, 0.04, 0.025)
m = wait(Tyler.Map(london)) # waits until all tiles are displayed
@test isempty(m.tiles_being_added)
@test isempty(m.queued_but_not_downloaded)
@test length(m.displayed_tiles) == 25
@test length(m.fetched_tiles) == 25

# Reference tests?
# provider = TileProviders.NASAGIBS()
# m = Tyler.Map(Rect2f(0, 50, 40, 20), 5; provider=provider, min_tiles=8, max_tiles=32)
# wait(m)

# provider = TileProviders.Google(:satelite)
# m = Tyler.Map(london; provider=provider, coordinate_system=Tyler.wgs84)
