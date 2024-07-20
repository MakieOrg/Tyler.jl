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

function debug_tile!(map::AbstractMap, tile::Tile)
    plot = Makie.linesegments!(map.axis, Rect2f(0, 0, 1, 1), color=:red, linewidth=1)
    Tyler.place_tile!(tile, plot, web_mercator)
end

function debug_tiles!(map::AbstractMap)
    for tile in map.displayed_tiles
        debug_tile!(map, tile)
    end
end
using Colors

function create_tileplot!(axis::LScene, image::Tuple)
    # Plot directly into scene to not update limits
    matr = image[1] .* -100
    return Makie.surface!(axis.scene, (0.0, 1.0), (0.0, 1.0), matr; color=image[2], shading=Makie.NoShading, colormap=:terrain, inspectable=false)
end

function create_tileplot!(axis, image)
    # Plot directly into scene to not update limits
    return Makie.image!(axis.scene, (0.0, 1.0), (0.0, 1.0), rotr90(image); inspectable=false)
end

function place_tile!(tile::Tile, plot::Makie.LineSegments, crs)
    bounds = MapTiles.extent(tile, crs)
    xmin, xmax = bounds.X
    ymin, ymax = bounds.Y
    plot[1] = Rect2f(xmin, ymin, xmax-xmin, ymax-ymin)
    Makie.translate!(plot, 0, 0, tile.z * 10)
    return
end


function place_tile!(tile::Tile, plot::Plot, crs)
    bounds = MapTiles.extent(tile, crs)
    xmin, xmax = bounds.X
    ymin, ymax = bounds.Y
    plot[1] = (xmin, xmax)
    plot[2] = (ymin, ymax)
    Makie.translate!(plot, 0, 0, tile.z * 10)
    return
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
