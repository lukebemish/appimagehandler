using Pkg

Pkg.activate(".")

include("src/appimagehandler.jl")

appimagehandler.main_cli()