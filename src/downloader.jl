
abstract type AbstractDownloader end

"""
    Tyler.USER_AGENT[]

The `User-Agent` header Tyler sends with every tile request, by default
`"Tyler.jl/\$(Base.pkgversion(Tyler)) (+https://github.com/MakieOrg/Tyler.jl)"`.

Tile servers use this header to tell their users apart, and some of them - notably
[OpenStreetMap](https://operations.osmfoundation.org/policies/tiles/) - block requests
that carry the generic default of the underlying HTTP client instead.

If you build an application on top of Tyler, identify that application here, ideally
together with a way of contacting you:

```julia
Tyler.USER_AGENT[] = "MyTownMaps/1.4 (+https://mytownmaps.example.com; maps@example.com)"
```

Set this before constructing a `Map`, since downloaders read it when they are created.
Individual downloaders can also be given a `user_agent` keyword, see
[`ByteDownloader`](@ref) and [`PathDownloader`](@ref).
"""
const USER_AGENT = Ref{String}("")

default_user_agent() = "Tyler.jl/$(something(Base.pkgversion(Tyler), "unknown")) (+https://github.com/MakieOrg/Tyler.jl)"

struct NoDownload <: AbstractDownloader end

"""
    ByteDownloader(timeout=3; user_agent=Tyler.USER_AGENT[])

Downloads tiles into memory, identifying itself to the tile server as `user_agent`
(see [`Tyler.USER_AGENT`](@ref)).
"""
struct ByteDownloader <: AbstractDownloader
    timeout::Float64
    downloader::Downloads.Downloader
    io::IOBuffer
    bytes::Vector{UInt8}
    # The user agent goes out as a header instead of via CURLOPT_USERAGENT in the easy_hook
    # below, since Downloads.jl adds its own `curl/x.y julia/x.y` header whenever we pass
    # none, and a header beats that option.
    headers::Vector{Pair{String,String}}
end
function ByteDownloader(timeout=3; user_agent=USER_AGENT[])
    downloader = Downloads.Downloader()
    downloader.easy_hook = (easy, info) -> Downloads.Curl.setopt(easy, Downloads.Curl.CURLOPT_LOW_SPEED_TIME, timeout)
    return ByteDownloader(timeout, downloader, IOBuffer(), UInt8[], ["User-Agent" => user_agent])
end

function download_tile_data(dl::ByteDownloader, provider, url)
    Downloads.download(url, dl.io; downloader=dl.downloader, timeout=dl.timeout, headers=dl.headers)
    # a bit of shananigans to allocate less and stress the GC less!
    resize!(dl.bytes, dl.io.ptr - 1)
    copyto!(dl.bytes, 1, dl.io.data, 1, dl.io.ptr-1)
    seekstart(dl.io)
    return dl.bytes
end

"""
    PathDownloader(cache_dir; timeout=5, cache_size_gb=5, user_agent=Tyler.USER_AGENT[])

Downloads tiles into `cache_dir`, identifying itself to the tile server as `user_agent`
(see [`Tyler.USER_AGENT`](@ref)).
"""
struct PathDownloader <: AbstractDownloader
    timeout::Float64
    downloader::Downloads.Downloader
    cache_dir::String
    lru::LRU{String, Int}
    headers::Vector{Pair{String,String}}
end
function PathDownloader(cache_dir; timeout=5, cache_size_gb=5, user_agent=USER_AGENT[])
    isdir(cache_dir) || mkpath(cache_dir)
    lru = LRU{String, Int}(maxsize=cache_size_gb * 10^9, by=identity)
    downloader = Downloads.Downloader()
    downloader.easy_hook = (easy, info) -> Downloads.Curl.setopt(easy, Downloads.Curl.CURLOPT_LOW_SPEED_TIME, timeout)
    return PathDownloader(timeout, downloader, cache_dir, lru, ["User-Agent" => user_agent])
end

function download_tile_data(dl::PathDownloader, provider::AbstractProvider, url)
    unique_name = _unique_filename(url)
    path = joinpath(dl.cache_dir, unique_name * file_ending(provider))
    if !isfile(path)
        Downloads.download(url, path; downloader=dl.downloader, headers=dl.headers)
    end
    return path
end

_unique_filename(url) = string(hash(url))
