########################################
#              PlotConfig              #
########################################


function create_tileplot!(
    config::PlotConfig, axis::GeoAxis, m, data::ImageData, bounds::Rect, tile_crs
)
    mini, maxi = extrema(bounds)
    plot = GeoMakie.meshimage!(
        axis,
        (mini[1], maxi[1]), (mini[2], maxi[2]), data;
        uv_transform=:rotr90,
        inspectable=false,
        reset_limits=false, # substitute for plotting directly to scene, since GeoMakie handles the CRS stuff
        xautolimits = false,
        yautolimits = false,
        source = tile_crs[2], # tile_crs is a tuple of (tile, crs), we can pass the CRS directly to GeoMakie though
        config.attributes...
    )
    # For a pure GeoAxis this is OK, because it is guaranteed to be 2D.
    # But for a 3D axis like GlobeAxis this is not OK and has to be removed.
    translate!(plot, 0, 0, -10)
    return plot
end

function Tyler.update_tile_plot!(plot::GeoMakie.MeshImage, ::PlotConfig, axis::AbstractAxis, m, data::ImageData, bounds::Rect, tile_crs)
    mini, maxi = extrema(bounds)
    update!(plot, (mini[1], maxi[1]), (mini[2], maxi[2]), data)
    return
end


########################################
#           DebugPlotConfig            #
########################################

function create_tileplot!(config::DebugPlotConfig, axis::GeoAxis, m, data::ImageData, bounds::Rect, tile_crs)
    plot = Makie.poly!(
        axis,
        bounds;
        color=reverse(data; dims=1),
        strokewidth=2,
        strokecolor=:black,
        inspectable=false,
        stroke_depth_shift=-0.01f0,
        reset_limits=false, # substitute for plotting directly to scene, since GeoMakie handles the CRS stuff
        source = tile_crs[2], # tile_crs is a tuple of (tile, crs), we can pass the CRS directly to GeoMakie though
        config.attributes...
    )
    return plot
end

function update_tile_plot!(plot::Makie.Poly, ::DebugPlotConfig, axis::GeoAxis, m, data::ImageData, bounds::Rect, tile_crs)
    update!(plot, bounds; color = reverse(data; dims = 1))
    return
end