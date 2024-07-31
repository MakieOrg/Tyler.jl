
Base.showable(::MIME"image/png", ::AbstractMap) = true

function Base.show(io::IO, m::MIME"image/png", map::AbstractMap)
    wait(map)
    Makie.show(io, m, map.figure)
end


function remove_unused!(m::AbstractMap, tile::Tile)
    return remove_unused!(m, tile_key(m.provider, tile))
end

function remove_unused!(m::AbstractMap, key::String)
    plot_tile = get(m.plots, key, nothing)
    if !isnothing(plot_tile)
        plot, tile, bounds = plot_tile
        move_to_back!(plot, abs(m.zoom[] - tile.z), bounds)
        return plot, key
    end
    return nothing
end

function update_tileset!(m::AbstractMap, new_current_tiles::OrderedSet{Tile})
    ptiles = plotted_tiles(m)
    tile2key = Dict(zip(ptiles, keys(m.plots)))
    not_needed_anymore = setdiff(keys(m.current_tiles), new_current_tiles)
    for tile in not_needed_anymore
        if haskey(tile2key, tile)
            key = tile2key[tile]
            remove_unused!(m, key)
        end
    end

    queue = m.tiles.tile_queue
    lock(queue) do
        queued = queue.data
        remove_from_queue = setdiff(queued, new_current_tiles)
        filter!(queued) do tile
            if tile in remove_from_queue
                Base._increment_n_avail(queue, -1)
                return false
            else
                return true
            end
        end
    end
end
