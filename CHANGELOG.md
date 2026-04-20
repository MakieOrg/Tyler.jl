# v0.2.1

- Allow creating `Map`s on `GeoAxis` (from GeoMakie) via a package extension [#114](https://github.com/MakieOrg/Tyler.jl/pull/114).
  - This works if you pass the GeoAxis to the `axis` keyword, or a NamedTuple with the keyword `type = GeoAxis` (see the next entry for more details on this).
  - Halo2D and SimpleTiling schemes are supported.
  - PlotConfig and DebugPlotConfig plotting configs are supported.
- Allow passing axis parameters as a NamedTuple (`axis = (; type = ..., aspect = ...)`, as in standard Makie plotting syntax) [#118](https://github.com/MakieOrg/Tyler.jl/pull/118)
- Improve loading order in Halo2DTiling and load intermediate zoom levels to improve the waiting experience [#119](https://github.com/MakieOrg/Tyler.jl/pull/119)
