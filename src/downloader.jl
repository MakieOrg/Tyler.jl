
abstract type AbstractDownloader end

struct NoDownload <: AbstractDownloader end

struct ByteDownloader <: AbstractDownloader
    timeout::Float64
    downloader::Downloads.Downloader
    io::IOBuffer
    bytes::Vector{UInt8}
end

function ByteDownloader(timeout=10)
    return ByteDownloader(timeout, Downloads.Downloader(), IOBuffer(), UInt8[])
end

function download_tile_data(dl::ByteDownloader, provider, url)
    Downloads.download(url, dl.io; downloader=dl.downloader)
    # a bit of shananigans to allocate less and stress the GC less!
    resize!(dl.bytes, dl.io.ptr - 1)
    copyto!(dl.bytes, 1, dl.io.data, 1, dl.io.ptr-1)
    seekstart(dl.io)
    return dl.bytes
end

struct PathDownloader <: AbstractDownloader
    timeout::Float64
    downloader::Downloads.Downloader
    cache_dir::String
    lru::LRU{String, Int}
end

function PathDownloader(cache_dir; timeout=10, cache_size_gb=5)
    isdir(cache_dir) || mkpath(cache_dir)
    lru = LRU{String, Int}(maxsize=cache_size_gb * 10^9, by=identity)
    return PathDownloader(timeout, Downloads.Downloader(), cache_dir, lru)
end

function unique_filename(url)
    return string(hash(url))
end

function download_tile_data(dl::PathDownloader, provider::AbstractProvider, url)
    unique_name = unique_filename(url)
    path = joinpath(dl.cache_dir, unique_name * file_ending(provider))
    if !isfile(path)
        Downloads.download(url, path; downloader=dl.downloader)
    end
    return path
end