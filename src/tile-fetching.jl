# Queue management

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
        tiles = Tile[]
        queued = queue.data
        filter!(queued) do tile
            if !(tile in to_keep)
                Base._increment_n_avail(queue, -1)
                push!(tiles, tile)
                return false
            else
                return true
            end
        end
        for tile in tiles
            delete!(m.should_get_plotted, tile_key(m.provider, tile))
        end
    end
end

function update_tiles!(m::Map, arealike)
    # Get the tiles to be plotted from the fetching scheme and arealike
    tiles = get_tiles_for_area(m, m.fetching_scheme, arealike)
    if length(tiles.foreground) > m.max_plots
        @warn "Too many tiles to plot, which means zoom level is not supported. Plotting no tiles for this zoomlevel." maxlog = 1
        empty!(tiles.foreground)
        empty!(tiles.background)
        empty!(tiles.offscreen)
    end
    queued_or_plotted = values(m.should_get_plotted)
    # Queue tiles to be downloaded & displayed
    to_add = map(t -> setdiff(t, queued_or_plotted), tiles)

    # replace
    empty!(m.foreground_tiles)
    for tile in tiles.foreground
        m.foreground_tiles[tile] = true
    end

    # Move all plots to the back, that aren't in the newest tileset anymore
    for (key, (plot, tile, bounds)) in m.plots
        dist = abs(m.zoom[] - tile.z)
        if haskey(m.foreground_tiles, tile)
            move_in_front!(plot, dist, bounds)
        else
            move_to_back!(plot, dist, bounds)
        end
    end

    # Remove any item from queue, that isn't in the new set
    to_keep_queued = union(tiles...)
    # Remove all tiles that are not in the new set from the queue
    cleanup_queue!(m, to_keep_queued)

    # The unique is needed to avoid tiles referencing the same tile
    # TODO, we should really consider to disallow this for tile providers,
    # This is currently only allowed because of the PointCloudProvider
    to_add_keys = map(to_add) do ta
        unique(t -> tile_key(m.provider, t), ta)
    end

    # We lock the queue, to put all tiles in one go into the tile queue
    # Without the lock, a few (n_download_threads) old tiles will be downloaded first
    # since they will be the last in the queue until we add the new tiles
    lock(m.tiles.tile_queue) do
        # Offscreen tiles show last, so scroll and zoom don't show
        # empty white areas or low resolution tiles
        foreach(tile -> queue_plot!(m, tile), to_add_keys.offscreen)
        # Foreground tiles show in the middle, filling out details
        foreach(tile -> queue_plot!(m, tile), to_add_keys.foreground)
        # Lower-resolution background tiles show first
        # Its quick to get them and they immediately fill the plot
        foreach(tile -> queue_plot!(m, tile), to_add_keys.background)
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
    # TODO, also early return if too many tiles to plot?
    ideal_zoom, zoom, approx_ntiles = optimal_zoom(m, norm(widths(to_rect(area))))
    m.zoom[] = zoom

    # And the z layers we will plot
    layer_range = max(min_zoom(m), zoom - depth):zoom
    # Get the tiles around the mouse first
    xpos, ypos = Makie.mouseposition(m.axis.scene)
    # Use the closest in-bounds point
    xpos = max(min(xpos, area.X[2]), area.X[1])
    ypos = max(min(ypos, area.Y[2]), area.Y[1])
    # Define a 1% resolution extent around the mouse
    xspan = (area.X[2] - area.X[1]) * 0.01
    yspan = (area.Y[2] - area.Y[1]) * 0.01
    mouse_area = Extents.Extent(; X=(xpos - xspan, xpos + xspan), Y=(ypos - yspan, ypos + yspan))
    # Define a halo around the area to download last, so pan/zoom are filled already
    halo_area = grow_extent(area, scheme.halo) # We don't mind that the middle tiles are the same, the OrderedSet will remove them

    # Set up empty tile lists
    foreground = OrderedSet{Tile}()
    background = OrderedSet{Tile}()
    offscreen = OrderedSet{Tile}()
    # Fill tiles for each z layer
    for z in layer_range
        # Get rings of tiles around the mouse, intersecting 
        # area so we don't get tiles outside the plot
        for ext_scale in 1:4:100
            # Get an extent
            mouse_halo_area = grow_extent(mouse_area, ext_scale)
            # Check if it intersects the plot area
            ext = Extents.intersection(mouse_halo_area, area)
            # No intersection so continue
            isnothing(ext) && continue
            tilegrid = MapTiles.TileGrid(ext, z, m.crs)
            if z == zoom
                union!(foreground, tilegrid)
            else
                union!(background, tilegrid)
            end
        end
        # Get the halo ring tiles to load offscreen
        area_grid = MapTiles.TileGrid(area, z, m.crs)
        halo_grid = MapTiles.TileGrid(halo_area, z, m.crs)
        # Remove tiles inside the area grid
        halo_tiles = setdiff(halo_grid, area_grid)
        # Update the offscreen tiles set
        union!(offscreen, halo_tiles)
    end
    tiles = (; foreground, background, offscreen)
    # Reverse the order of the groups. Reversing the ranges 
    # above doesn't have the same effect due to then unions
    return map(OrderedSet ∘ reverse ∘ collect, tiles)
end

#########################################################################################
##### SimpleTiling

struct SimpleTiling <: FetchingScheme
end

function get_tiles_for_area(m::Map, ::SimpleTiling, area::Union{Rect,Extent})
    area = typeof(area) <: Rect ? Extents.extent(area) : area
    diag = norm(widths(to_rect(area)))
    # Calculate the zoom level
    ideal_zoom, zoom, approx_ntiles = optimal_zoom(m, diag)
    m.zoom[] = zoom
    foreground = OrderedSet{Tile}(MapTiles.TileGrid(area, zoom, m.crs))
    background = OrderedSet{Tile}()
    offscreen = OrderedSet{Tile}()
    return (; foreground, background, offscreen)
end

#########################################################################################
##### Tiling3D

struct Tiling3D <: FetchingScheme
end

function get_tiles_for_area(m::Map{LScene}, ::Tiling3D, (cam, camc)::Tuple{Camera,Camera3D})
    points = frustrum_plane_intersection(cam, camc)
    eyepos = camc.eyeposition[]
    maxdist, _ = findmax(p -> norm(p[3] .- eyepos), points)
    camc.far[] = maxdist
    camc.near[] = eyepos[3] * 0.01
    update_cam!(m.axis.scene)
    foreground = tiles_from_poly(m, points; zshift=0)
    background = OrderedSet{Tile}()
    # for i in 2:2:6
    #     tiles = tiles_from_poly(m, points; zshift=-i)
    #     union!(foreground, tiles)
    # end
    offscreen = OrderedSet{Tile}()
    tiles = (; foreground, background, offscreen)
    return tiles
    # Reverse the order of the groups. Reversing the ranges 
    # above doesn't have the same effect due to then unions
    # return map(OrderedSet ∘ reverse ∘ collect, tiles)
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

# TODO this will be in Extents.jl soon, so remove
function grow_extent(area::Union{Rect,Extent}, factor)
    Extent(map(Extents.bounds(area)) do axis_bounds
        span = axis_bounds[2] - axis_bounds[1]
        pad = factor * span / 2
        return (axis_bounds[1] - pad, axis_bounds[2] + pad)
    end)
end

function optimal_zoom(m::Map, diagonal)
    diagonal_res = norm(get_resolution(m)) * m.scale
    # Go over complete known zoomrange of any provider.
    # So that we can get the theoretical optimal zoom level, even if the provider doesn't support it,
    # which we can then use to calculate the distance to the supported zoomlevel and may decide to not plot anything.
    # (TODO, how exactly can we get this over all providers?)
    zoomrange = 1:22
    z = optimal_zoom(m.crs, diagonal, diagonal_res, zoomrange, m.zoom[])
    actual_zoom = clamp(z, min_zoom(m), max_zoom(m))
    return z, actual_zoom, approx_tiles(m, actual_zoom, diagonal)
end
function optimal_zoom(crs, diagonal, diagonal_resolution, zoom_range, old_zoom)
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

function approx_tiles(m::Map, zoom, diagonal)
    ext = Extents.extent(Tile(0, 0, zoom), m.crs)
    mini, maxi = Point2.(ext.X, ext.Y)
    diag = norm(maxi .- mini)
    ntiles_diag = diagonal / diag
    return (ntiles_diag / sqrt(2)) ^ 2
end
