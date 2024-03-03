using Documenter, DocumenterVitepress
using Tyler

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
    draft=false,
    source="src", 
    build="build", 
    warnonly=true,
)

deploydocs(;
    repo="github.com/MakieOrg/Tyler.jl.git",
    target="build", # this is where Vitepress stores its output
    branch = "gh-pages",
    devbranch="master",
    push_preview = true
)