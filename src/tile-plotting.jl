
function update_tile_plot!(plot::Plot, new_data)
    plot[3] = new_data
    plot.visible = true
    return
end

function update_tile_plot!(plot::Plot, new_data::AbstractMatrix)
    plot[3] = rotr90(new_data)
    plot.visible = true
    return
end

function create_tile_plot!(map::AbstractMap, tile::Tile, image)
    if haskey(map.plots, tile)
        # this shouldn't get called with plots that are already displayed
        @debug "getting tile plot already plotted"
        return map.plots[tile]
    end
    if isempty(map.free_tiles)
        mplot = create_tileplot!(map.axis, image)
    else
        mplot = pop!(map.free_tiles)
        update_tile_plot!(mplot, image)
    end
    map.plots[tile] = mplot
    return place_tile!(tile, mplot, map.crs)
end

function create_tileplot!(axis::LScene, image::Tuple)
    # Plot directly into scene to not update limits
    matr = image[1] .* -100
    return Makie.surface!(axis.scene, (0.0, 1.0), (0.0, 1.0), matr; color=image[2], shading=Makie.NoShading,
                          colormap=:terrain, inspectable=false)
end

function create_tileplot!(axis, image)
    # Plot directly into scene to not update limits
    return Makie.image!(axis.scene, (0.0, 1.0), (0.0, 1.0), rotr90(image); inspectable=false)
end

function place_tile!(tile::Tile, plot::Makie.LineSegments, crs)
    bounds = MapTiles.extent(tile, crs)
    xmin, xmax = bounds.X
    ymin, ymax = bounds.Y
    plot[1] = Rect2f(xmin, ymin, xmax - xmin, ymax - ymin)
    # Makie.translate!(plot, 0, 0, tile.z * 10)
    return
end

function place_tile!(tile::Tile, plot::Plot, crs)
    bounds = MapTiles.extent(tile, crs)
    xmin, xmax = bounds.X
    ymin, ymax = bounds.Y
    plot[1] = (xmin, xmax)
    plot[2] = (ymin, ymax)
    # Makie.translate!(plot, 0, 0, tile.z * 10)
    return
end

function debug_tile!(map::AbstractMap, tile::Tile)
    plot = Makie.linesegments!(map.axis, Rect2f(0, 0, 1, 1); color=:red, linewidth=1)
    return Tyler.place_tile!(tile, plot, web_mercator)
end

function debug_tiles!(map::AbstractMap)
    for tile in map.displayed_tiles
        debug_tile!(map, tile)
    end
end
