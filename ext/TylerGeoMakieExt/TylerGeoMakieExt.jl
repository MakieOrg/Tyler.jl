using Tyler, GeoMakie

using LinearAlgebra, OrderedCollections

import Tyler: tile_reloader, create_tileplot!, update_tile_plot!,
            Map, AbstractMap, ImageData, PlotConfig, SimpleTiling, Halo2DTiling

using Tyler: to_rect


using Makie

using Makie: AbstractAxis, Mat

# functions directly related to plotting

function Tyler.create_tileplot!(config::PlotConfig, axis::GeoAxis, data::ImageData, bounds::Rect, tile_crs)
    mini, maxi = extrema(bounds)
    plot = GeoMakie.meshimage!(
        axis,
        (mini[1], maxi[1]), (mini[2], maxi[2]), data;
        uv_transform=:rotl90,
        inspectable=false,
        reset_limits=false, # substitute for plotting directly to scene, since GeoMakie handles the CRS stuff
        source = tile_crs[2], # tile_crs is a tuple of (tile, crs), we can pass the CRS directly to GeoMakie though
        config.attributes...
    )
    return plot
end

function Tyler.update_tile_plot!(plot::GeoMakie.MeshImage, ::PlotConfig, axis::AbstractAxis, data::ImageData, bounds::Rect, tile_crs)
    mini, maxi = extrema(bounds)
    plot[1] = (mini[1], maxi[1])
    plot[2] = (mini[2], maxi[2])
    plot[3] = data
    return
end


# functions related to fetching tiles

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


# Here, the `area` has already been transformed to the tile CRS
function Tyler.get_tiles_for_area(m::Map{GeoAxis}, scheme::Halo2DTiling, area::Union{Rect,Extent})
    area = typeof(area) <: Rect ? Extents.extent(area) : area
    # `depth` determines the number of layers below the current
    # layer to load. Tiles are downloaded in order from lowest to highest zoom.
    depth = scheme.depth

    # Calculate the zoom level
    # TODO, also early return if too many tiles to plot?
    ideal_zoom, zoom, approx_ntiles = Tyler.optimal_zoom(m, norm(widths(to_rect(area))))
    m.zoom[] = zoom

    # And the z layers we will plot
    layer_range = max(Tyler.min_zoom(m), zoom - depth):zoom
    # Get the tiles around the mouse first
    xpos, ypos = Makie.mouseposition(m.axis.scene)
    # transform the mouse position to tile CRS
    # TODO: we should instead transform areas after they are calculated in the axis's CRS
    xpos, ypos = Makie.apply_transform(GeoMakie.create_transform(m.crs, m.axis.dest[]), Point2f(xpos, ypos))
    xspan = (area.X[2] - area.X[1]) * 0.01
    yspan = (area.Y[2] - area.Y[1]) * 0.01
    mouse_area = Extents.Extent(; X=(xpos - xspan, xpos + xspan), Y=(ypos - yspan, ypos + yspan))
    # Make a halo around the mouse tile to load next, intersecting area so we don't download outside the plot
    mouse_halo_area = Tyler.grow_extent(mouse_area, 10)
    # Define a halo around the area to download last, so pan/zoom are filled already
    halo_area = Tyler.grow_extent(area, scheme.halo) # We don't mind that the middle tiles are the same, the OrderedSet will remove them

    # transform the areas to tile crs

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