
function update_tiles!(m::Map, arealike)
    # Get the tiles to be plotted from the fetching scheme and arealike
    new_tiles_set, background_tiles = get_tiles_for_area(m, m.fetching_scheme, arealike)


    currently_plotted = values(m.should_be_plotted)
    to_add = setdiff(new_tiles_set, currently_plotted)
    # We don't add any background tile to the current_tiles, so they stay shifted to the back
    # They get added async, so at this point `to_add` won't be in currently_plotted yet
    will_be_plotted = union(new_tiles_set, currently_plotted)
    # update_tileset!(m, new_tiles_set)

    # replace
    empty!(m.current_tiles)
    for tile in new_tiles_set
        m.current_tiles[tile] = true
    end

    # Move all plots to the back, that aren't in the newest tileset anymore
    for (key, (plot, tile, bounds)) in m.plots
        if haskey(m.current_tiles, tile)
            move_in_front!(plot, abs(m.zoom[] - tile.z), bounds)
        else
            move_to_back!(plot, abs(m.zoom[] - tile.z), bounds)
        end
    end

    # Queue tiles to be downloaded & displayed
    to_add_background = setdiff(background_tiles, will_be_plotted)
    # Remove any item from queue, that isn't in the new set
    to_keep = union(background_tiles, will_be_plotted)
    cleanup_queue!(m, to_keep)
    # The unique is needed to avoid tiles referencing the same tile
    # TODO, we should really consider to disallow this for tile providers, currently only allowed because of the PointCloudProvider
    foreach(tile -> queue_plot!(m, tile), unique(t -> tile_key(m.provider, t), to_add))
    foreach(tile -> queue_plot!(m, tile), unique(t -> tile_key(m.provider, t), to_add_background))
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
    zoom = calculate_optimal_zoom(m, area)
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
    points = map(p -> (p .* SCALE_DIV[]) .+ SCALE_ADD[], points)
    return tiles_from_poly(m, points), OrderedSet{Tile}()
end

#########################################################################################
##### Helper functions

function get_resolution(map::Map)
    screen = Makie.getscreen(map.axis.scene)
    return isnothing(screen) ? size(map.axis.scene) .* 1.5 : size(screen)
end

function calculate_optimal_zoom(map::Map, area)
    screen = Makie.getscreen(map.axis.scene)
    res = isnothing(screen) ? size(map.axis.scene) : size(screen)
    return clamp(z_index(area, res, map.crs), min_zoom(map), max_zoom(map))
end

function z_index(extent::Union{Rect,Extent}, res::Tuple, crs)
    # Calculate the number of tiles at each z and get the one
    # closest to the resolution `res`
    target_ntiles = prod(map(r -> r / 256, res))
    tiles_at_z = map(1:24) do z
        length(TileGrid(extent, z, crs))
    end
    return findmin(x -> abs(x - target_ntiles), tiles_at_z)[2]
end

function grow_extent(area::Union{Rect,Extent}, factor)
    Extent(map(Extents.bounds(area)) do axis_bounds
        span = axis_bounds[2] - axis_bounds[1]
        pad = factor * span / 2
        return (axis_bounds[1] - pad, axis_bounds[2] + pad)
    end)
end
