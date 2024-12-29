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

    e = events(scene)

    function compute_diff(delta)
        if projectiontype[] == Makie.Perspective
            # TODO wrong scaling? :(
            ynorm = 2 * norm(cam.lookat[] - cam.eyeposition[]) * tand(0.5 * cam.fov[])
            return ynorm / size(scene, 2) * delta
        else
            viewnorm = norm(cam.eyeposition[] - cam.lookat[])
            return 2 * viewnorm / size(scene, 2) * delta
        end
    end

    # drag start/stop
    on(camera(scene), e.mousebutton) do event
        # Drag start translation/rotation
        if event.action == Mouse.press && is_mouseinside(scene)
            if ispressed(scene, translation_button[])
                last_mousepos[] = mouseposition_px(scene)
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

            # Drag stop translation/rotation
            if dragging[][1]
                mousepos = mouseposition_px(scene)
                diff = compute_diff(last_mousepos[] .- mousepos)
                last_mousepos[] = mousepos
                dragging[] = (false, false)
                translate_cam!(scene, cam, mouse_translationspeed[] .* Vec3d(diff[1], diff[2], 0.0))
                consume = true
            elseif dragging[][2]
                mousepos = mouseposition_px(scene)
                dragging[] = (false, false)
                rot_scaling = mouse_rotationspeed[] * (e.window_dpi[] * 0.005)
                mp = (last_mousepos[] .- mousepos) .* 0.01 .* rot_scaling
                last_mousepos[] = mousepos
                t_rotate_cam!(scene, cam, Vec3d(-mp[2], mp[1], 0.0), true)
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
            diff = compute_diff(last_mousepos[] .- mousepos)
            last_mousepos[] = mousepos
            translate_cam!(scene, cam, mouse_translationspeed[] * Vec3d(diff[1], diff[2], 0.0))
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

    #zoom
    on(camera(scene), e.scroll) do scroll
        if is_mouseinside(scene) && ispressed(scene, scroll_mod[])
            zoom_step = (1.0 + 0.1 * mouse_zoomspeed[])^-scroll[2]
            _zoom!(scene, cam, zoom_step)
            return Consume(true)
        end
        return Consume(false)
    end
end