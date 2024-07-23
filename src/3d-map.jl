
struct Tiling3D <: FetchingScheme
end
using GeometryBasics, LinearAlgebra

function setup_axis!(axis::LScene, ext_target)
    X = ext_target.X
    Y = ext_target.Y
    pmin = Vec3(X[1], Y[1], 0)
    pmax = Vec3(X[2], Y[2], 0)
    xrange = X[2] - X[1]
    center = Vec3((X[1] + X[2]) / 2, (Y[1] + Y[2]) / 2, 0)
    xaxis = Vec3(xrange / 2, 0, 0)
    eyeposition = pmin .+ xaxis .+ Vec3(0, 0, 0.8 * xrange)
    up = cross(xaxis, center .- eyeposition)
    cam = axis.scene.camera_controls
    cam.settings.clipping_mode[] = :static
    cam.far[] = xrange * 100f0
    cam.near[] = 100f0

    cam.controls.fix_x_key[] = true
    cam.controls.fix_y_key[] = true
    cam.settings.circular_rotation[] = (false, false, false)
    cam.settings.fixed_axis[] = true
    cam.settings.rotation_center[] = :eyeposition
    update_cam!(axis.scene, eyeposition, center, up)
    return
end

function Map3D(extent, extent_crs=wgs84;
        size=(1000, 1000),
        figure=Makie.Figure(; size=size),
        axis=Makie.LScene(figure[1, 1]; show_axis=false),
        provider=TileProviders.OpenStreetMap(:Mapnik),
        fetching_scheme=Tiling3D()
    )

    return Map(
        extent, extent_crs;
        resolution=(1000, 1000),
               figure=figure,
               axis=axis,
               provider=provider,
        crs=MapTiles.web_mercator,
        cache_size_gb=5,
        fetching_scheme = fetching_scheme,
    )
end


function tile_reloader(map::Map{LScene}, area)
    scene = map.axis.scene
    cam = scene.camera_controls
    on(scene, cam.eyeposition; update=true) do position
        update_tiles!(map, (position, cam.lookat[]))
        return
    end
end

function get_extent(map::Map{LScene})
    scene = map.axis.scene
    cam = scene.camera_controls
    position = cam.eyeposition[]
    lookat = cam.lookat[]
    x, y, _ = lookat
    z = position[3]
    return Rect2f(x - z, y - z, 2 * z, 2 * z)
end

function get_tiles_for_area(m::Map{LScene}, ::Tiling3D, (eyeposition, lookat))
    x, y, _ = lookat
    z = eyeposition[3]
    area = Rect2f(x - z, y - z, 2*z, 2*z)
    ext = Extents.extent(area)
    # `depth` determines the number of layers below the current
    # layer to load. Tiles are downloaded in order from lowest to highest zoom.
    # Calculate the zoom level
    z = clamp(z_index(ext, (2000, 2000), m.crs), min_zoom(m), max_zoom(m))
    m.zoom[] = z

    return OrderedSet{Tile}(MapTiles.TileGrid(ext, z, m.crs))
end
