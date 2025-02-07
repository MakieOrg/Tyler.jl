"""
    ElevationProvider(color_provider::Union{Nothing, AbstractProvider}=TileProviders.Esri(:WorldImagery); cache_size_gb=5)

Provider rendering elevation data from [arcgis](https://elevation3d.arcgis.com/arcgis/rest/services/WorldElevation3D/Terrain3D/ImageServer).
This provider is special, since it uses a second provider for color information,
which also means you can provide a cache size, since color tile caching has to be managed by the provider.
When set to `nothing`, no color provider is used and the elevation data is used to color the surface with a colormap directly.
Use `Map(..., plot_config=Tyler.PlotConfig(colormap=colormap))` to set the colormap and other `surface` plot attributes.
"""
struct ElevationProvider <: AbstractProvider
    color_provider::Union{Nothing, AbstractProvider}
    tile_cache::LRU{String}
    downloader::Vector
end
function ElevationProvider(provider=TileProviders.Esri(:WorldImagery); cache_size_gb=5)
    TileFormat = get_tile_format(provider)
    fetched_tiles = LRU{String,TileFormat}(; maxsize=cache_size_gb * 10^9, by=Base.sizeof)
    downloader = [get_downloader(provider) for i in 1:Threads.maxthreadid()]
    ElevationProvider(provider, fetched_tiles, downloader)
end

# TileProviders interface
TileProviders.options(::ElevationProvider) = nothing
TileProviders.min_zoom(::ElevationProvider) = 0
TileProviders.max_zoom(::ElevationProvider) = 16
function TileProviders.geturl(::ElevationProvider, x::Integer, y::Integer, z::Integer)
    return "https://elevation3d.arcgis.com/arcgis/rest/services/WorldElevation3D/Terrain3D/ImageServer/tile/$(z)/$(y)/$(x)"
end

# Tyler interface
get_tile_format(::ElevationProvider) = ElevationData
file_ending(::ElevationProvider) = ".lerc"
function get_downloader(::ElevationProvider)
    cache_dir = joinpath(CACHE_PATH[], "ElevationProvider")
    return PathDownloader(cache_dir)
end

function fetch_tile(provider::ElevationProvider, dl::PathDownloader, tile::Tile)
    path = download_tile_data(dl, provider, TileProviders.geturl(provider, tile.x, tile.y, tile.z))
    dataset = ArchGDAL.read(path, options=["DATATYPE=Float32"])
    band = ArchGDAL.getband(dataset, 1)
    mini = -450
    maxi = 8700
    elevation_img = collect(reverse(band; dims=2))
    elevation_img .= Float32.(elevation_img)
    if isnothing(provider.color_provider)
        return Tyler.ElevationData(elevation_img, Matrix{RGBf}(undef, 0, 0), Vec2d(mini, maxi))
    end
    foto_img = get!(provider.tile_cache, path) do
        dl = provider.downloader[Threads.threadid()]
        fetch_tile(provider.color_provider, dl, tile)
    end
    return Tyler.ElevationData(elevation_img, foto_img, Vec2d(mini, maxi))
end
