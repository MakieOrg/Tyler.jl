struct TileCache{TileFormat,Downloader}
    provider::AbstractProvider
    # Nothing for unavailable tiles, so we don't download them again
    fetched_tiles::LRU{String,Union{Nothing, TileFormat}}
    tile_queue::Channel{Tile}
    # We also need to put! nothing for unavailable tiles into downloaded_tiles,
    # so `Map` can clean up the expected tiles
    downloaded_tiles::Channel{Tuple{Tile,Union{Nothing, TileFormat}}}
    downloader::Vector{Downloader}
end

get_tile_format(provider) = Matrix{RGB{N0f8}}

get_downloader(provider) = ByteDownloader()

function take_last!(c::Channel)
    lock(c)
    try
        while isempty(c.data)
            Base.check_channel_state(c)
            wait(c.cond_take)
        end
        # function taken from Base.take_buffered, with just this line replaced to use `pop!` instead of `popfirst!`
        v = pop!(c.data)
        Base._increment_n_avail(c, -1)
        notify(c.cond_put, nothing, false, false) # notify only one, since only one slot has become available for a put!.
        return v
    finally
        unlock(c)
    end
end


function run_loop(dl, tile_queue, fetched_tiles, provider, downloaded_tiles)
    while isopen(tile_queue) || isready(tile_queue)
        tile = take_last!(tile_queue) # priorize newly arrived tiles
        @show (tile.x, tile.y, tile.z)
        #sleep()
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
                try
                    return fetch_tile(provider, dl, tile)
                catch e
                    if isa(e, RequestError)
                        status = e.response.status
                        if (status == 404 || status == 500)
                            @warn "tile $(tile) not available, will not download again" maxlog = 10
                            return nothing
                        end
                    end
                    rethrow(e)
                end
            end
        catch e
            @warn "Error while fetching tile on thread $(Threads.threadid())" exception = (e, catch_backtrace())
            nothing
        end
        put!(downloaded_tiles, (tile, result))
        yield()
    end
end

function Base.close(tiles::TileCache)
    close(tiles.tile_queue)
    close(tiles.downloaded_tiles)
    empty!(tiles.fetched_tiles)
end

function TileCache(provider; cache_size_gb=5, max_parallel_downloads=1)
    TileFormat = get_tile_format(provider)
    downloader = [get_downloader(provider) for i in 1:max_parallel_downloads]
    fetched_tiles = LRU{String,Union{Nothing, TileFormat}}(; maxsize=cache_size_gb * 10^9, by=Base.summarysize)
    downloaded_tiles = Channel{Tuple{Tile,Union{Nothing, TileFormat}}}(Inf)
    tile_queue = Channel{Tile}(Inf)

    async = Threads.nthreads(:default) <= 1
    async = true # TODO remove 
    if async && max_parallel_downloads > 1
        @warn "Multiple download threads are not supported with Threads.nthreads()==1, falling back to async. Start Julia with more threads for parallel downloads."
        async = true
    end
    @assert max_parallel_downloads > 0
    for thread in 1:max_parallel_downloads
        dl = downloader[thread]
        if async
            @async run_loop(dl, tile_queue, fetched_tiles, provider, downloaded_tiles)
        else
            Threads.@spawn run_loop(dl, tile_queue, fetched_tiles, provider, downloaded_tiles)
        end
    end
    return TileCache{TileFormat,eltype(downloader)}(provider, fetched_tiles, tile_queue, downloaded_tiles, downloader)
end

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

function Base.wait(tiles::TileCache; timeout=50)
    # wait for all tiles to get downloaded
    items = lock(tiles.tile_queue) do
        copy(tiles.tile_queue.data)
    end
    tile_keys = filter!(!isnothing, map(t-> tile_key(tiles.provider, t), items))
    start = time()
    while true
        if isempty(tiles.tile_queue) && all(tk -> haskey(tiles.fetched_tiles, tk), tile_keys)
            break
        end
        if time() - start > timeout
            @warn "Timeout while waiting for tiles to download"
            break
        end
        sleep(0.01)
    end
end
