function Tyler.tile_reloader(m::Map{GeoAxis})
    axis = m.axis
    throttled = Makie.Observables.throttle(0.2, axis.finallimits)
    map_inverse_transform = lift(axis.scene, axis.dest) do dest
        GeoMakie.create_transform(#= destination =# m.crs, #= source =# dest)
    end

    onany(axis.scene, map_inverse_transform, throttled; update=true) do ax2map, axis_finallimits
        new_extent = Makie.apply_transform(ax2map, axis_finallimits)
        Tyler.update_tiles!(m, new_extent)
        return
    end
end

function Tyler.get_tiles_for_area(m::Map{<: GeoAxis}, scheme::Halo2DTiling, area::Union{Rect,Extent})
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
    xpos, ypos = Makie.apply_transform(GeoMakie.create_transform(m.crs, m.axis.dest[]), Point2f(xpos, ypos))
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
