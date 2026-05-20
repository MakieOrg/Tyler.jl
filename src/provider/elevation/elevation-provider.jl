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
    bounds_cache::ThreadSafeDict{Tile, NTuple{2, Float64}}
end

# Sidecar file in the same scratch dir as the LERC tile cache.
elevation_bounds_file() = joinpath(CACHE_PATH[], "ElevationProvider", "bounds.bin")

# Compatibility wrappers — public API names kept for backwards compatibility
# with tests / scripts; the actual format/IO is shared with other providers.
load_persisted_bounds!(cache) = load_bounds_file!(elevation_bounds_file(), cache)
save_persisted_bounds(cache) = save_bounds_file(elevation_bounds_file(), cache)

function ElevationProvider(provider=TileProviders.Esri(:WorldImagery); cache_size_gb=5)
    TileFormat = get_tile_format(provider)
    fetched_tiles = LRU{String,TileFormat}(; maxsize=cache_size_gb * 10^9, by=Base.sizeof)
    downloader = [get_downloader(provider) for i in 1:Threads.maxthreadid()]
    bounds_cache = ThreadSafeDict{Tile, NTuple{2, Float64}}()
    load_persisted_bounds!(bounds_cache)
    ElevationProvider(provider, fetched_tiles, downloader, bounds_cache)
end

tile_z_bounds(p::ElevationProvider, tile::Tile) =
    ancestor_or_default_bounds(p.bounds_cache, tile, default_z_bounds())

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
    # Tighten the per-tile vertical bounds so SSE / frustum culling stop having
    # to use the global -450..8848 fallback for this region of the world.
    provider.bounds_cache[tile] = Float64.(extrema(elevation_img))
    # Periodic checkpoint so a Julia restart starts with tight bounds for
    # previously-visited areas. ~25 bytes/tile, mod-50 keeps I/O off the
    # hot path; mv-on-write keeps the file uncorrupted on crash.
    length(provider.bounds_cache) % 50 == 0 && save_persisted_bounds(provider.bounds_cache)
    if isnothing(provider.color_provider)
        return Tyler.ElevationData(elevation_img, Matrix{RGBf}(undef, 0, 0), Vec2d(mini, maxi))
    end
    foto_img = get!(provider.tile_cache, path) do
        dl = provider.downloader[Threads.threadid()]
        fetch_tile(provider.color_provider, dl, tile)
    end
    return Tyler.ElevationData(elevation_img, foto_img, Vec2d(mini, maxi))
end
