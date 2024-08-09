
using GeometryBasics, LinearAlgebra

function setup_axis!(axis::LScene, ext_target, crs)
    # Disconnect all events
    scene = axis.scene
    cam = scene.camera_controls
    Makie.disconnect!(scene.camera)
    # add back our mouse controls
    add_tyler_mouse_controls!(scene, cam)
    X = ext_target.X
    Y = ext_target.Y
    pmin = Vec3(X[1], Y[1], 0)
    xrange = X[2] - X[1]
    center = Vec3((X[1] + X[2]) / 2, (Y[1] + Y[2]) / 2, 0)
    xaxis = Vec3(xrange / 2, 0, 0)
    eyeposition = pmin .+ xaxis .+ Vec3(0, 0, 0.8 * xrange)
    up = cross(xaxis, center .- eyeposition)
    cam.settings.clipping_mode[] = :static
    update_cam!(axis.scene, eyeposition, center, up)
    return
end

function Map3D(extent, extent_crs=wgs84;
        size=(1000, 1000),
        figure=Makie.Figure(; size=size),
        axis=Makie.LScene(figure[1, 1]; show_axis=false),
        provider=TileProviders.OpenStreetMap(:Mapnik),
        fetching_scheme=Tiling3D(),
        args...
    )
    return Map(
        extent, extent_crs;
        figure=figure,
        axis=axis,
        provider=provider,
        fetching_scheme=fetching_scheme,
        args...
    )
end

function tile_reloader(m::Map{LScene})
    scene = m.axis.scene
    camc = scene.camera_controls
    update_signal = map((a,b)->nothing, camc.lookat, camc.eyeposition)
    throttled = Makie.Observables.throttle(0.2, update_signal)
    on(scene, throttled; update=true) do _
        update_tiles!(m, (scene.camera, camc))
        return
    end
end


function frustum_snapshot(cam::Camera)
    bottom_left = Point4d(-1, -1, 1, 1)
    top_left = Point4d(-1, 1, 1, 1)
    top_right = Point4d(1, 1, 1, 1)
    bottom_right = Point4d(1, -1, 1, 1)
    rect_ps = [bottom_left, top_left, top_right, bottom_right]
    inv_pv = inv(cam.projectionview[])
    return map(rect_ps) do p
        p = inv_pv * p
        return p[Vec(1, 2, 3)] / p[4]
    end
end

# Function to find the intersection of a ray with a plane
function ray_plane_intersection(position::Point3, normal::Vec3, start::Point3, direction::Vec3)::Union{Point3,Nothing}
    # Calculate the denominator of the intersection formula
    denom = dot(normal, direction)
    if abs(denom) > 1e-6
        # Calculate the numerator of the intersection formula
        numerator = dot(normal, position .- start)
        t = numerator / denom
        if t >= 0
            # The intersection point is at t * direction from the ray's start point
            intersection = start .+ t .* direction
            return intersection
        end
    end
    # Return nothing if there is no intersection
    return nothing
end

function area_around_lookat(camc::Camera3D, multiplier=2)
    x, y, _ = camc.lookat[]
    z = camc.eyeposition[][3]
    w = multiplier * z
    return Rect2d(x - w, y - w, 2w, 2w)
end

function frustrum_plane_intersection(cam::Camera, camc::Camera3D)
    frustrum = frustum_snapshot(cam)
    result = Union{Nothing, Point3d}[]
    eyepos = camc.eyeposition[]
    for point in frustrum
        res = ray_plane_intersection(Point3d(0), Vec3d(0, 0, 1), Point3d(eyepos), Vec3d(point .- eyepos))
        push!(result, res)
    end
    x, y, _ = camc.lookat[]
    z = camc.eyeposition[][3]
    w = 2 * z
    fallback = [Point3d(x - w, y - w, 0), Point3d(x - w, y + w, 0), Point3d(x + w, y + w, 0), Point3d(x + w, y - w, 0)]
    return map(enumerate(result)) do (i, res)
        if !isnothing(res)
            return res
        else
            return fallback[i]
        end
    end
end

function to_rect(extent::Extent)
    return Rect2(extent.X[1], extent.Y[1], extent.X[2] - extent.X[1], extent.Y[2] - extent.Y[1])
end

function tiles_from_poly(m::Map, points)
    mini = minimum(points)
    points_s = sort(points, by=(x -> norm(x .- mini)))
    start = points_s[1]
    diagonal = norm(points_s[end] .- start)
    zoom = optimal_zoom(m, diagonal)
    m.zoom[] = zoom
    boundingbox = Rect2d(Rect3d(points))
    ext = Extents.extent(boundingbox)
    tilegrid = TileGrid(ext, zoom, m.crs)
    tiles = OrderedSet{Tile}()
    poly = Polygon(map(p-> Point2d(p[1], p[2]), points))
    for tile in tilegrid
        tile_ext = to_rect(Extents.extent(tile, m.crs))
        tile_poly = Polygon(decompose(Point2d, tile_ext))
        if GO.intersects(poly, tile_poly)
            push!(tiles, tile)
        end
    end
    return tiles
end
