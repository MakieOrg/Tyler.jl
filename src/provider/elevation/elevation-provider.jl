
struct ElevationProvider <: AbstractProvider
    color_provider::Union{Nothing, AbstractProvider}
    tile_cache::LRU{String}
    downloader::Vector
end

Tyler.get_tile_format(::ElevationProvider) = Tyler.ElevationData
TileProviders.options(::ElevationProvider) = nothing
TileProviders.min_zoom(::ElevationProvider) = 0
TileProviders.max_zoom(::ElevationProvider) = 16

function ElevationProvider(provider=TileProviders.Esri(:WorldImagery); cache_size_gb=5)
    TileFormat = get_tile_format(provider)
    fetched_tiles = LRU{String,TileFormat}(; maxsize=cache_size_gb * 10^9, by=Base.sizeof)
    downloader = [get_downloader(provider) for i in 1:Threads.nthreads()]
    ElevationProvider(provider, fetched_tiles, downloader)
end
# https://elevation3d.arcgis.com/arcgis/rest/services/WorldElevation3D/Terrain3D/ImageServer
function TileProviders.geturl(::ElevationProvider, x::Integer, y::Integer, z::Integer)
    return "https://elevation3d.arcgis.com/arcgis/rest/services/WorldElevation3D/Terrain3D/ImageServer/tile/$(z)/$(y)/$(x)"
end

function get_downloader(::ElevationProvider)
    cache_dir = joinpath(CACHE_PATH[], "ElevationProvider")
    return PathDownloader(cache_dir)
end

file_ending(::ElevationProvider) = ".lerc"

function fetch_tile(provider::ElevationProvider, dl::PathDownloader, tile::Tile)
    path = download_tile_data(dl, provider, TileProviders.geturl(provider, tile.x, tile.y, tile.z))
    dataset = ArchGDAL.read(path, options=["DATATYPE=Float32"])
    band = ArchGDAL.getband(dataset, 1)
    mini = -450
    maxi = 8700
    elevation_img = collect(reverse(band; dims=2))
    elevation_img .= Float32.(elevation_img) ./ 8700.0f0 # .* (maxi - mini) .+ mini
    if isnothing(provider.color_provider)
        return Tyler.ElevationData(elevation_img, RGBf[])
    end
    foto_img = get!(provider.tile_cache, path) do
        dl = provider.downloader[Threads.threadid()]
        fetch_tile(provider.color_provider, dl, tile)
    end
    return Tyler.ElevationData(elevation_img, rotr90(foto_img))
end
