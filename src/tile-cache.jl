struct TileCache{TileFormat,Downloader}
    provider::AbstractProvider
    # Nothing for unavailable tiles, so we don't download them again
    fetched_tiles::LRU{String,Union{Nothing, TileFormat}}
    tile_queue::Channel{Tile}
    # We also need to put! nothing for unavailable tiles into downloaded_tiles,
    # so `Map` can clean up the expected tiles
    downloaded_tiles::Channel{Tuple{Tile,Union{Nothing, TileFormat}}}
    downloader::Vector{Downloader}
    # Track retry counts for failed downloads (not 404s which are permanent)
    retry_counts::ThreadSafeDict{String, Int}
    max_retries::Int
end

struct CacheMiss end
const CACHE_MISS = CacheMiss()

function TileCache(provider; cache_size_gb=5, max_parallel_downloads=1, max_retries=3)
    TileFormat = get_tile_format(provider)
    downloader = [get_downloader(provider) for i in 1:max_parallel_downloads]
    fetched_tiles = LRU{String,Union{Nothing, TileFormat}}(; maxsize=cache_size_gb * 10^9, by=Base.summarysize)
    downloaded_tiles = Channel{Tuple{Tile,Union{Nothing, TileFormat}}}(Inf)
    tile_queue = Channel{Tile}(Inf)
    retry_counts = ThreadSafeDict{String, Int}()

    async = Threads.nthreads(:default) <= 1
    if async && max_parallel_downloads > 1
        @warn "Multiple download threads are not supported with Threads.nthreads()==1, falling back to async. Start Julia with more threads for parallel downloads."
        async = true
    end
    @assert max_parallel_downloads > 0
    for thread in 1:max_parallel_downloads
        dl = downloader[thread]
        if async
            @async run_loop(dl, tile_queue, fetched_tiles, provider, downloaded_tiles, retry_counts, max_retries)
        else
            Threads.@spawn run_loop(dl, tile_queue, fetched_tiles, provider, downloaded_tiles, retry_counts, max_retries)
        end
    end
    return TileCache{TileFormat,eltype(downloader)}(provider, fetched_tiles, tile_queue, downloaded_tiles, downloader, retry_counts, max_retries)
end

# Base methods

function Base.close(tiles::TileCache)
    close(tiles.tile_queue)
    close(tiles.downloaded_tiles)
    empty!(tiles.fetched_tiles)
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

# Re-queue a failed tile after exponential backoff, without blocking the worker.
function schedule_retry!(tile_queue::Channel{Tile}, tile::Tile, retries::Int)
    delay = 0.1 * 2^retries # 0.1s, 0.2s, 0.4s, ...
    @async begin
        sleep(delay)
        isopen(tile_queue) && put!(tile_queue, tile)
    end
    return
end

function run_loop(dl, tile_queue, fetched_tiles, provider, downloaded_tiles, retry_counts, max_retries)
    while isopen(tile_queue)
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

            # Atomic cache lookup: haskey + getindex would race with LRU eviction.
            cached = get(fetched_tiles, key, CACHE_MISS)
            if !(cached isa CacheMiss)
                result = cached
            else
                try
                    fetched = fetch_tile(provider, dl, tile)
                    fetched_tiles[key] = fetched
                    delete!(retry_counts, key)
                    result = fetched
                catch e
                    permanent = e isa RequestError && e.response.status == 404
                    retries = get(retry_counts, key, 0)
                    status = e isa RequestError ? e.response.status : nothing
                    if permanent
                        @warn "tile $(tile) not available (404), will not download again" maxlog = 10
                        fetched_tiles[key] = nothing
                        delete!(retry_counts, key)
                    elseif retries >= max_retries
                        @warn "tile $(tile) failed after $(max_retries) retries (status: $(status)), giving up" exception=(e, catch_backtrace()) maxlog = 10
                        fetched_tiles[key] = nothing
                        delete!(retry_counts, key)
                    else
                        retry_counts[key] = retries + 1
                        @warn "tile $(tile) download failed (status: $(status)), retry $(retries + 1)/$(max_retries)" maxlog = 20
                        schedule_retry!(tile_queue, tile, retries)
                        continue # don't emit a downloaded_tiles entry for this attempt
                    end
                end
            end
        catch e
            @warn "Error while fetching tile on thread $(Threads.threadid())" exception = (e, catch_backtrace())
            result = nothing
        end
        put!(downloaded_tiles, (tile, result))
        yield()
    end
    close(downloaded_tiles)
end
