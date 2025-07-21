########################################
#              PlotConfig              #
########################################


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
    update!(plot, (mini[1], maxi[1]), (mini[2], maxi[2]), data)
    return
end


########################################
#           DebugPlotConfig            #
########################################

function create_tileplot!(config::DebugPlotConfig, axis::GeoAxis, data::ImageData, bounds::Rect, tile_crs)
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

function update_tile_plot!(plot::Makie.Poly, ::DebugPlotConfig, axis::GeoAxis, data::ImageData, bounds::Rect, tile_crs)
    update!(plot, bounds; color = reverse(data; dims = 1))
    return
end