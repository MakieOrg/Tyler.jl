
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

# Conservative global elevation defaults (Mariana Trench to Mt. Everest).
default_z_bounds() = (-450.0, 8848.0)

"""
    tile_z_bounds(provider, tile) -> (zmin, zmax, loose)

The vertical bounding range used by 3D fetching schemes for frustum culling
and screen-space-error selection. Returns `(zmin, zmax, loose::Bool)` where
`loose=true` means the bounds are a conservative estimate (e.g. inherited
from an ancestor or the global default) and SSE distance should be computed
conservatively. Override per-provider to return tighter bounds when known.
"""
tile_z_bounds(::AbstractProvider, ::Tile) = (default_z_bounds()..., true)

# ── Shared bounds-cache persistence helpers ───────────────────────────────
#
# Same binary format used for any per-tile (zmin, zmax) sidecar: 8-byte magic
# + 1-byte version + repeated 25-byte records (Int32 x, Int32 y, Int8 z,
# Float64 zmin, Float64 zmax). Atomic write via mv-on-tmpfile, fail-quiet on
# read errors so a stale or partial file just starts fresh.
const TILE_BOUNDS_MAGIC = b"TYLRBND\0"
const TILE_BOUNDS_VERSION = 0x01

function load_bounds_file!(path::AbstractString,
                           cache::ThreadSafeDict{Tile, NTuple{2, Float64}})
    isfile(path) || return cache
    try
        open(path, "r") do io
            read(io, length(TILE_BOUNDS_MAGIC)) == TILE_BOUNDS_MAGIC || return
            read(io, UInt8) == TILE_BOUNDS_VERSION || return
            while !eof(io)
                x = read(io, Int32); y = read(io, Int32); z = read(io, Int8)
                zmin = read(io, Float64); zmax = read(io, Float64)
                cache[Tile(Int(x), Int(y), Int(z))] = (zmin, zmax)
            end
        end
    catch e
        @warn "Could not load persisted bounds from $path" exception=e
    end
    return cache
end

function save_bounds_file(path::AbstractString,
                          cache::ThreadSafeDict{Tile, NTuple{2, Float64}})
    isdir(dirname(path)) || mkpath(dirname(path))
    tmp = path * ".tmp"
    try
        open(tmp, "w") do io
            write(io, TILE_BOUNDS_MAGIC)
            write(io, TILE_BOUNDS_VERSION)
            for (tile, (zmin, zmax)) in cache
                write(io, Int32(tile.x)); write(io, Int32(tile.y)); write(io, Int8(tile.z))
                write(io, Float64(zmin)); write(io, Float64(zmax))
            end
        end
        mv(tmp, path; force=true)
    catch e
        @warn "Could not persist bounds to $path" exception=e
        isfile(tmp) && rm(tmp; force=true)
    end
    return
end

# Walk up ancestors looking for the nearest tile with tight bounds. Returns
# `(zmin, zmax, loose::Bool)` — loose=true means we fell back to an ancestor
# or the default. Used by per-provider `tile_z_bounds` implementations.
function ancestor_or_default_bounds(cache::ThreadSafeDict{Tile, NTuple{2, Float64}},
                                    tile::Tile, default::NTuple{2, Float64})
    cached = get(cache, tile, nothing)
    cached !== nothing && return (cached..., false)
    t = tile
    while t.z > 0
        t = Tile(t.x >> 1, t.y >> 1, t.z - 1)
        cached = get(cache, t, nothing)
        cached !== nothing && return (cached..., true)
    end
    return (default..., true)
end