
Base.showable(::MIME"image/png", ::AbstractMap) = true

function Base.show(io::IO, m::MIME"image/png", map::AbstractMap)
    wait(map)
    Makie.show(io, m, map.figure)
end

function update_tileset!(m::AbstractMap, new_current_tiles::OrderedSet{Tile})
    plotted_tiles = getindex.(values(m.plots), 2)
    tile2key = Dict(zip(plotted_tiles, keys(m.plots)))
    not_needed_anymore = setdiff(plotted_tiles, new_current_tiles)
    for tile in not_needed_anymore
        key = tile2key[tile]
        plot_tile = get(m.plots, key, nothing)
        if !isnothing(plot_tile)
            plot, tile, bounds = plot_tile
            move_to_back!(plot, bounds)
        end
        delete!(m.current_tiles, tile)
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
