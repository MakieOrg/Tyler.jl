
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

function cleanup_queue!(m::AbstractMap, to_keep::OrderedSet{Tile})
    queue = m.tiles.tile_queue
    lock(queue) do
        queued = queue.data
        filter!(queued) do tile
            if !(tile in to_keep)
                Base._increment_n_avail(queue, -1)
                return false
            else
                return true
            end
        end
    end
end
