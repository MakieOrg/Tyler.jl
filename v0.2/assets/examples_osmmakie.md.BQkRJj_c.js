import{_ as s,c as n,o as p,aA as e}from"./chunks/framework.Di3Qz2Vh.js";const _=JSON.parse('{"title":"","description":"","frontmatter":{},"headers":[],"relativePath":"examples/osmmakie.md","filePath":"examples/osmmakie.md","lastUpdated":null}'),l={name:"examples/osmmakie.md"};function i(o,a,t,r,c,d){return p(),n("div",null,[...a[0]||(a[0]=[e(`<h2 id="OpenStreetMap-data-OSM" tabindex="-1">OpenStreetMap data (OSM) <a class="header-anchor" href="#OpenStreetMap-data-OSM" aria-label="Permalink to &quot;OpenStreetMap data (OSM) {#OpenStreetMap-data-OSM}&quot;">​</a></h2><p>In this example, we combine OpenStreetMap data, loading some roads and buildings and plotting them on top of a Tyler map.</p><div class="language-@example vp-adaptive-theme"><button title="Copy Code" class="copy"></button><span class="lang">@example</span><pre class="shiki shiki-themes github-light github-dark vp-code" tabindex="0"><code><span class="line"><span>using Tyler, Tyler.TileProviders</span></span>
<span class="line"><span>using GLMakie, OSMMakie, LightOSM</span></span>
<span class="line"><span></span></span>
<span class="line"><span>area = (</span></span>
<span class="line"><span>    minlat = 51.50, minlon = -0.0921, # bottom left corner</span></span>
<span class="line"><span>    maxlat = 51.52, maxlon = -0.0662 # top right corner</span></span>
<span class="line"><span>)</span></span>
<span class="line"><span></span></span>
<span class="line"><span>download_osm_network(:bbox; # rectangular area</span></span>
<span class="line"><span>    area..., # splat previously defined area boundaries</span></span>
<span class="line"><span>    network_type=:drive, # download motorways</span></span>
<span class="line"><span>    save_to_file_location=&quot;london_drive.json&quot;</span></span>
<span class="line"><span>);</span></span>
<span class="line"><span></span></span>
<span class="line"><span>osm = graph_from_file(&quot;london_drive.json&quot;;</span></span>
<span class="line"><span>    graph_type=:light, # SimpleDiGraph</span></span>
<span class="line"><span>    weight_type=:distance</span></span>
<span class="line"><span>)</span></span>
<span class="line"><span></span></span>
<span class="line"><span>download_osm_buildings(:bbox;</span></span>
<span class="line"><span>    area...,</span></span>
<span class="line"><span>    metadata=true,</span></span>
<span class="line"><span>    download_format=:osm,</span></span>
<span class="line"><span>    save_to_file_location=&quot;london_buildings.osm&quot;</span></span>
<span class="line"><span>);</span></span>
<span class="line"><span></span></span>
<span class="line"><span># load as Buildings Dict</span></span>
<span class="line"><span>buildings = buildings_from_file(&quot;london_buildings.osm&quot;);</span></span>
<span class="line"><span># Google + OSM</span></span>
<span class="line"><span>provider = TileProviders.Google(:satelite)</span></span>
<span class="line"><span>london = Rect2f(-0.0921, 51.5, 0.04, 0.025)</span></span>
<span class="line"><span>m = Tyler.Map(london; provider=provider, crs=Tyler.wgs84)</span></span>
<span class="line"><span>m.axis.aspect = map_aspect(area.minlat, area.maxlat)</span></span>
<span class="line"><span>p = osmplot!(m.axis, osm; buildings)</span></span>
<span class="line"><span># DataInspector(m.axis) # this is broken/slow</span></span>
<span class="line"><span>m</span></span></code></pre></div>`,3)])])}const u=s(l,[["render",i]]);export{_ as __pageData,u as default};
