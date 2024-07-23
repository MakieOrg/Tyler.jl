struct TileCache{TileFormat}
    provider::AbstractProvider
    fetched_tiles::LRU{Tile,TileFormat}
    tile_queue::Channel{Tile}
    downloaded_tiles::Channel{Tuple{Tile,TileFormat}}
end

get_tile_format(provider) = Matrix{RGB{N0f8}}

function TileCache(provider; cache_size_gb=5)
    TileFormat = get_tile_format(provider)
    fetched_tiles = LRU{Tile,TileFormat}(; maxsize=cache_size_gb * 10^9, by=Base.sizeof)
    downloaded_tiles = Channel{Tuple{Tile,TileFormat}}(Inf)

    tile_queue = Channel{Tile}(Inf; spawn=true) do tile_queue
        for tile in tile_queue
            downloaded_tile = get!(fetched_tiles, tile) do
                try
                    fetch_tile(provider, tile)
                catch e
                    @warn "Error while fetching tile" exception = (e, catch_backtrace())
                    # put!(tile_queue, tile)  # retry (not implemented, should have a max retry count)
                end
            end
            # we may have moved already and the tile doesn't need to be displayed anymore
            put!(downloaded_tiles, (tile, downloaded_tile))
        end
    end
    return TileCache{TileFormat}(provider, fetched_tiles, tile_queue, downloaded_tiles)
end

function fetch_tile(provider::AbstractProvider, tile::Tile)
    url = TileProviders.geturl(provider, tile.x, tile.y, tile.z)
    result = HTTP.get(url; retry=false, readtimeout=10, connect_timeout=10)
    return ImageMagick.readblob(result.body)
end

function Base.wait(tiles::TileCache)
    # wait for all tiles to get downloaded
    while !isempty(tiles.tile_queue)
        sleep(0.01)
    end
end
