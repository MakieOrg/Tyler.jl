
struct ElevationProvider <: AbstractProvider
    color_provider::Union{Nothing, AbstractProvider}
end

Tyler.get_tile_format(::ElevationProvider) = Tyler.ElevationData
TileProviders.options(::ElevationProvider) = nothing
TileProviders.min_zoom(::ElevationProvider) = 0
TileProviders.max_zoom(::ElevationProvider) = 16

function ElevationProvider()
    ElevationProvider(TileProviders.Esri(:WorldImagery))
end

function TileProviders.geturl(::ElevationProvider, x::Integer, y::Integer, z::Integer)
    return "https://elevation3d.arcgis.com/arcgis/rest/services/WorldElevation3D/Terrain3D/ImageServer/tile/$(z)/$(y)/$(x)"
end

cache_path = joinpath(@__DIR__, "elevation-cache")

function fetch_elevation_tile(provider, tile::Tyler.Tile)
    url = TileProviders.geturl(provider, tile.x, tile.y, tile.z)
    name = "$(tile.z)-$(tile.x)-$(tile.y).lerc"
    path = joinpath(cache_path, name)
    if !isdir(cache_path)
        mkpath(cache_path)
    end
    Downloads.download(url, path)
    dataset = ArchGDAL.read(path)
    band = ArchGDAL.getband(dataset, 1)
    return Float32.(reverse(band; dims=2) .* -1.0f0)
end

function Tyler.fetch_tile(provider::ElevationProvider, tile::Tyler.Tile)
    elevation_img = fetch_elevation_tile(provider, tile)
    if isnothing(provider.color_provider)
        return Tyler.ElevationData(elevation_img, RGBf[])
    end
    foto_img = Tyler.fetch_tile(provider.color_provider, tile)
    return Tyler.ElevationData(elevation_img, rotr90(foto_img))
end
