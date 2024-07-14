import Makie: Point3d


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
    plot = Makie.linesegments!(map.axis, Rect2f(0, 0, 1, 1), color=:red, linewidth=1, overdraw = true)
    Tyler.place_tile!(tile, plot, web_mercator)
end

function debug_tiles!(map::AbstractMap)
    for tile in map.displayed_tiles
        debug_tile!(map, tile)
    end
end


function create_tileplot!(axis, image)
    # Use a mesh plot until image rotr90 is fixed
    # Also, this will make it easier to subdivide the image mesh
    # To apply some other coordinate transforms
    # use GeometryBasics.Tesselation(rect, (128, 128)) to get a 128x128 subdivied mesh
    rect = Rect2f(0, 0, 1, 1)
    points = decompose(Point2f, rect)
    faces = decompose(GLTriangleFace, rect)
    uv = decompose_uv(rect)
    map!(uv -> Vec2f(uv[1], 1 - uv[2]), uv, uv)
    m = GeometryBasics.Mesh(meta(Makie.to_ndim.((Point3d,), points, (0,)); uv=uv), faces)
    # Plot directly into scene to not update limits 
    return mesh!(axis.scene, m; color=image, shading=Makie.NoShading, inspectable=false)
end


function place_tile!(tile::Tile, plot::Plot, crs)
    bounds = MapTiles.extent(tile, crs)
    xmin, xmax = bounds.X
    ymin, ymax = bounds.Y
    Makie.translate!(plot, xmin, ymin, tile.z - 100)
    Makie.scale!(plot, xmax - xmin, ymax - ymin, 1)
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
