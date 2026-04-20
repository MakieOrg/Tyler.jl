
# Tyler provider defauls

get_tile_format(provider) = Matrix{RGB{N0f8}}
get_downloader(provider) = ByteDownloader()

function fetch_tile(provider::AbstractProvider, downloader::AbstractDownloader, tile::Tile)
    url = TileProviders.geturl(provider, tile.x, tile.y, tile.z)
    isnothing(url) && return nothing
    data = download_tile_data(downloader, provider, url)
    return load_tile_data(provider, data)
end

function load_tile_data(::AbstractProvider, downloaded::AbstractVector{UInt8})
    io = IOBuffer(downloaded)
    format = FileIO.query(io)  # this interrogates the magic bits to see what file format it is (JPEG, PNG, etc)
    return FileIO.load(format) # this works because we have ImageIO loaded
end

function tile_key(provider::AbstractProvider, tile::Tile)
    return TileProviders.geturl(provider, tile.x, tile.y, tile.z)
end