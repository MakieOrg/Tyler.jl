struct TileCache{TileFormat}
    provider::AbstractProvider
    fetched_tiles::LRU{String,TileFormat}
    tile_queue::Channel{Tile}
    downloaded_tiles::Channel{Tuple{Tile,Union{Nothing, TileFormat}}}
end

get_tile_format(provider) = Matrix{RGB{N0f8}}

function TileCache(provider; cache_size_gb=5, download_threads=min(1, Threads.nthreads() ÷ 3))
    TileFormat = get_tile_format(provider)
    fetched_tiles = LRU{String,TileFormat}(; maxsize=cache_size_gb * 10^9, by=Base.sizeof)
    downloaded_tiles = Channel{Tuple{Tile,Union{Nothing, TileFormat}}}(Inf)

    tile_queue = Channel{Tile}(Inf)
    for thread in 1:download_threads
        Threads.@spawn for tile in tile_queue
            result = nothing
            try
                @debug("downloading tile on thread $(Threads.threadid())")
                # For providers which have to map the same data to different tiles
                # Or providers that have e.g. additional paramers like date
                # the url is a much better key than the tile itself
                key = tile_key(provider, tile)
                # if the provider knows it doesn't have a tile, it can return nothing
                isnothing(key) && continue
                result = get!(fetched_tiles, key) do
                    fetch_tile(provider, tile)
                end
            catch e
                @warn "Error while fetching tile on thread $(Threads.threadid())" exception = (e, catch_backtrace())
                # put!(tile_queue, tile)  # retry (not implemented, should have a max retry count and some error handling)
                nothing
            end
            put!(downloaded_tiles, (tile, result))
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
