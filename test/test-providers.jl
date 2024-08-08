using GeometryBasics, GLMakie, Tyler, TileProviders
using Tyler: ElevationProvider, GeoTilePointCloudProvider
using MapTiles
using MeshIO, FileIO
# https://api.3dbag.nl/api.html
# https://docs.3dbag.nl/en/delivery/webservices/
amsti = load("amsterdam/amsterdam.obj")
tex = load("amsterdam/texture.png")
f, ax, pl = mesh(amsti; color=:gray)
boundingbox(pl)


lat, lon = (52.395593, 4.884704)
delta = 0.01
ext = Rect2f(lon - delta / 2, lat - delta / 2, delta, delta)
extrema(ext)
begin
    lat, lon = (52.395593, 4.884704)
    delta = 0.01
    ext = Rect2f(lon-delta/2, lat-delta/2, delta, delta)
    m1 = Tyler.Map(ext; max_parallel_downloads=3)
end

begin
    lat, lon = (52.395593, 4.884704)
    delta = 0.01
    ext = Rect2f(lon - delta / 2, lat - delta / 2, delta, delta)
    m1 = Tyler.Map(ext; max_parallel_downloads=1)
    display(m1.figure.scene)
end

begin
    # lat, lon = (40.697211, -74.037523)
    # lat, lon = (52.377428, 4.898387)
    # lat, lon = (53.208252, 5.169539)
    # lat, lon = (55.648466, 12.566546)
    lat, lon = (47.087441, 13.377214)
    delta = 0.3
    ext = Rect2f(lon-delta/2, lat-delta/2, delta, delta)
    m = Tyler.Map3D(ext; provider=ElevationProvider())
end

begin
    lat, lon = (47.087441, 13.377214)
    delta = 0.3
    ext = Rect2f(lon - delta / 2, lat - delta / 2, delta, delta)
    cfg = Tyler.PlotConfig(preprocess=pc -> map(p -> p .* 2, pc), shading=FastShading, material=mat, colormap=:alpine)
    m = Tyler.Map3D(ext; provider=ElevationProvider(nothing), plot_config=cfg)
end

for i in 1:1000
    rotate_cam!(m.axis.scene, 0, 0.01, 0)
    sleep(1/60)
end

begin
    lat, lon = (52.40459835, 4.84763329)
    delta = 0.006
    ext = Rect2f(lon - delta / 2, lat - delta / 2, delta, delta)
    subset="AHN1_T" # Takes reasonably long to load (~1-5mb compressed per tile)
    # subset="AHN4_T" # Takes _really_ long to load, even from disk (~300mb compressed points per tile)
    provider = GeoTilePointCloudProvider(subset=subset)
    image = ElevationProvider(nothing)
    cfg = Tyler.MeshScatterPlotconfig(markersize=5, marker=Rect3f(Vec3f(0), Vec3f(1)))
    m1 = Tyler.Map3D(ext; provider=provider, plot_config=cfg)
    cfg = Tyler.PlotConfig(preprocess=pc -> map(p -> p .* 2, pc), shading=FastShading, colormap=:alpine)
    m2 = Tyler.Map3D(m1; provider=image, plot_config=cfg)
    m1
end


begin
    lat, lon = (52.395593, 4.884704)
    delta = 0.02
    ext = Rect2f(lon - delta / 2, lat - delta / 2, delta, delta)
    subset = "AHN1_T" # Takes reasonably long to load (~1-5mb compressed per tile)
    # subset = "AHN4_T" # Takes _really_ long to load, even from disk (~300mb compressed points per tile)
    provider = GeoTilePointCloudProvider(subset=subset)
    m1 = Tyler.Map3D(ext; provider=provider)
    m2 = Tyler.Map3D(ext; provider=ElevationProvider(), max_plots=20, figure=m1.figure, axis=m1.axis)
    m1
end

unique_plots = unique(Tyler.tile_key.((m1.provider,), keys(m1.current_tiles)))
length(unique_plots) == length(m1.plots)

using RPRMakie, FileIO

function plastic_material()
    return (type=:Uber, reflection_color=Vec4f(1),
        reflection_weight=Vec4f(1), reflection_roughness=Vec4f(0.1),
        reflection_anisotropy=Vec4f(0), reflection_anisotropy_rotation=Vec4f(0),
        reflection_metalness=Vec4f(0), reflection_ior=Vec4f(1.4), refraction_weight=Vec4f(0),
        coating_weight=Vec4f(0), sheen_weight=Vec4f(0), emission_weight=Vec3f(0),
        transparency=Vec4f(0), reflection_mode=UInt(RPR.RPR_UBER_MATERIAL_IOR_MODE_PBR),
        emission_mode=UInt(RPR.RPR_UBER_MATERIAL_EMISSION_MODE_SINGLESIDED),
        coating_mode=UInt(RPR.RPR_UBER_MATERIAL_IOR_MODE_PBR), sss_multiscatter=true,
        refraction_thin_surface=true)
end
begin
    lat, lon = (52.40459835, 4.84763329)
    delta = 0.005
    ext = Rect2f(lon - delta / 2, lat - delta / 2, delta, delta)
    provider = GeoTilePointCloudProvider()
    mat = plastic_material()
    cfg = Tyler.MeshScatterPlotconfig(material=mat)
    m = Tyler.Map3D(ext; figure=f, axis=ax, provider=provider, max_plots=3, plot_config=cfg)
end


using RPRMakie, FileIO
function render_rpr(m, name, radiance=1000000)
    wait(m)
    ax = m.axis
    cam = ax.scene.camera_controls
    lightpos = Vec3f(cam.lookat[][1], cam.lookat[][2], cam.eyeposition[][3])
    lights = [
        EnvironmentLight(1.5, load(RPR.assetpath("studio026.exr"))),
        PointLight(lightpos, RGBf(radiance, radiance * 0.9, radiance * 0.9))
    ]
    empty!(ax.scene.lights)
    append!(ax.scene.lights, lights)
    save("$(name).png", ax.scene; plugin=RPR.Northstar, backend=RPRMakie, iterations=2000)
end

function plastic_material()
    return (type=:Uber, reflection_color=Vec4f(1),
        reflection_weight=Vec4f(1), reflection_roughness=Vec4f(0.1),
        reflection_anisotropy=Vec4f(0), reflection_anisotropy_rotation=Vec4f(0),
        reflection_metalness=Vec4f(0), reflection_ior=Vec4f(1.4), refraction_weight=Vec4f(0),
        coating_weight=Vec4f(0), sheen_weight=Vec4f(0), emission_weight=Vec3f(0),
        transparency=Vec4f(0), reflection_mode=UInt(RPR.RPR_UBER_MATERIAL_IOR_MODE_PBR),
        emission_mode=UInt(RPR.RPR_UBER_MATERIAL_EMISSION_MODE_SINGLESIDED),
        coating_mode=UInt(RPR.RPR_UBER_MATERIAL_IOR_MODE_PBR), sss_multiscatter=true,
        refraction_thin_surface=true)
end

begin
    lat, lon = (47.087441, 13.377214)
    delta = 0.5
    ext = Rect2f(lon - delta / 2, lat - delta / 2, delta, delta)
    mat = (type=:Uber, roughness=0.2, ior=1.390)
    cfg = Tyler.PlotConfig(preprocess=pc -> map(p -> p .* 2, pc), shading=FastShading, material=plastic, colormap=:alpine)
    m = Tyler.Map3D(ext; provider=ElevationProvider(nothing), plot_config=cfg, max_plots=5)
    render_rpr(m, "alpine", 10000000)
end

begin
    lat, lon = (52.40459835229174, 4.84763329882317)
    delta = 0.005
    ext = Rect2f(lon - delta / 2, lat - delta / 2, delta, delta)
    subset = "AHN1_T" # Takes reasonably long to load (~1-5mb compressed per tile)
    # subset = "AHN4_T" # Takes _really_ long to load, even from disk (~300mb compressed points per tile)
    provider = GeoTilePointCloudProvider(subset=subset)
    mat = plastic_material()
    cfg = Tyler.MeshScatterPlotconfig(markersize=5, material=mat)
    m = Tyler.Map3D(ext; provider=provider, plot_config=cfg, max_plots=3, size=(2000, 2000))
    cfg = Tyler.PlotConfig(preprocess=pc -> map(p -> p .* 2, pc), shading=FastShading, material=mat, colormap=:Blues)
    m2 = Tyler.Map3D(m; provider=ElevationProvider(nothing), plot_config=cfg, max_plots=5)
    wait(m)
    render_rpr(m, "pointclouds")
end
