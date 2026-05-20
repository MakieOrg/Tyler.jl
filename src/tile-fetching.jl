# Queue management

function queue_plot!(m::Map, tile)
    key = tile_key(m.provider, tile)
    # Provider doesn't have a tile for this
    isnothing(key) && return
    m.should_get_plotted[key] = tile
    put!(m.tiles.tile_queue, tile)
    return
end

function cleanup_queue!(m::AbstractMap, to_keep::OrderedSet{Tile})
    queue = m.tiles.tile_queue
    lock(queue) do
        tiles = Tile[]
        queued = queue.data
        filter!(queued) do tile
            if !(tile in to_keep)
                Base._increment_n_avail(queue, -1)
                push!(tiles, tile)
                return false
            else
                return true
            end
        end
        for tile in tiles
            delete!(m.should_get_plotted, tile_key(m.provider, tile))
        end
    end
end

function update_tiles!(m::Map, arealike)
    # Get the tiles to be plotted from the fetching scheme and arealike
    tiles = get_tiles_for_area(m, m.fetching_scheme, arealike)
    if length(tiles.foreground) > m.max_plots
        @warn "Too many tiles to plot, which means zoom level is not supported. Plotting no tiles for this zoomlevel." maxlog = 1
        empty!(tiles.foreground)
        empty!(tiles.background)
        empty!(tiles.offscreen)
    end
    queued_or_plotted = values(m.should_get_plotted)
    # Queue tiles to be downloaded & displayed
    to_add = map(t -> setdiff(t, queued_or_plotted), tiles)

    # replace
    empty!(m.foreground_tiles)
    for tile in tiles.foreground
        m.foreground_tiles[tile] = true
    end

    # Move all plots to the back, that aren't in the newest tileset anymore
    for (key, (plot, tile, bounds)) in m.plots
        move_z(m, plot, tile, bounds)
    end

    # Remove any item from queue, that isn't in the new set
    to_keep_queued = union(tiles...)
    # Remove all tiles that are not in the new set from the queue
    cleanup_queue!(m, to_keep_queued)

    # The unique is needed to avoid tiles referencing the same tile
    # TODO, we should really consider to disallow this for tile providers,
    # This is currently only allowed because of the PointCloudProvider
    to_add_keys = map(to_add) do ta
        unique(t -> tile_key(m.provider, t), ta)
    end

    # We lock the queue, to put all tiles in one go into the tile queue
    # Without the lock, a few (n_download_threads) old tiles will be downloaded first
    # since they will be the last in the queue until we add the new tiles
    lock(m.tiles.tile_queue) do
        # Queue is LIFO (take_last!), so the LAST tile pushed is the FIRST one
        # downloaded. Order from lowest-to-highest priority:
        #   1. Offscreen halo — prefetch, lowest priority
        #   2. Background coarser tiles — fallback while foreground loads
        #   3. Foreground tiles — what the user actually sees, highest priority
        # Previously the order was reversed (background pushed last), which
        # made foreground starve behind 30+ depth=8 backdrop tiles. After fast
        # zoom-in/out, foreground would not arrive until the entire backdrop
        # queue drained.
        foreach(tile -> queue_plot!(m, tile), to_add_keys.offscreen)
        foreach(tile -> queue_plot!(m, tile), to_add_keys.background)
        foreach(tile -> queue_plot!(m, tile), to_add_keys.foreground)
    end
end

#########################################################################################
##### Halo2DTiling

struct Halo2DTiling <: FetchingScheme
    depth::Int
    halo::Float64
    pixel_scale::Float64
end

Halo2DTiling(; depth=2, halo=0.4, pixel_scale=2.0) = Halo2DTiling(depth, halo, pixel_scale)

function get_tiles_for_area(m::Map{Axis}, scheme::Halo2DTiling, area::Union{Rect,Extent})
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

#########################################################################################
##### SimpleTiling

struct SimpleTiling <: FetchingScheme
end

function get_tiles_for_area(m::Map, ::SimpleTiling, area::Union{Rect,Extent})
    area = typeof(area) <: Rect ? Extents.extent(area) : area
    diag = norm(widths(to_rect(area)))
    # Calculate the zoom level
    ideal_zoom, zoom, approx_ntiles = optimal_zoom(m, diag)
    m.zoom[] = zoom
    foreground = OrderedSet{Tile}(MapTiles.TileGrid(area, zoom, m.crs))
    background = OrderedSet{Tile}()
    offscreen = OrderedSet{Tile}()
    return (; foreground, background, offscreen)
end

#########################################################################################
##### Tiling3D

struct Tiling3D <: FetchingScheme
end

function get_tiles_for_area(m::Map{LScene}, ::Tiling3D, (cam, camc)::Tuple{Camera,Camera3D})
    points = frustrum_plane_intersection(cam, camc)
    eyepos = camc.eyeposition[]
    # Bug fix: was `norm(p[3] .- eyepos)` which is `norm(scalar .- vec3)` —
    # broadcasts the Z component over each eye axis, producing the magnitude
    # of `eyepos` itself (~7e6 in web-mercator scenes!) instead of the
    # distance from eye to ground-projected corner. Result: far ≈ 7e6 with
    # near ≈ 40, giving a depth-buffer ratio of ~150 000 that crashes
    # GLMakie's depth pass on AMD drivers and produces severe z-fighting
    # elsewhere. Now we measure the actual distance.
    maxdist, _ = findmax(p -> norm(p - eyepos), points)
    camc.far[] = maxdist
    camc.near[] = max(1.0, eyepos[3] * 0.01)
    update_cam!(m.axis.scene)
    foreground = tiles_from_poly(m, points)
    background = OrderedSet{Tile}()
    # for i in 2:2:6
    #     tiles = tiles_from_poly(m, points; zshift=-i)
    #     union!(foreground, tiles)
    # end
    offscreen = OrderedSet{Tile}()
    tiles = (; foreground, background, offscreen)
    return tiles
    # Reverse the order of the groups. Reversing the ranges
    # above doesn't have the same effect due to then unions
    # return map(OrderedSet ∘ reverse ∘ collect, tiles)
end
function get_tiles_for_area(m::Map{LScene}, s::SimpleTiling, (cam, camc)::Tuple{Camera,Camera3D})
    area = area_around_lookat(camc)
    return get_tiles_for_area(m, s, area)
end

#########################################################################################
##### SSETiling3D — Cesium-style screen-space-error quadtree selection
#
# Replaces Tiling3D's "intersect frustum with ground plane, pick one zoom level"
# approach with a recursive quadtree descent driven by per-tile screen-space
# error. Tiles near the camera refine deeper; far tiles stay coarse. Each tile's
# 3D bounding box (X,Y from MapTiles + Z from `tile_z_bounds(provider, tile)`)
# is tested against the 6 view-frustum planes for culling.

"""
    SSETiling3D(; sse_threshold=8.0, max_depth=22)

3D tile selection by screen-space error. `sse_threshold` is the pixel error
above which a tile is subdivided; lower = sharper + more tiles. `max_depth`
caps recursion as a safety net.
"""
struct SSETiling3D <: FetchingScheme
    sse_threshold::Float64
    max_depth::Int
end
SSETiling3D(; sse_threshold=8.0, max_depth=22) = SSETiling3D(sse_threshold, max_depth)

# Web Mercator world width in meters.
web_mercator_world_m() = 4.0075016686e7

# Geometric error of a raster tile at zoom z: one source-pixel size in world
# units, assuming 256 px per tile.
tile_geometric_error(z::Integer) = web_mercator_world_m() / (256 * 2.0^z)

# 6 frustum planes (a,b,c,d) such that a*x+b*y+c*z+d ≥ 0 for points inside.
# Standard derivation from the projection*view matrix rows.
function frustum_planes(pv::Mat4)
    r1 = Vec4d(pv[1,1], pv[1,2], pv[1,3], pv[1,4])
    r2 = Vec4d(pv[2,1], pv[2,2], pv[2,3], pv[2,4])
    r3 = Vec4d(pv[3,1], pv[3,2], pv[3,3], pv[3,4])
    r4 = Vec4d(pv[4,1], pv[4,2], pv[4,3], pv[4,4])
    return (r4 + r1, r4 - r1, r4 + r2, r4 - r2, r4 + r3, r4 - r3)
end

# AABB vs frustum, p-vertex test: pick the corner most positive in the plane's
# direction; if even that is on the negative side, the whole box is outside.
function aabb_outside_frustum(planes, xmin, xmax, ymin, ymax, zmin, zmax)
    for p in planes
        a, b, c, d = p[1], p[2], p[3], p[4]
        px = a > 0 ? xmax : xmin
        py = b > 0 ? ymax : ymin
        pz = c > 0 ? zmax : zmin
        a*px + b*py + c*pz + d < 0 && return true
    end
    return false
end

# Closest-point distance from `eye` to the tile AABB. When the z range is
# loose, pick whichever of zmin/zmax is _farther_ from the eye — this
# over-estimates distance, which under-estimates SSE, which biases the
# selector toward _too little_ detail rather than too much. Same trick as
# Cesium's BoundingRegionWithLooseFittingHeights.
function tile_distance(eye::Vec3d, xmin, xmax, ymin, ymax, zmin, zmax, loose::Bool)
    cx = clamp(eye[1], xmin, xmax)
    cy = clamp(eye[2], ymin, ymax)
    cz = loose ?
        (abs(eye[3] - zmin) > abs(eye[3] - zmax) ? zmin : zmax) :
        clamp(eye[3], zmin, zmax)
    return sqrt((eye[1]-cx)^2 + (eye[2]-cy)^2 + (eye[3]-cz)^2)
end

# Recursive quadtree descent driven by screen-space error. `sse_denom` is the
# per-frame constant 2*tan(fov_y/2)/viewport_h so that
# sse = geom_err / (dist * sse_denom).
#
# Parent-stays-while-children-load is handled at plot time by Tyler's existing
# filter_overlapping! (tile-plotting.jl): once a finer child plot arrives, the
# coarser parent plot is replaced. So this selector only chooses the ideal LOD
# per region — fallback comes from the previous frame's plots still being on
# screen, plus the cold-start coarse pass that get_tiles_for_area adds below.
# Enumerate tiles at a given zoom level that overlap the ground-plane footprint
# `ground_pts` (the camera frustum projected onto z=0). Used to seed the SSE
# descent at min_z so we don't recurse through low zoom levels whose tiles are
# bigger than the entire view.
function tiles_at_zoom(ground_pts::AbstractVector{<:Point3}, zoom::Int, crs)
    bbox = Rect2d(Rect3d(ground_pts))
    ext = Extents.extent(bbox)
    tilegrid = TileGrid(ext, zoom, crs)
    tiles = OrderedSet{Tile}()
    poly = Polygon(map(p -> Point2d(p[1], p[2]), ground_pts))
    for tile in tilegrid
        tile_ext = to_rect(Extents.extent(tile, crs))
        tile_poly = Polygon(decompose(Point2d, tile_ext))
        GO.intersects(poly, tile_poly) && push!(tiles, tile)
    end
    return tiles
end

function select_sse!(out::OrderedSet{Tile}, tile::Tile, provider, planes,
                     eyepos::Vec3d, sse_denom::Float64, threshold::Float64,
                     min_z::Int, max_z::Int, max_depth::Int)
    ext = MapTiles.extent(tile, web_mercator)
    xmin, xmax = ext.X
    ymin, ymax = ext.Y
    zmin, zmax, loose = tile_z_bounds(provider, tile)

    # Frustum-cull first — without this, providers with min_zoom > 0 (e.g.
    # GeoTilePointCloudProvider with min_zoom=16) fan out exponentially before
    # reaching their first renderable level. 4^15 recursive calls hangs the
    # constructor.
    aabb_outside_frustum(planes, xmin, xmax, ymin, ymax, zmin, zmax) && return

    if tile.z < min_z
        @goto recurse  # below the provider's renderable range — keep refining
    end

    if tile.z >= max_z || tile.z >= max_depth
        push!(out, tile)
        return
    end

    dist = max(tile_distance(eyepos, xmin, xmax, ymin, ymax, zmin, zmax, loose), 1e-3)
    sse = tile_geometric_error(tile.z) / (dist * sse_denom)
    if sse <= threshold
        push!(out, tile)
        return
    end

    @label recurse
    for dx in 0:1, dy in 0:1
        select_sse!(out, Tile(2*tile.x + dx, 2*tile.y + dy, tile.z + 1),
                    provider, planes, eyepos, sse_denom,
                    threshold, min_z, max_z, max_depth)
    end
    return
end

# Called from the download consumer loop after every successful tile plot.
# As tiles arrive their bounds tighten in the provider; under SSE that
# typically means the selector now wants finer LOD for those areas. Re-fire
# update_tiles! at most a few times per second so the view keeps refining
# while the camera sits still — without this the view freezes at whatever
# LOD was chosen when the camera last moved.
#
# Only useful for 3D + SSETiling3D; other schemes don't depend on bounds.
function maybe_refine_for_sse!(m::AbstractMap, last_refine::Ref{Float64})
    m isa Map{LScene} || return
    m.fetching_scheme isa SSETiling3D || return
    now = time()
    now - last_refine[] < 0.5 && return
    last_refine[] = now
    scene = m.axis.scene
    update_tiles!(m, (scene.camera, scene.camera_controls))
    return
end

function get_tiles_for_area(m::Map{LScene}, scheme::SSETiling3D,
                            (cam, camc)::Tuple{Camera,Camera3D})
    eyepos = Vec3d(camc.eyeposition[])

    # Camera defaults to near=0.1, far=100 — at geo scale that puts the far
    # plane ~8 km from the eye, so the projectionview matrix's frustum
    # excludes most of the actual scene. Calibrate from ray-to-ground first
    # (same trick the old Tiling3D used) before reading the matrix.
    ground_pts = frustrum_plane_intersection(cam, camc)
    maxdist, _ = findmax(p -> norm(p .- eyepos), ground_pts)
    camc.far[] = maxdist
    camc.near[] = max(1.0, eyepos[3] * 0.01)
    update_cam!(m.axis.scene)

    planes = frustum_planes(cam.projectionview[])
    fov_y_rad = deg2rad(Float64(camc.fov[]))
    vp_h = Float64(get_resolution(m)[2])
    sse_denom = 2 * tan(fov_y_rad / 2) / vp_h

    min_z = min_zoom(m)
    max_z = max_zoom(m)

    # Find the tiles at zoom = min_z that the camera frustum touches. We can't
    # start the SSE descent at Tile(0,0,0) — at low zoom levels every tile's
    # AABB straddles all 6 frustum planes (the world is much bigger than the
    # frustum), so AABB-vs-frustum p-vertex culling can't prune anything and
    # the recursion fans out exponentially (4^min_z calls before the first
    # cull).  Directly enumerating min_z tiles from the ground-plane footprint
    # bypasses that pathological descent.
    seed_tiles = tiles_at_zoom(ground_pts, min_z, m.crs)
    foreground = OrderedSet{Tile}()
    for seed in seed_tiles
        select_sse!(foreground, seed, m.provider, planes, eyepos,
                    sse_denom, scheme.sse_threshold, min_z, max_z, scheme.max_depth)
    end

    # Drive move_z's "show coarser plots as fallback" rule by exposing the
    # deepest selected zoom. Without this m.zoom stays at 0 and any plot from
    # the previous frame with z > 0 gets hidden, defeating fallback.
    if !isempty(foreground)
        m.zoom[] = maximum(t.z for t in foreground)
    end

    # Priority: the fetch channel is LIFO, so to download closest tiles first
    # we need to queue them last. Sort farthest-first.
    function dist_key(t::Tile)
        ext = MapTiles.extent(t, web_mercator)
        zmin, zmax, loose = tile_z_bounds(m.provider, t)
        return tile_distance(eyepos, ext.X[1], ext.X[2], ext.Y[1], ext.Y[2], zmin, zmax, loose)
    end
    foreground = OrderedSet{Tile}(sort!(collect(foreground); by=dist_key, rev=true))

    if length(foreground) > m.max_plots
        @warn "SSETiling3D selected $(length(foreground)) tiles (max_plots=$(m.max_plots)); raise sse_threshold or max_plots." maxlog=1
    end

    return (; foreground, background=OrderedSet{Tile}(), offscreen=OrderedSet{Tile}())
end


#########################################################################################
##### Helper functions

function get_resolution(map::Map)
    screen = Makie.getscreen(map.axis.scene)
    return isnothing(screen) ? size(map.axis.scene) .* 1.5 : size(screen)
end

# TODO this will be in Extents.jl soon, so remove
function grow_extent(area::Union{Rect,Extent}, factor)
    Extent(map(Extents.bounds(area)) do axis_bounds
        span = axis_bounds[2] - axis_bounds[1]
        pad = factor * span / 2
        return (axis_bounds[1] - pad, axis_bounds[2] + pad)
    end)
end

function optimal_zoom(m::Map, diagonal)
    diagonal_res = norm(get_resolution(m)) * m.scale
    # Go over complete known zoomrange of any provider.
    # So that we can get the theoretical optimal zoom level, even if the provider doesn't support it,
    # which we can then use to calculate the distance to the supported zoomlevel and may decide to not plot anything.
    # (TODO, how exactly can we get this over all providers?)
    zoomrange = 1:22
    z = optimal_zoom(m.crs, diagonal, diagonal_res, zoomrange, m.zoom[])
    actual_zoom = clamp(z, min_zoom(m), max_zoom(m))
    return z, actual_zoom, approx_tiles(m, actual_zoom, diagonal)
end
function optimal_zoom(crs, diagonal, diagonal_resolution, zoom_range, old_zoom)
    # TODO, this should come from provider
    tile_diag_res = norm((255, 255))
    target_ntiles = diagonal_resolution / tile_diag_res
    candidates_dict = Dict{Int,Float64}()
    candidates = @NamedTuple{z::Int, ntiles::Float64}[]
    for z in zoom_range
        ext = Extents.extent(Tile(0, 0, z), crs)
        mini, maxi = Point2.(ext.X, ext.Y)
        diag = norm(maxi .- mini)
        ntiles = diagonal / diag
        candidates_dict[z] = ntiles
        push!(candidates, (; z, ntiles))
    end
    if haskey(candidates_dict, old_zoom) # for the first invokation, old_zoom is 0, which is not a candidate
        old_ntiles = candidates_dict[old_zoom]
        # If the old zoom level is close to the target number of tiles, return it
        # to change the zoom level less often
        if old_ntiles > (target_ntiles - 1) && old_ntiles < (target_ntiles + 1)
            return old_zoom
        end
    end
    dist, idx = findmin(x -> abs(x.ntiles - target_ntiles), candidates)
    return candidates[idx].z
end

function approx_tiles(m::Map, zoom, diagonal)
    ext = Extents.extent(Tile(0, 0, zoom), m.crs)
    mini, maxi = Point2.(ext.X, ext.Y)
    diag = norm(maxi .- mini)
    ntiles_diag = diagonal / diag
    return (ntiles_diag / sqrt(2)) ^ 2
end
