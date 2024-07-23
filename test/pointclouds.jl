using Tyler, GLMakie, TileProviders, Colors, Extents, MapTiles, Downloads

struct ElevationProvider <: AbstractProvider
    options::Dict
end

function TileProviders.geturl(::ElevationProvider, x::Integer, y::Integer, z::Integer)
    return "https://s3.amazonaws.com/elevation-tiles-prod/geotiff/$(z)/$(x)/$(y).tif"
end

world_image = TileProviders.Esri(:WorldImagery)
@time Downloads.download("https://s3.amazonaws.com/elevation-tiles-prod/geotiff/0/0/0.tif")
provider = ElevationProvider(Dict())
Tyler.fetch_tile(provider, Tyler.Tile(0, 0, 0))

download_cache = Dict{String,Any}()

function fetch_lazy_tile(provider, tile::Tyler.Tile)
    url = TileProviders.geturl(provider, tile.x, tile.y, tile.z)
    return get!(download_cache, url) do
        io = IOBuffer()
        Downloads.download(url, io)
        return rotr90(Tyler.ImageMagick.readblob(take!(io)))
    end
end

function Tyler.fetch_tile(provider::ElevationProvider, tile::Tyler.Tile)
    println("Fetching tile")
    elevation_img = Float32.(fetch_lazy_tile(provider, tile))
    foto_img = fetch_lazy_tile(world_image, tile)
    println("Fetched tile")
    elevation = map(elevation_img) do x
        (x > 0.9 ? x - 1 : x) .* -500
    end
    return (elevation, (foto_img))
end

begin
    # point location to add to map
    lat = 34.2013
    lon = -118.1714
    delta = 1
    extent = Extent(X=(lon - delta / 2, lon + delta / 2), Y=(lat - delta / 2, lat + delta / 2))
    m = Tyler.Map(extent, provider=ElevationProvider(Dict()))
    display(m.figure)
    extent isa Extent || (extent = Extents.extent(extent))
    extent_crs = Tyler.wgs84
    crs = MapTiles.web_mercator
    ext_target = MapTiles.project_extent(extent, extent_crs, crs)
    X = ext_target.X
    Y = ext_target.Y
    wait(m)
    m.axis.scene.theme.limits[] = data_limits(m.axis.scene.plots)
    center!(m.axis.scene)
    nothing
end


using PointClouds


m = Tyler.Map3D(extent)
display(m.figure.scene)

function get_tiles(extent)
    tiles = Set{PointClouds.DataSources.PointCloudTile}()
    for (x, y) in zip(LinRange(extent.X..., 10), LinRange(extent.Y..., 10))
        @show x y
        union!(tiles, PointClouds.gettiles(y,x))
    end
    return tiles
end



tiles = get_tiles(extent)
m.axis.scene.camera_controls.near[] = 0.1f0
m.axis.scene.camera_controls.far[] = 100000f0
m = Tyler.Map3D(extent)
display(m.figure.scene)
for tile in tiles
    @time try
        pc = LAS(tile)
        pcc = PointCloud(pc; crs="EPSG:3857", attributes=(i=intensity,))
        points = Point3f.(pcc.x, pcc.y, pcc.z)
        scatter!(m.axis, points, color=Float32.(log10.(pcc.i)), colormap=:inferno, marker=Makie.FastPixel(), markerspace=:data, markersize=1f0)
    catch e
        @show e
    end
end
