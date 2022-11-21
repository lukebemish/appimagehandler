using Pkg
using TOML

Pkg.activate("build")

using PackageCompiler

function interpolate(s::AbstractString, d::Dict)
    for (k, v) in d
        s = replace(s, "\${$k}" => v)
    end
    return s
end

function makeapp(arch)
    if isdir("build/out")
        rm("build/out";recursive=true)
    end
    mkpath("build/out")

    project = TOML.parse(read("Project.toml", String))

    version = project["version"]
    
    println("Building for $arch")

    create_app(".","build/out/usr";executables=["appimagehandler"=>"main_cli"], cpu_target=arch)

    originalDir = pwd()

    cd("build/out")
    symlink("usr/bin/appimagehandler","AppRun")
    iconpath = "usr/share/icons/hicolor/scalable/apps/appimagehandler.svg"
    mkpath(abspath(joinpath(iconpath,"../")))
    touch(iconpath)
    symlink(iconpath, "appimagehandler.svg")
    for file in readdir("../template")
        cp(joinpath("../template",file),joinpath("./",file))
    end

    # process desktop file
    replacements = Dict("version"=>version,"arch"=>arch)
    desktop = read("appimagehandler.desktop",String)
    desktop = interpolate(desktop,replacements)
    write("appimagehandler.desktop",desktop)

    cd(originalDir)

    if !isdir("build/artifacts")
        mkpath("build/artifacts")
    end
    cd("build/artifacts")

    run(`appimagetool ../out/ appimagehandler.AppImage`)

    cd(originalDir)
end

makeapp("x86_64")