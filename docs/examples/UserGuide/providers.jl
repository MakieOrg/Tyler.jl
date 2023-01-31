# # Tile Providers

using Tyler, GLMakie
using TileProviders
using MapTiles

# Several providers are available (unfortunally is hard to find the ones that work properly).
# See the following list:

providers = TileProviders.list_providers()

# Try and see which ones work, and report back please.

##london = Rect2f(-0.0921, 51.5, 0.04, 0.025)
##ptopo = TileProviders.USGS(:USTopo)
##pclouds = TileProviders.OpenWeatherMap(:Clouds)
##pbright = TileProviders.MapTiler(:Bright)
##ppositron = TileProviders.CartoDB(:Positron)
##providers = [ptopo, pclouds, pbright, ppositron]
##m = Tyler.Map(london; provider=ppositron,
##    figure=Figure(resolution=(600, 600)))
