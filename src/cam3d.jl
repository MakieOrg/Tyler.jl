using Makie: ray_assisted_pick, @extract, mouseposition_px, parent_scene, screen_relative

function translate_cam!(scene, cam::Camera3D, shift::Vec3d)
    fb = cam.lookat[] .- cam.eyeposition[]
    dir_left_right = normalize(cross(fb, cam.upvector[])) .* shift[1]
    dir_front_back = normalize(Vec3(fb[1], fb[2], 0)) .* shift[2]
    dir = (dir_front_back + dir_left_right) ./ 2
    cam.eyeposition[] += dir
    cam.lookat[] += Vec3(dir[1], dir[2], 0)
    update_cam!(scene, cam)
end


function _zoom!(scene, cam::Camera3D, zoom_step)
    s = sign(1 - zoom_step)
    eyepos = cam.eyeposition[]
    lookat = cam.lookat[]
    # just zoom up down
    move_dir = Vec3(0, 0, 1) # -z
    falloff = eyepos[3] / 10
    z_to_move = s .* zoom_step .* falloff
    new_z = max(30, eyepos[3] - z_to_move)
    cam.eyeposition[] = Vec3(eyepos[1], eyepos[2], new_z)

    # Calculate the direction vector from eyeposition to lookat
    direction = Vec3(eyepos[1], eyepos[2], 0.0) .- lookat
    ldistance = norm(direction)
    lookat2d = lookat .+ ((ldistance / 15) .* s .* normalize(direction))
    cam.lookat[] = Vec3(lookat2d[1], lookat2d[2], 0)

    update_cam!(scene, cam)
    return
end

# ─── Cursor-anchored pan & zoom ──────────────────────────────────────────────
#
# Standard map-camera trick from Cesium/Mapbox/Google Earth: instead of moving
# the camera at a fixed pixel-to-world rate (which feels disconnected from the
# map), pick the world point under the cursor on mousedown / scroll, and
# translate/zoom so that point stays anchored to the cursor. Makes the world
# feel like it's physically attached to the mouse.

# Resolve a screen pixel to a world point on the topmost surface plot under it.
#
# Makie.pick gives us the nearest *vertex* index — which at low LOD is up to
# ~150 m off in XY from the true ray-surface hit, and shifts to a different
# location when the LOD changes during zoom (which is what causes the
# "zickzack" anchor wander during scroll). To stay stable, we use the picked
# vertex only as a Z hint and ray-plane intersect at that Z for an accurate
# XY under the cursor.
function pick_world(scene, px)
    plot, idx = Makie.pick(scene, px)
    isnothing(plot) && return nothing
    plot isa Makie.Surface || return nothing
    xs = plot[1][]; ys = plot[2][]; zs = plot[3][]
    w, h = size(zs)
    i = mod1(idx, w)
    j = div(idx - 1, w) + 1
    (1 <= i <= w && 1 <= j <= h) || return nothing
    z_hint = Float64(zs[i, j])
    ray = Makie.Ray(scene, px .- minimum(Makie.viewport(scene)[]))
    hit = ray_plane_intersection(
        Point3d(0, 0, z_hint), Vec3d(0, 0, 1),
        Point3d(ray.origin), Vec3d(ray.direction),
    )
    return hit === nothing ? Vec3d(xs[i], ys[j], z_hint) : Vec3d(hit)
end

# Same but falls back to the z=0 ground plane when no terrain is picked
# (cursor over sky / off the edge of loaded tiles).
function pick_world_or_ground(scene, px)
    p = pick_world(scene, px)
    p === nothing || return p
    ray = Makie.Ray(scene, px .- minimum(Makie.viewport(scene)[]))
    hit = ray_plane_intersection(
        Point3d(0), Vec3d(0, 0, 1),
        Point3d(ray.origin), Vec3d(ray.direction),
    )
    return hit === nothing ? nothing : Vec3d(hit)
end

# Translate the camera horizontally so that the ground projection of `anchor`
# stays under `target_px` on screen. Used during drag-pan.
#
# Two design choices that match Google Earth / Mapbox feel:
#   - Use the z=0 ground plane (not the anchor's own z): consistent across the
#     view, so dragging a mountain peak and dragging a valley behave the same.
#   - Cap per-frame translation magnitude: tilted views can produce arbitrarily
#     large translations when the new cursor ray nearly parallels the plane
#     (cursor near the horizon), which felt like the camera teleporting.
function anchored_translate!(scene, cam::Camera3D, anchor::Vec3d, target_px)
    ray = Makie.Ray(scene, target_px .- minimum(Makie.viewport(scene)[]))
    hit = ray_plane_intersection(
        Point3d(0, 0, 0), Vec3d(0, 0, 1),
        Point3d(ray.origin), Vec3d(ray.direction),
    )
    hit === nothing && return  # ray nearly parallel to ground / above horizon
    T = Vec3d(anchor[1] - hit[1], anchor[2] - hit[2], 0.0)
    # Cap to a fraction of camera altitude so a horizon-grab can't teleport.
    eye_alt = max(1.0, abs(Float64(cam.eyeposition[][3])))
    cap = 0.5 * eye_alt
    n = norm(T)
    n > cap && (T = T * (cap / n))
    cam.eyeposition[] = cam.eyeposition[] + T
    cam.lookat[] = cam.lookat[] + T
    update_cam!(scene, cam)
    return
end

# Zoom toward / away from a fixed world anchor. `factor < 1` zooms in (camera
# moves toward anchor), `factor > 1` zooms out. The full camera rig (eye +
# lookat) translates by the same delta so orientation is preserved.
function anchored_zoom!(scene, cam::Camera3D, anchor::Vec3d, factor::Float64)
    eye = Vec3d(cam.eyeposition[])
    new_eye = anchor + factor * (eye - anchor)
    # don't let the camera punch through whatever it's zooming into
    norm(new_eye - anchor) < 10.0 && return
    T = new_eye - eye
    cam.eyeposition[] = cam.eyeposition[] + T
    cam.lookat[] = cam.lookat[] + T
    update_cam!(scene, cam)
    return
end

function signed_angle_between(v1::Vec3, v2::Vec3, normal::Vec3=Vec3d(0, 0, 1))
    # Normalize both vectors
    v1n = normalize(v1)
    v2n = normalize(v2)

    # Calculate the dot product
    d = dot(v1n, v2n)

    # Calculate the cosine of the angle
    cos_theta = clamp(d, -1.0, 1.0)

    # Calculate the angle in radians
    angle_rad = acos(cos_theta)

    # Calculate the cross product
    cross_product = cross(v1n, v2n)
    if dot(cross_product, normal) < 0
        return -angle_rad
    end
    return angle_rad
end


function t_rotate_cam!(scene, cam::Camera3D, angles::VecTypes, from_mouse=false)
    @extractvalue cam.controls (fix_x_key, fix_y_key, fix_z_key)
    @extractvalue cam.settings (fixed_axis, circular_rotation, rotation_center)

    # This applies rotations around the x/y/z axis of the camera coordinate system
    # x expands right, y expands up and z expands towards the screen
    lookat = cam.lookat[]
    eyepos = cam.eyeposition[]
    up = cam.upvector[]         # +y
    viewdir = lookat - eyepos   # -z
    right = cross(viewdir, up)  # +x
    x_axis = right
    y_axis = Vec3d(0, 0, 1)
    z_axis = -viewdir

    rotation = Quaternionf(0, 0, 0, 1)
    # restrict total quaternion rotation to one axis
    rotation *= qrotation(y_axis, angles[2])
    rotation *= qrotation(x_axis, angles[1])
    rotation *= qrotation(z_axis, angles[3])
    new_viewdir = rotation * viewdir
    new_angle = signed_angle_between(new_viewdir, Vec3d(0, 0, -1), -right)
    if new_angle > 0 && new_angle < deg2rad(80)
        new_lookat = ray_plane_intersection(Point3d(0), Vec3d(0, 0, 1), Point(eyepos), Vec(new_viewdir))
        isnothing(new_lookat) && return
        cam.upvector[] = rotation * up
        cam.lookat[] = new_lookat
        update_cam!(scene, cam)
    end
    return
end

function add_tyler_mouse_controls!(scene, cam::Camera3D)
    @extract cam.controls (translation_button, rotation_button, reposition_button, scroll_mod)
    @extract cam.settings (
        mouse_translationspeed, mouse_rotationspeed, mouse_zoomspeed,
        cad, projectiontype, zoom_shift_lookat
    )

    last_mousepos = Base.RefValue(Vec2d(0, 0))
    dragging = Base.RefValue((false, false)) # rotation, translation
    # World point picked under the cursor at the start of a translation drag.
    # Stays fixed in world space; we translate the camera each mouseposition
    # event to keep this point under the cursor.
    pan_anchor = Base.RefValue{Union{Nothing, Vec3d}}(nothing)
    # Same idea for scroll-zoom: re-picking the anchor every scroll event
    # causes "zickzack" because the picked vertex jumps between LODs as the
    # zoom progresses. Cache the first pick and reuse it for rapid scrolls.
    zoom_anchor = Base.RefValue{Union{Nothing, Vec3d}}(nothing)
    last_zoom_time = Base.RefValue(0.0)

    e = events(scene)

    # drag start/stop
    on(camera(scene), e.mousebutton) do event
        # Drag start translation/rotation
        if event.action == Mouse.press && is_mouseinside(scene)
            if ispressed(scene, translation_button[])
                last_mousepos[] = mouseposition_px(scene)
                pan_anchor[] = pick_world_or_ground(scene, last_mousepos[])
                dragging[] = (false, true)
                return Consume(true)
            elseif ispressed(scene, rotation_button[])
                last_mousepos[] = mouseposition_px(scene)
                dragging[] = (true, false)
                return Consume(true)
            end
            # drag stop & repostion
        elseif event.action == Mouse.release
            consume = false

            if dragging[][1] || dragging[][2]
                if dragging[][2]
                    pan_anchor[] = nothing
                else
                    mousepos = mouseposition_px(scene)
                    rot_scaling = mouse_rotationspeed[] * (e.window_dpi[] * 0.005)
                    mp = (last_mousepos[] .- mousepos) .* 0.01 .* rot_scaling
                    last_mousepos[] = mousepos
                    t_rotate_cam!(scene, cam, Vec3d(-mp[2], mp[1], 0.0), true)
                end
                dragging[] = (false, false)
                consume = true
            end

            return Consume(consume)
        end

        return Consume(false)
    end

    # in drag
    on(camera(scene), e.mouseposition) do mp
        if dragging[][2] && ispressed(scene, translation_button[])
            mousepos = screen_relative(scene, mp)
            last_mousepos[] = mousepos
            anchor = pan_anchor[]
            anchor === nothing || anchored_translate!(scene, cam, anchor, mousepos)
            return Consume(true)
        elseif dragging[][1] && ispressed(scene, rotation_button[])
            mousepos = screen_relative(scene, mp)
            rot_scaling = mouse_rotationspeed[] * (e.window_dpi[] * 0.005)
            mp = (last_mousepos[] .- mousepos) * 0.01 * rot_scaling
            last_mousepos[] = mousepos
            t_rotate_cam!(scene, cam, Vec3d(-mp[2], mp[1], 0.0), true)
            return Consume(true)
        end
        return Consume(false)
    end

    # zoom — cursor-anchored: scroll over a mountain peak and that peak grows
    # under the cursor instead of drifting toward the screen edge.
    on(camera(scene), e.scroll) do scroll
        if is_mouseinside(scene) && ispressed(scene, scroll_mod[])
            now = time()
            # Reuse the anchor from the previous scroll event if it was recent.
            # Picking changes as LOD swaps during zoom, so re-picking every
            # event would zigzag the cursor across the world point we meant
            # to hold. 0.4 s catches typical bursts without sticking forever.
            if zoom_anchor[] === nothing || now - last_zoom_time[] > 0.4
                zoom_anchor[] = pick_world_or_ground(scene, mouseposition_px(scene))
            end
            last_zoom_time[] = now
            anchor = zoom_anchor[]
            anchor === nothing && return Consume(true)
            factor = (1.0 + 0.1 * mouse_zoomspeed[])^-scroll[2]
            anchored_zoom!(scene, cam, anchor, factor)
            return Consume(true)
        end
        return Consume(false)
    end
end