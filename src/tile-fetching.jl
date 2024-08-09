
function queue_plot!(m::Map, tile)
    key = tile_key(m.provider, tile)
    # Provider doesn't have a tile for this
    isnothing(key) && return
    m.should_get_plotted[key] = tile
    put!(m.tiles.tile_queue, tile)
    return
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

function update_tiles!(m::Map, arealike)
    # Get the tiles to be plotted from the fetching scheme and arealike
    new_tiles_set, background_tiles = get_tiles_for_area(m, m.fetching_scheme, arealike)

    queued_or_plotted = values(m.should_get_plotted)
    to_add = setdiff(new_tiles_set, queued_or_plotted)

    # We don't add any background tile to the current_tiles, so they stay shifted to the back
    # They get added async, so at this point `to_add` won't be in currently_plotted yet
    will_be_plotted = union(new_tiles_set, queued_or_plotted)
    # replace
    empty!(m.current_tiles)
    for tile in new_tiles_set
        m.current_tiles[tile] = true
    end

    # Move all plots to the back, that aren't in the newest tileset anymore
    for (key, (plot, tile, bounds)) in m.plots
        dist = abs(m.zoom[] - tile.z)
        if haskey(m.current_tiles, tile)
            move_in_front!(plot, dist, bounds)
        else
            move_to_back!(plot, dist, bounds)
        end
    end

    # Queue tiles to be downloaded & displayed
    to_add_background = setdiff(background_tiles, will_be_plotted)
    # Remove any item from queue, that isn't in the new set
    to_keep = union(background_tiles, will_be_plotted)
    # Remove all tiles that are not in the new set from the queue
    cleanup_queue!(m, to_keep)

    # The unique is needed to avoid tiles referencing the same tile
    # TODO, we should really consider to disallow this for tile providers,
    # This is currently only allowed because of the PointCloudProvider
    background = unique(t -> tile_key(m.provider, t), to_add_background)
    foreground = unique(t -> tile_key(m.provider, t), to_add)

    # We lock the queue, to put all tiles in one go into the tile queue
    # Since download workers take the last tiles first, foreground tiles go last
    # Without the lock, a few (n_download_threads) background tiles would be downloaded first,
    # since they will be the last in the queue until we add the foreground tiles
    lock(m.tiles.tile_queue) do
        foreach(tile -> queue_plot!(m, tile), background)
        foreach(tile -> queue_plot!(m, tile), foreground)
    end
end

#########################################################################################
##### Halo2DTiling

struct Halo2DTiling <: FetchingScheme
    depth::Int
    halo::Float64
    pixel_scale::Float64
end

Halo2DTiling(; depth=8, halo=0.2, pixel_scale=2.0) = Halo2DTiling(depth, halo, pixel_scale)

function get_tiles_for_area(m::Map{Axis}, scheme::Halo2DTiling, area::Union{Rect,Extent})
    area = typeof(area) <: Rect ? Extents.extent(area) : area
    # `depth` determines the number of layers below the current
    # layer to load. Tiles are downloaded in order from lowest to highest zoom.
    depth = scheme.depth

    # Calculate the zoom level
    zoom = optimal_zoom(m, norm(widths(to_rect(area))))
    m.zoom[] = zoom

    # And the z layers we will plot
    layer_range = max(min_zoom(m), zoom - depth):zoom
    # Get the tiles around the mouse first
    xpos, ypos = Makie.mouseposition(m.axis.scene)
    xspan = (area.X[2] - area.X[1]) * 0.01
    yspan = (area.Y[2] - area.Y[1]) * 0.01
    mouse_area = Extents.Extent(; X=(xpos - xspan, xpos + xspan), Y=(ypos - yspan, ypos + yspan))
    # Make a halo around the mouse tile to load next, intersecting area so we don't download outside the plot
    mouse_halo_area = grow_extent(mouse_area, 10)
    # Define a halo around the area to download last, so pan/zoom are filled already
    halo_area = grow_extent(area, scheme.halo) # We don't mind that the middle tiles are the same, the OrderedSet will remove them
    # Define all the tiles in the order they will load in
    background_areas = if Extents.intersects(mouse_halo_area, area)
        mha = Extents.intersection(mouse_halo_area, area)
        if Extents.intersects(mouse_area, area)
            [Extents.intersection(mouse_area, area), mha, halo_area]
        else
            [mha, halo_area]
        end
    else
        [halo_area]
    end

    foreground = OrderedSet{Tile}(MapTiles.TileGrid(area, zoom, m.crs))
    background = OrderedSet{Tile}()
    for z in layer_range
        z == zoom && continue
        for ext in background_areas
            union!(background, MapTiles.TileGrid(ext, z, m.crs))
        end
    end
    return foreground, background
end

#########################################################################################
##### SimpleTiling

struct SimpleTiling <: FetchingScheme
end

function get_tiles_for_area(m::Map, ::SimpleTiling, area::Union{Rect,Extent})
    area = typeof(area) <: Rect ? Extents.extent(area) : area
    diag = norm(widths(to_rect(area)))
    # Calculate the zoom level
    zoom = optimal_zoom(m, diag)
    m.zoom[] = zoom
    return OrderedSet{Tile}(MapTiles.TileGrid(area, zoom, m.crs)), OrderedSet{Tile}()
end

#########################################################################################
##### Tiling3D

struct Tiling3D <: FetchingScheme
end

function get_tiles_for_area(m::Map{LScene}, ::Tiling3D, (cam, camc)::Tuple{Camera,Camera3D})
    points = frustrum_plane_intersection(cam, camc)
    eyepos = camc.eyeposition[]
    maxdist, _ = findmax(p -> norm(p[3] .- eyepos), points)
    camc.far[] = maxdist * 10
    camc.near[] = eyepos[3] * 0.001
    update_cam!(m.axis.scene)
    return tiles_from_poly(m, points), OrderedSet{Tile}()
end

function get_tiles_for_area(m::Map{LScene}, s::SimpleTiling, (cam, camc)::Tuple{Camera,Camera3D})
    area = area_around_lookat(camc)
    return get_tiles_for_area(m, s, area)
end


#########################################################################################
##### Helper functions

function get_resolution(map::Map)
    screen = Makie.getscreen(map.axis.scene)
    return isnothing(screen) ? size(map.axis.scene) .* 1.5 : size(screen)
end

function grow_extent(area::Union{Rect,Extent}, factor)
    Extent(map(Extents.bounds(area)) do axis_bounds
        span = axis_bounds[2] - axis_bounds[1]
        pad = factor * span / 2
        return (axis_bounds[1] - pad, axis_bounds[2] + pad)
    end)
end

function optimal_zoom(m::Map, diagonal)
    diagonal_res = norm(get_resolution(m)) * m.scale
    zoomrange = min_zoom(m):max_zoom(m)
    optimal_zoom(m.crs, diagonal, diagonal_res, zoomrange, m.zoom[])
end

function optimal_zoom(crs, diagonal, diagonal_resolution, zoom_range, old_zoom)
    # Some provider only support one zoom level
    length(zoom_range) == 1 && return zoom_range[1]
    # TODO, this should come from provider
    tile_diag_res = norm((255, 255))
    target_ntiles = diagonal_resolution / tile_diag_res
    canditates_dict = Dict{Int,Float64}()
    candidates = @NamedTuple{z::Int, ntiles::Float64}[]
    for z in zoom_range
        ext = Extents.extent(Tile(0, 0, z), crs)
        mini, maxi = Point2.(ext.X, ext.Y)
        diag = norm(maxi .- mini)
        ntiles = diagonal / diag
        canditates_dict[z] = ntiles
        push!(candidates, (; z, ntiles))
    end
    if haskey(canditates_dict, old_zoom) # for the first invokation, old_zoom is 0, which is not a candidate
        old_ntiles = canditates_dict[old_zoom]
        # If the old zoom level is close to the target number of tiles, return it
        # to change the zoom level less often
        if old_ntiles > (target_ntiles - 1) && old_ntiles < (target_ntiles + 1)
            return old_zoom
        end
    end
    dist, idx = findmin(x -> abs(x.ntiles - target_ntiles), candidates)
    return candidates[idx].z
end
