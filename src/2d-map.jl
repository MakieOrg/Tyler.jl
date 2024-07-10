"""
    Map

    Map(extent, [extent_crs=wgs84]; kw...)

Tylers main object, it plots tiles onto a Makie.jl `Axis`,
downloading and plotting more tiles as you zoom and pan.

# Arguments

-`extent`: the initial extent of the map, as a `GeometryBasics.Rect`
    or an `Extents.Extent` in the projection of `extent_crs`.
-`extent_crs`: Any `GeoFormatTypes` compatible crs, the default is wsg84.

# Keywords

-`resolution`: The figure resolution.
-`figure`: an existing `Makie.Figure` object.
-`crs`: The providers coordinate reference system.
-`provider`: a TileProviders.jl `Provider`.
-`max_parallel_downloads`: limits the attempted simultaneous downloads, with a default of `16`.
-`cache_size_gb`: limits the cache for storing tiles, with a default of `5`.
-`depth`: the number of layers to load when zooming. Lower numbers will be slightly faster
    but have more artefacts. The default is `8`.
-`halo`: The fraction of the width of tiles to add as a halo so that panning is smooth - the
    tiles will already be loaded. The default is `0.2`, which means `0.1` on each side.
-`scale`: a tile scaling factor. Low number decrease the downloads but reduce the resolution.
    The default is `1.0`.
"""
struct Map <: AbstractMap
    provider::AbstractProvider
    figure::Figure
    axis::Axis

    tiles::TileCache
    displayed_tiles::OrderedSet{Tile}
    free_tiles::Vector{Makie.Plot}
    plots::Dict{Tile,Makie.Plot}
    display_task::Base.RefValue{Task}

    crs::CoordinateReferenceSystemFormat
    zoom::Observable{Int}
    depth::Int
    halo::Float64
    scale::Float64
    max_zoom::Int
end

function create_tile_plot!(map::Map, tile::Tile, image::TileImage)
    if haskey(map.plots, tile)
        # this shouldn't get called with plots that are already displayed
        @debug "getting tile plot already plotted"
        return map.plots[tile]
    end
    if isempty(map.free_tiles)
        mplot = create_tileplot!(map.axis, image)
    else
        mplot = pop!(map.free_tiles)
        mplot.color[] = image
        mplot.visible = true
    end
    map.plots[tile] = mplot
    place_tile!(tile, mplot, map.crs)
end

# Wait for all tiles to be loaded
function Base.wait(map::Map)
    # The download + plot loops need a screen to do their work!
    if isnothing(Makie.getscreen(map.figure.scene))
        display(map.figure)
    end
    screen = Makie.getscreen(map.figure.scene)
    isnothing(screen) && error("No screen after display. Wrong backend? Only WGLMakie and GLMakie are supported.")
    wait(map.tiles)
end

function Map(extent, extent_crs=wgs84;
        resolution=(1000, 1000),
        figure=Makie.Figure(; size=resolution),
        axis=Makie.Axis(figure[1, 1]; aspect=Makie.DataAspect()),
        provider=TileProviders.OpenStreetMap(:Mapnik),
        crs=MapTiles.web_mercator,
        cache_size_gb=5,
        depth=8,
        halo=0.2,
        scale=2.0,
        max_zoom=TileProviders.max_zoom(provider)
    )

    # Extent
    # if extent input is a HyperRectangle then convert to type Extent
    extent isa Extent || (extent = Extents.extent(extent))
    ext_target = MapTiles.project_extent(extent, extent_crs, crs)
    X = ext_target.X
    Y = ext_target.Y
    axis.autolimitaspect = 1
    Makie.limits!(axis, (X[1], X[2]), (Y[1], Y[2]))

    tiles = TileCache{TileImage}(provider; cache_size_gb=cache_size_gb)
    downloaded_tiles = tiles.downloaded_tiles

    plots = Dict{Tile,Any}()
    displayed_tiles = OrderedSet{Tile}()
    free_tiles = Makie.Plot[]
    display_task = Base.RefValue{Task}()

    map = Map(
        provider,

        figure,
        axis,
        tiles,
        displayed_tiles,
        free_tiles,
        plots,
        display_task,

        crs,
        Observable(1),
        depth, halo, scale, max_zoom
    )

    map.zoom[] = get_zoom(map, extent)


    display_task[] = @async for (tile, img) in downloaded_tiles
        while isnothing(Makie.getscreen(map.axis.scene))
            sleep(0.01)
        end
        screen = Makie.getscreen(map.axis.scene)
        while !isopen(screen)
            sleep(0.01)
        end
        try
            create_tile_plot!(map, tile, img)
            # fixes on demand renderloop which doesn't pick up all updates!
            if hasproperty(screen, :requires_update)
                screen.requires_update = true
            end
        catch e
            @warn "error while creating tile" exception = (e, Base.catch_backtrace())
        end
    end

    # Queue tiles to be downloaded & displayed
    update_tiles!(map, ext_target)

    on(axis.scene, axis.finallimits) do extent
        stopped_displaying(figure) && return
        update_tiles!(map, extent)
        return
    end
    return map
end



function update_tiles!(m::Map, area::Union{Rect,Extent})
    area = typeof(area) <: Rect ? Extents.extent(area) : area
    # `depth` determines the number of layers below the current
    # layer to load. Tiles are downloaded in order from lowest to highest zoom.
    depth = m.depth

    # Calculate the zoom level
    zoom = get_zoom(m, area)
    m.zoom[] = zoom

    # And the z layers we will plot
    layer_range = max(min_zoom(m), zoom - depth):zoom
    # Get the tiles around the mouse first
    xpos, ypos = Makie.mouseposition(m.axis.scene)
    xspan = (area.X[2] - area.X[1]) * 0.01
    yspan = (area.Y[2] - area.Y[1]) * 0.01
    mouse_area = Extents.Extent(X=(xpos - xspan, xpos + xspan), Y=(ypos - yspan, ypos + yspan))
    # Make a halo around the mouse tile to load next, intersecting area so we don't download outside the plot
    mouse_halo_area = grow_extent(mouse_area, 10)
    # Define a halo around the area to download last, so pan/zoom are filled already
    halo_area = grow_extent(area, m.halo) # We don't mind that the middle tiles are the same, the OrderedSet will remove them
    # Define all the tiles in the order they will load in
    areas = if Extents.intersects(mouse_halo_area, area)
        mha = Extents.intersection(mouse_halo_area, area)
        if Extents.intersects(mouse_area, area)
            [Extents.intersection(mouse_area, area), mha, area, halo_area]
        else
            [mha, area, halo_area]
        end
    else
        [area, halo_area]
    end

    area_layers = Iterators.flatten(map(layer_range) do z
        return Iterators.flatten(map(areas) do ext
            return MapTiles.TileGrid(ext, z, m.crs)
        end)
    end)

    # Create the full set of tiles
    # Using an ordered set gives a smoother load than a Set
    new_tiles_set = OrderedSet{Tile}(area_layers)
    # Remove any tiles not in the new set
    remove_tiles!(m, new_tiles_set)

    to_add = setdiff(new_tiles_set, m.displayed_tiles)

    # replace
    empty!(m.displayed_tiles)
    union!(m.displayed_tiles, new_tiles_set)

    # Queue tiles to be downloaded & displayed
    foreach(tile -> put!(m.tiles.tile_queue, tile), to_add)
end

GeoInterface.crs(map::Map) = map.crs
Extents.extent(map::Map) = Extents.extent(map.axis.finallimits[])

TileProviders.max_zoom(map::Map) = map.max_zoom
TileProviders.min_zoom(map::Map) = Int(min_zoom(map.provider))

function get_zoom(map::Map, area)
    res = size(map.axis.scene) .* map.scale
    return clamp(z_index(area, (X=res[2], Y=res[1]), map.crs), min_zoom(map), max_zoom(map))
end
