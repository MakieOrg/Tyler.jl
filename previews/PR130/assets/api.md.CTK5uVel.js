import{_ as n,c as p,j as i,a,G as e,ai as l,B as h,o as k}from"./chunks/framework.UGNbPTLl.js";const T=JSON.parse('{"title":"","description":"","frontmatter":{},"headers":[],"relativePath":"api.md","filePath":"api.md","lastUpdated":null}'),r={name:"api.md"},o={class:"jldocstring custom-block",open:""},d={class:"jldocstring custom-block",open:""},E={class:"jldocstring custom-block",open:""},g={class:"jldocstring custom-block",open:""},y={class:"jldocstring custom-block",open:""},c={class:"jldocstring custom-block",open:""};function F(u,s,C,m,b,f){const t=h("Badge");return k(),p("div",null,[s[18]||(s[18]=i("h2",{id:"api",tabindex:"-1"},[a("API "),i("a",{class:"header-anchor",href:"#api","aria-label":'Permalink to "API"'},"​")],-1)),i("details",o,[i("summary",null,[s[0]||(s[0]=i("a",{id:"Tyler.ElevationProvider",href:"#Tyler.ElevationProvider"},[i("span",{class:"jlbinding"},"Tyler.ElevationProvider")],-1)),s[1]||(s[1]=a()),e(t,{type:"info",class:"jlObjectType jlType",text:"Type"})]),s[2]||(s[2]=l('<div class="language-julia vp-adaptive-theme"><button title="Copy Code" class="copy"></button><span class="lang">julia</span><pre class="shiki shiki-themes github-light github-dark vp-code" tabindex="0"><code><span class="line"><span style="--shiki-light:#005CC5;--shiki-dark:#79B8FF;">ElevationProvider</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8;">(color_provider</span><span style="--shiki-light:#D73A49;--shiki-dark:#F97583;">::</span><span style="--shiki-light:#005CC5;--shiki-dark:#79B8FF;">Union{Nothing, AbstractProvider}</span><span style="--shiki-light:#D73A49;--shiki-dark:#F97583;">=</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8;">TileProviders</span><span style="--shiki-light:#D73A49;--shiki-dark:#F97583;">.</span><span style="--shiki-light:#005CC5;--shiki-dark:#79B8FF;">Esri</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8;">(</span><span style="--shiki-light:#005CC5;--shiki-dark:#79B8FF;">:WorldImagery</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8;">); cache_size_gb</span><span style="--shiki-light:#D73A49;--shiki-dark:#F97583;">=</span><span style="--shiki-light:#005CC5;--shiki-dark:#79B8FF;">5</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8;">)</span></span></code></pre></div><p>Provider rendering elevation data from <a href="https://elevation3d.arcgis.com/arcgis/rest/services/WorldElevation3D/Terrain3D/ImageServer" target="_blank" rel="noreferrer">arcgis</a>. This provider is special, since it uses a second provider for color information, which also means you can provide a cache size, since color tile caching has to be managed by the provider. When set to <code>nothing</code>, no color provider is used and the elevation data is used to color the surface with a colormap directly. Use <code>Map(..., plot_config=Tyler.PlotConfig(colormap=colormap))</code> to set the colormap and other <code>surface</code> plot attributes.</p><p><a href="https://github.com/MakieOrg/Tyler.jl/blob/54976f91b121323f984b865345042e1190ca7310/src/provider/elevation/elevation-provider.jl#L1-L9" target="_blank" rel="noreferrer">source</a></p>',3))]),i("details",d,[i("summary",null,[s[3]||(s[3]=i("a",{id:"Tyler.GeoTilePointCloudProvider",href:"#Tyler.GeoTilePointCloudProvider"},[i("span",{class:"jlbinding"},"Tyler.GeoTilePointCloudProvider")],-1)),s[4]||(s[4]=a()),e(t,{type:"info",class:"jlObjectType jlType",text:"Type"})]),s[5]||(s[5]=l('<div class="language-julia vp-adaptive-theme"><button title="Copy Code" class="copy"></button><span class="lang">julia</span><pre class="shiki shiki-themes github-light github-dark vp-code" tabindex="0"><code><span class="line"><span style="--shiki-light:#005CC5;--shiki-dark:#79B8FF;">GeoTilePointCloudProvider</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8;">(subset</span><span style="--shiki-light:#D73A49;--shiki-dark:#F97583;">=</span><span style="--shiki-light:#032F62;--shiki-dark:#9ECBFF;">&quot;AHN1_T&quot;</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8;">)</span></span></code></pre></div><p>The PointCloud provider downloads from <a href="https://geotiles.citg.tudelft.nl" target="_blank" rel="noreferrer">geotiles.citg.tudelft</a>, which spans most of the netherlands. You can specify the subset to download from, which can be one of the following:</p><ul><li><p>AHN1_T (default): The most corse dataset, but also the fastest to download (1-5mb compressed per tile)</p></li><li><p>AHN2_T: More detailed dataset (~70mb per tile)</p></li><li><p>AHN3_T: ~250mb per tile</p></li><li><p>AHN4_T: 300-500mb showing much detail, takes a long time to load each tile (over 1 minute per tile). Use <code>max_plots=5</code> to limit the number of tiles loaded at once.</p></li></ul><p><a href="https://github.com/MakieOrg/Tyler.jl/blob/54976f91b121323f984b865345042e1190ca7310/src/provider/pointclouds/geotiles-pointcloud-provider.jl#L1-L10" target="_blank" rel="noreferrer">source</a></p>',4))]),i("details",E,[i("summary",null,[s[6]||(s[6]=i("a",{id:"Tyler.Interpolator",href:"#Tyler.Interpolator"},[i("span",{class:"jlbinding"},"Tyler.Interpolator")],-1)),s[7]||(s[7]=a()),e(t,{type:"info",class:"jlObjectType jlType",text:"Type"})]),s[8]||(s[8]=l(`<div class="language-julia vp-adaptive-theme"><button title="Copy Code" class="copy"></button><span class="lang">julia</span><pre class="shiki shiki-themes github-light github-dark vp-code" tabindex="0"><code><span class="line"><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8;">Interpolator </span><span style="--shiki-light:#D73A49;--shiki-dark:#F97583;">&lt;:</span><span style="--shiki-light:#005CC5;--shiki-dark:#79B8FF;"> AbstractProvider</span></span>
<span class="line"></span>
<span class="line"><span style="--shiki-light:#005CC5;--shiki-dark:#79B8FF;">Interpolator</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8;">(f; colormap</span><span style="--shiki-light:#D73A49;--shiki-dark:#F97583;">=</span><span style="--shiki-light:#005CC5;--shiki-dark:#79B8FF;">:thermal</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8;">, options</span><span style="--shiki-light:#D73A49;--shiki-dark:#F97583;">=</span><span style="--shiki-light:#005CC5;--shiki-dark:#79B8FF;">Dict</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8;">(</span><span style="--shiki-light:#005CC5;--shiki-dark:#79B8FF;">:minzoom</span><span style="--shiki-light:#D73A49;--shiki-dark:#F97583;">=</span><span style="--shiki-light:#005CC5;--shiki-dark:#79B8FF;">1</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8;">, </span><span style="--shiki-light:#005CC5;--shiki-dark:#79B8FF;">:maxzoom</span><span style="--shiki-light:#D73A49;--shiki-dark:#F97583;">=</span><span style="--shiki-light:#005CC5;--shiki-dark:#79B8FF;">19</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8;">))</span></span></code></pre></div><p>Provides tiles by interpolating them on the fly.</p><ul><li><p><code>f</code>: an Interpolations.jl interpolator or similar.</p></li><li><p><code>colormap</code>: A <code>Symbol</code> or <code>Vector{RGBA{Float32}}</code>. Default is <code>:thermal</code>.</p></li></ul><p><a href="https://github.com/MakieOrg/Tyler.jl/blob/54976f91b121323f984b865345042e1190ca7310/src/provider/interpolations.jl#L2-L11" target="_blank" rel="noreferrer">source</a></p>`,4))]),i("details",g,[i("summary",null,[s[9]||(s[9]=i("a",{id:"Tyler.Map",href:"#Tyler.Map"},[i("span",{class:"jlbinding"},"Tyler.Map")],-1)),s[10]||(s[10]=a()),e(t,{type:"info",class:"jlObjectType jlType",text:"Type"})]),s[11]||(s[11]=l(`<div class="language-julia vp-adaptive-theme"><button title="Copy Code" class="copy"></button><span class="lang">julia</span><pre class="shiki shiki-themes github-light github-dark vp-code" tabindex="0"><code><span class="line"><span style="--shiki-light:#005CC5;--shiki-dark:#79B8FF;">Map</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8;">(extent, [extent_crs</span><span style="--shiki-light:#D73A49;--shiki-dark:#F97583;">=</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8;">wgs84]; kw</span><span style="--shiki-light:#D73A49;--shiki-dark:#F97583;">...</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8;">)</span></span>
<span class="line"><span style="--shiki-light:#005CC5;--shiki-dark:#79B8FF;">Map</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8;">(map</span><span style="--shiki-light:#D73A49;--shiki-dark:#F97583;">::</span><span style="--shiki-light:#005CC5;--shiki-dark:#79B8FF;">Map</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8;">; </span><span style="--shiki-light:#D73A49;--shiki-dark:#F97583;">...</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8;">) </span><span style="--shiki-light:#6A737D;--shiki-dark:#6A737D;"># layering another provider on top of an existing map</span></span></code></pre></div><p>Tylers main object, it plots tiles onto a Makie.jl <code>Axis</code>, downloading and plotting more tiles as you zoom and pan. When layering providers over each other with <code>Map(map::Map; ...)</code>, you can use <code>toggle_visibility!(map)</code> to hide/unhide them.</p><p><strong>Arguments</strong></p><ul><li><p><code>extent</code>: the initial extent of the map, as a <code>GeometryBasics.Rect</code> or an <code>Extents.Extent</code> in the projection of <code>extent_crs</code>.</p></li><li><p><code>extent_crs</code>: Any <code>GeoFormatTypes</code> compatible crs, the default is wsg84.</p></li></ul><p><strong>Keywords</strong></p><ul><li><p><code>size</code>: The figure size.</p></li><li><p><code>figure</code>: an existing <code>Makie.Figure</code> object.</p></li><li><p><code>crs</code>: The providers coordinate reference system.</p></li><li><p><code>provider</code>: a TileProviders.jl <code>Provider</code>.</p></li><li><p><code>max_parallel_downloads</code>: limits the attempted simultaneous downloads, with a default of <code>16</code>.</p></li><li><p><code>cache_size_gb</code>: limits the cache for storing tiles, with a default of <code>5</code>.</p></li><li><p><code>fetching_scheme=Halo2DTiling()</code>: The tile fetching scheme. Can be SimpleTiling(), Halo2DTiling(), or Tiling3D().</p></li><li><p><code>scale</code>: a tile scaling factor. Low number decrease the downloads but reduce the resolution. The default is <code>0.5</code>.</p></li><li><p><code>plot_config</code>: A <code>PlotConfig</code> object to change the way tiles are plotted.</p></li><li><p><code>max_zoom</code>: The maximum zoom level to display, with a default of <code>TileProviders.max_zoom(provider)</code>.</p></li><li><p><code>max_plots=400:</code> The maximum number of plots to keep displayed at the same time.</p></li></ul><p><a href="https://github.com/MakieOrg/Tyler.jl/blob/54976f91b121323f984b865345042e1190ca7310/src/map.jl#L1-L29" target="_blank" rel="noreferrer">source</a></p>`,7))]),i("details",y,[i("summary",null,[s[12]||(s[12]=i("a",{id:"Tyler.Map-Tuple{Tyler.Map}",href:"#Tyler.Map-Tuple{Tyler.Map}"},[i("span",{class:"jlbinding"},"Tyler.Map")],-1)),s[13]||(s[13]=a()),e(t,{type:"info",class:"jlObjectType jlMethod",text:"Method"})]),s[14]||(s[14]=l(`<div class="language-julia vp-adaptive-theme"><button title="Copy Code" class="copy"></button><span class="lang">julia</span><pre class="shiki shiki-themes github-light github-dark vp-code" tabindex="0"><code><span class="line"><span style="--shiki-light:#005CC5;--shiki-dark:#79B8FF;">Map</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8;">(m</span><span style="--shiki-light:#D73A49;--shiki-dark:#F97583;">::</span><span style="--shiki-light:#005CC5;--shiki-dark:#79B8FF;">Map</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8;">; kw</span><span style="--shiki-light:#D73A49;--shiki-dark:#F97583;">...</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8;">)</span></span></code></pre></div><p>Layering constructor to show another provider on top of an existing map.</p><p><strong>Example</strong></p><div class="language-julia vp-adaptive-theme"><button title="Copy Code" class="copy"></button><span class="lang">julia</span><pre class="shiki shiki-themes github-light github-dark vp-code" tabindex="0"><code><span class="line"><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8;">lat, lon </span><span style="--shiki-light:#D73A49;--shiki-dark:#F97583;">=</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8;"> (</span><span style="--shiki-light:#005CC5;--shiki-dark:#79B8FF;">52.395593</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8;">, </span><span style="--shiki-light:#005CC5;--shiki-dark:#79B8FF;">4.884704</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8;">)</span></span>
<span class="line"><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8;">delta </span><span style="--shiki-light:#D73A49;--shiki-dark:#F97583;">=</span><span style="--shiki-light:#005CC5;--shiki-dark:#79B8FF;"> 0.01</span></span>
<span class="line"><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8;">ext </span><span style="--shiki-light:#D73A49;--shiki-dark:#F97583;">=</span><span style="--shiki-light:#005CC5;--shiki-dark:#79B8FF;"> Rect2f</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8;">(lon </span><span style="--shiki-light:#D73A49;--shiki-dark:#F97583;">-</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8;"> delta </span><span style="--shiki-light:#D73A49;--shiki-dark:#F97583;">/</span><span style="--shiki-light:#005CC5;--shiki-dark:#79B8FF;"> 2</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8;">, lat </span><span style="--shiki-light:#D73A49;--shiki-dark:#F97583;">-</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8;"> delta </span><span style="--shiki-light:#D73A49;--shiki-dark:#F97583;">/</span><span style="--shiki-light:#005CC5;--shiki-dark:#79B8FF;"> 2</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8;">, delta, delta)</span></span>
<span class="line"><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8;">m1 </span><span style="--shiki-light:#D73A49;--shiki-dark:#F97583;">=</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8;"> Tyler</span><span style="--shiki-light:#D73A49;--shiki-dark:#F97583;">.</span><span style="--shiki-light:#005CC5;--shiki-dark:#79B8FF;">Map</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8;">(ext)</span></span>
<span class="line"><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8;">m2 </span><span style="--shiki-light:#D73A49;--shiki-dark:#F97583;">=</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8;"> Tyler</span><span style="--shiki-light:#D73A49;--shiki-dark:#F97583;">.</span><span style="--shiki-light:#005CC5;--shiki-dark:#79B8FF;">Map</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8;">(m1; provider</span><span style="--shiki-light:#D73A49;--shiki-dark:#F97583;">=</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8;">TileProviders</span><span style="--shiki-light:#D73A49;--shiki-dark:#F97583;">.</span><span style="--shiki-light:#005CC5;--shiki-dark:#79B8FF;">Esri</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8;">(</span><span style="--shiki-light:#005CC5;--shiki-dark:#79B8FF;">:WorldImagery</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8;">), plot_config</span><span style="--shiki-light:#D73A49;--shiki-dark:#F97583;">=</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8;">Tyler</span><span style="--shiki-light:#D73A49;--shiki-dark:#F97583;">.</span><span style="--shiki-light:#005CC5;--shiki-dark:#79B8FF;">PlotConfig</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8;">(alpha</span><span style="--shiki-light:#D73A49;--shiki-dark:#F97583;">=</span><span style="--shiki-light:#005CC5;--shiki-dark:#79B8FF;">0.5</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8;">, postprocess</span><span style="--shiki-light:#D73A49;--shiki-dark:#F97583;">=</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8;">(p</span><span style="--shiki-light:#D73A49;--shiki-dark:#F97583;">-&gt;</span><span style="--shiki-light:#005CC5;--shiki-dark:#79B8FF;"> translate!</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8;">(p, </span><span style="--shiki-light:#005CC5;--shiki-dark:#79B8FF;">0</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8;">, </span><span style="--shiki-light:#005CC5;--shiki-dark:#79B8FF;">0</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8;">, </span><span style="--shiki-light:#005CC5;--shiki-dark:#79B8FF;">1f0</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8;">))))</span></span>
<span class="line"><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8;">m1</span></span></code></pre></div><p><a href="https://github.com/MakieOrg/Tyler.jl/blob/54976f91b121323f984b865345042e1190ca7310/src/map.jl#L54-L67" target="_blank" rel="noreferrer">source</a></p>`,5))]),i("details",c,[i("summary",null,[s[15]||(s[15]=i("a",{id:"Tyler.PlotConfig-Tuple{}",href:"#Tyler.PlotConfig-Tuple{}"},[i("span",{class:"jlbinding"},"Tyler.PlotConfig")],-1)),s[16]||(s[16]=a()),e(t,{type:"info",class:"jlObjectType jlMethod",text:"Method"})]),s[17]||(s[17]=l(`<div class="language-julia vp-adaptive-theme"><button title="Copy Code" class="copy"></button><span class="lang">julia</span><pre class="shiki shiki-themes github-light github-dark vp-code" tabindex="0"><code><span class="line"><span style="--shiki-light:#005CC5;--shiki-dark:#79B8FF;">PlotConfig</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8;">(; preprocess</span><span style="--shiki-light:#D73A49;--shiki-dark:#F97583;">=</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8;">identity, postprocess</span><span style="--shiki-light:#D73A49;--shiki-dark:#F97583;">=</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8;">identity, plot_attributes</span><span style="--shiki-light:#D73A49;--shiki-dark:#F97583;">...</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8;">)</span></span></code></pre></div><p>Creates a <code>PlotConfig</code> object to influence how tiles are being plotted.</p><ul><li><p>preprocess(tile_data): Function to preprocess the data before plotting. For a tile provider returning image data, preprocess will be called on the image data before plotting.</p></li><li><p>postprocess(tile_data): Function to mutate the plot object after creation. Can be used like this: <code>(plot)-&gt; translate!(plot, 0, 0, 1)</code>.</p></li><li><p>plot_attributes: Additional attributes to pass to the plot</p></li></ul><p><strong>Example</strong></p><div class="language-julia vp-adaptive-theme"><button title="Copy Code" class="copy"></button><span class="lang">julia</span><pre class="shiki shiki-themes github-light github-dark vp-code" tabindex="0"><code><span class="line"><span style="--shiki-light:#D73A49;--shiki-dark:#F97583;">using</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8;"> Tyler, GLMakie</span></span>
<span class="line"></span>
<span class="line"><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8;">config </span><span style="--shiki-light:#D73A49;--shiki-dark:#F97583;">=</span><span style="--shiki-light:#005CC5;--shiki-dark:#79B8FF;"> PlotConfig</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8;">(</span></span>
<span class="line"><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8;">    preprocess </span><span style="--shiki-light:#D73A49;--shiki-dark:#F97583;">=</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8;"> (data) </span><span style="--shiki-light:#D73A49;--shiki-dark:#F97583;">-&gt;</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8;"> data </span><span style="--shiki-light:#D73A49;--shiki-dark:#F97583;">.+</span><span style="--shiki-light:#005CC5;--shiki-dark:#79B8FF;"> 1</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8;">,</span></span>
<span class="line"><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8;">    postprocess </span><span style="--shiki-light:#D73A49;--shiki-dark:#F97583;">=</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8;"> (plot) </span><span style="--shiki-light:#D73A49;--shiki-dark:#F97583;">-&gt;</span><span style="--shiki-light:#005CC5;--shiki-dark:#79B8FF;"> translate!</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8;">(plot, </span><span style="--shiki-light:#005CC5;--shiki-dark:#79B8FF;">0</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8;">, </span><span style="--shiki-light:#005CC5;--shiki-dark:#79B8FF;">0</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8;">, </span><span style="--shiki-light:#005CC5;--shiki-dark:#79B8FF;">1</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8;">),</span></span>
<span class="line"><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8;">    color </span><span style="--shiki-light:#D73A49;--shiki-dark:#F97583;">=</span><span style="--shiki-light:#005CC5;--shiki-dark:#79B8FF;"> :red</span></span>
<span class="line"><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8;">)</span></span>
<span class="line"><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8;">lat, lon </span><span style="--shiki-light:#D73A49;--shiki-dark:#F97583;">=</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8;"> (</span><span style="--shiki-light:#005CC5;--shiki-dark:#79B8FF;">52.395593</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8;">, </span><span style="--shiki-light:#005CC5;--shiki-dark:#79B8FF;">4.884704</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8;">)</span></span>
<span class="line"><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8;">delta </span><span style="--shiki-light:#D73A49;--shiki-dark:#F97583;">=</span><span style="--shiki-light:#005CC5;--shiki-dark:#79B8FF;"> 0.1</span></span>
<span class="line"><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8;">extent </span><span style="--shiki-light:#D73A49;--shiki-dark:#F97583;">=</span><span style="--shiki-light:#005CC5;--shiki-dark:#79B8FF;"> Extent</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8;">(; X</span><span style="--shiki-light:#D73A49;--shiki-dark:#F97583;">=</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8;">(lon </span><span style="--shiki-light:#D73A49;--shiki-dark:#F97583;">-</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8;"> delta </span><span style="--shiki-light:#D73A49;--shiki-dark:#F97583;">/</span><span style="--shiki-light:#005CC5;--shiki-dark:#79B8FF;"> 2</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8;">, lon </span><span style="--shiki-light:#D73A49;--shiki-dark:#F97583;">+</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8;"> delta </span><span style="--shiki-light:#D73A49;--shiki-dark:#F97583;">/</span><span style="--shiki-light:#005CC5;--shiki-dark:#79B8FF;"> 2</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8;">), Y</span><span style="--shiki-light:#D73A49;--shiki-dark:#F97583;">=</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8;">(lat </span><span style="--shiki-light:#D73A49;--shiki-dark:#F97583;">-</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8;"> delta </span><span style="--shiki-light:#D73A49;--shiki-dark:#F97583;">/</span><span style="--shiki-light:#005CC5;--shiki-dark:#79B8FF;"> 2</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8;">, lat </span><span style="--shiki-light:#D73A49;--shiki-dark:#F97583;">+</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8;"> delta </span><span style="--shiki-light:#D73A49;--shiki-dark:#F97583;">/</span><span style="--shiki-light:#005CC5;--shiki-dark:#79B8FF;"> 2</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8;">))</span></span>
<span class="line"><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8;">Tyler</span><span style="--shiki-light:#D73A49;--shiki-dark:#F97583;">.</span><span style="--shiki-light:#005CC5;--shiki-dark:#79B8FF;">Map</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8;">(extent; provider</span><span style="--shiki-light:#D73A49;--shiki-dark:#F97583;">=</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8;">Tyler</span><span style="--shiki-light:#D73A49;--shiki-dark:#F97583;">.</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8;">TileProviders</span><span style="--shiki-light:#D73A49;--shiki-dark:#F97583;">.</span><span style="--shiki-light:#005CC5;--shiki-dark:#79B8FF;">Esri</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8;">(</span><span style="--shiki-light:#005CC5;--shiki-dark:#79B8FF;">:WorldImagery</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8;">), plot_config</span><span style="--shiki-light:#D73A49;--shiki-dark:#F97583;">=</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8;">config)</span></span></code></pre></div><p><a href="https://github.com/MakieOrg/Tyler.jl/blob/54976f91b121323f984b865345042e1190ca7310/src/tile-plotting.jl#L26-L49" target="_blank" rel="noreferrer">source</a></p>`,6))])])}const A=n(r,[["render",F]]);export{T as __pageData,A as default};
