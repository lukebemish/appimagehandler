using Pkg

Pkg.activate("build")

using PackageCompiler

if isdir("build/out")
    rm("build/out";recursive=true)
end
create_app(".","build/out";executables=["appimagehandler"=>"main_cli"])