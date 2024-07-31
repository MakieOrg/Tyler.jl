
struct Tiling3D <: FetchingScheme
end
using GeometryBasics, LinearAlgebra

function setup_axis!(axis::LScene, ext_target)
    X = ext_target.X
    Y = ext_target.Y
    pmin = Vec3(X[1], Y[1], 0)
    xrange = X[2] - X[1]
    center = Vec3((X[1] + X[2]) / 2, (Y[1] + Y[2]) / 2, 0)
    xaxis = Vec3(xrange / 2, 0, 0)
    eyeposition = pmin .+ xaxis .+ Vec3(0, 0, 0.8 * xrange)
    up = cross(xaxis, center .- eyeposition)
    cam = axis.scene.camera_controls
    cam.settings.clipping_mode[] = :static

    cam.near[] = 10f0
    cam.far[] = xrange * 100f0
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
        fetching_scheme=Tiling3D(),
        args...
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
        args...
    )
end

function tile_reloader(m::Map{LScene}, area)
    scene = m.axis.scene
    camc = scene.camera_controls
    update_signal = map((a,b)->nothing, camc.lookat, camc.eyeposition)
    throttled = Makie.Observables.throttle(0.2, update_signal)
    on(scene, throttled; update=true) do _
        update_tiles!(m, (scene.camera, camc))
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

using LinearAlgebra, GeometryBasics
using GeometryBasics: Point4d, Point3d

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

function frustrum_plane_intersection(cam::Camera, camc::Camera3D)
    frustrum = frustum_snapshot(cam)
    result = Union{Nothing, Point3d}[]
    eyepos = camc.eyeposition[]
    for point in frustrum
        res = ray_plane_intersection(Point3f(0), Vec3f(0, 0, 1), Point3f(eyepos), Vec3f(point .- eyepos))
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
    return Rect2f(extent.X[1], extent.Y[1], extent.X[2] - extent.X[1], extent.Y[2] - extent.Y[1])
end

function optimal_zoom(m::Map, diagonal)
    diagonal_res = norm(get_resolution(m)) * 0.6
    zoomrange = min_zoom(m):max_zoom(m)
    optimal_zoom(m.crs, diagonal, diagonal_res, zoomrange, m.zoom[])
end

function optimal_zoom(crs, diagonal, diagonal_resolution, zoom_range, old_zoom)
    # Some provider only support one zoom level
    length(zoom_range) == 1 && return zoom_range[1]
    # TODO, this should come from provider
    tile_diag_res = norm((255,255))
    target_ntiles = diagonal_resolution / tile_diag_res
    canditates_dict = Dict{Int, Float64}()
    candidates = @NamedTuple{z::Int, ntiles::Float64}[]
    for z in zoom_range
        ext = Extents.extent(Tile(0, 0, z), crs)
        diag = norm(Point2f(ext.X[2], ext.Y[2]) .- Point2f(ext.X[1], ext.Y[1]))
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

import GeometryOps as GO

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

function get_tiles_for_area(m::Map{LScene}, ::Tiling3D, (cam, camc)::Tuple{Camera,Camera3D})
    points = frustrum_plane_intersection(cam, camc)
    eyepos = camc.eyeposition[]
    maxdist, _ = findmax(p -> norm(p[3] .- eyepos), points)
    mindist, _ = findmin(p -> norm(p[3] .- eyepos), points)
    camc.far[] = maxdist * 1.5
    camc.near[] = mindist * 0.0001
    return tiles_from_poly(m, points), OrderedSet{Tile}()
end
