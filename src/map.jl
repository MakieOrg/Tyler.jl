abstract type AbstractMap end

Base.showable(::MIME"image/png", ::AbstractMap) = true

function Base.show(io::IO, m::MIME"image/png", map::AbstractMap)
    wait(map)
    Makie.show(io, m, map.figure)
end

function stopped_displaying(screen::Makie.MakieScreen)
    Backend = parentmodule(typeof(screen))
    if nameof(Backend) == :WGLMakie
        session = Backend.get_screen_session(screen)
        isnothing(session) && return false
        !isready(session) && return false
        return !isopen(session)
    elseif nameof(Backend) == :GLMakie
        return !isopen(screen)
    else
        error("Unsupported backend: $(Backend)")
    end
end

function stopped_displaying(fig::Figure)
    scene = Makie.get_scene(fig)
    screen = Makie.getscreen(scene)
    # if not displayed yet, we return true, since we're using
    # is_open as a condition in our while loop to stop once it got displayed & closed
    isnothing(screen) && return false
    return stopped_displaying(screen)
end

function remove_tiles!(m::AbstractMap, tiles_being_displayed::OrderedSet{Tile})
    to_remove_plots = setdiff(keys(m.plots), tiles_being_displayed)
    for tile in to_remove_plots
        if haskey(m.plots, tile)
            plot = pop!(m.plots, tile)
            plot.visible = false
            push!(m.free_tiles, plot)
        end
    end

    queue = m.tiles.tile_queue
    lock(queue) do
        queued = queue.data
        remove_from_queue = setdiff(queued, tiles_being_displayed)
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
