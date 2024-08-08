struct TileCache{TileFormat,Downloader}
    provider::AbstractProvider
    fetched_tiles::LRU{String,TileFormat}
    tile_queue::Channel{Tile}
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

function run_loop(thread_id, tile_queue, fetched_tiles, downloader, provider, downloaded_tiles)
    dl = downloader[thread_id]
    while isopen(tile_queue) || isready(tile_queue)
        tile = take_last!(tile_queue) # priorize newly arrived tiles
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
                fetch_tile(provider, dl, tile)
            end
        catch e
            @warn "Error while fetching tile on thread $(Threads.threadid())" exception = (e, catch_backtrace())
            # put!(tile_queue, tile)  # retry (not implemented, should have a max retry count and some error handling)
            nothing
        end
        put!(downloaded_tiles, (tile, result))
        yield()
    end
end

function TileCache(provider; cache_size_gb=5, max_parallel_downloads=min(1, Threads.nthreads() ÷ 3))
    TileFormat = get_tile_format(provider)
    downloader = [get_downloader(provider) for i in 1:max_parallel_downloads]
    fetched_tiles = LRU{String,TileFormat}(; maxsize=cache_size_gb * 10^9, by=Base.summarysize)
    downloaded_tiles = Channel{Tuple{Tile,Union{Nothing, TileFormat}}}(Inf)
    tile_queue = Channel{Tile}(Inf)
    async = Threads.nthreads() <= 1
    if async && max_parallel_downloads > 1
        @warn "Multiple download threads are not supported with Threads.nthreads()==1, falling back to async. Start Julia with more threads for parallel downloads."
        async = true
    end
    for thread in 1:max_parallel_downloads
        if async
            @async run_loop(thread, tile_queue, fetched_tiles, downloader, provider, downloaded_tiles)
        else
            Threads.@spawn run_loop(thread, tile_queue, fetched_tiles, downloader, provider, downloaded_tiles)
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

function Base.wait(tiles::TileCache)
    # wait for all tiles to get downloaded
    while !isempty(tiles.tile_queue)
        sleep(0.01)
    end
end
