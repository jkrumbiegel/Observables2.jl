using Documenter, Observables2

makedocs(;
    modules=[Observables2],
    format=Documenter.HTML(),
    pages=[
        "Home" => "index.md",
    ],
    repo="https://github.com/jkrumbiegel/Observables2.jl/blob/{commit}{path}#L{line}",
    sitename="Observables2.jl",
    authors="Julius Krumbiegel",
    assets=String[],
)

deploydocs(;
    repo="github.com/jkrumbiegel/Observables2.jl",
)
