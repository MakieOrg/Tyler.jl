using Documenter, DocumenterVitepress
using Tyler
using Logging

makedocs(;
    sitename="Tyler",
    modules=[Tyler],
    clean=true,
    doctest=true,
    authors="Simon Danisch et al.",
    checkdocs=:all,
    format=DocumenterVitepress.MarkdownVitepress(
        repo = "github.com/MakieOrg/Tyler.jl", # this must be the full URL!
        devbranch="master",
        devurl="dev";
    ),
    pages = [
        "Home" => "index.md",
        "Getting Started" => "getting_started.md",
        "Examples" => [
            "Points, Poly & Text" => "examples/points_poly_text.md",
            "OpenStreetMap data" => "examples/osmmakie.md",
            "Whale shark trajectory" => "examples/whale_shark.md",
            "Ice loss animation" => "examples/iceloss_ex.md",
            "Interpolation on the fly" => "examples/interpolation.md",
            "Map3D" => "examples/map-3d.md",
            "PlotConfig" => "examples/plotconfig.md",
        ],
        "API" => "api.md",
    ],
    draft=false,
    source="src",
    build="build",
    warnonly=true,
)

DocumenterVitepress.deploydocs(;
    repo="github.com/MakieOrg/Tyler.jl.git",
    target="build", # this is where Vitepress stores its output
    branch = "gh-pages",
    devbranch="master",
    push_preview = true
)
