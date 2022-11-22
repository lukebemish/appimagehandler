using Pkg

Pkg.activate("build")

using PackageCompiler
using TOML
using ArgParse

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

    # grab license
    cp("../../LICENSE.md","./LICENSE.md")

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

    if isfile("appimagehandler_$arch.AppImage")
        rm("appimagehandler_$arch.AppImage")
    end
    if isfile("appimagehandler_$arch.AppImage.zsync")
        rm("appimagehandler_$arch.AppImage.zsync")
    end

    run(`appimagetool ../out/ appimagehandler_$arch.AppImage -u "gh-releases-zsync|lukebemish|appimagehandler|latest|appimagehandler_$arch.AppImage.zsync"`)

    run(`zsyncmake -C appimagehandler_$arch.AppImage -u appimagehandler_$arch.AppImage`)

    cd(originalDir)
end

s = ArgParseSettings()

@add_arg_table s begin
    "--arch"
        help = "The architecture to build for; if not specified, all architectures will be built"
        required = false
end

args = parse_args(ARGS, s; as_symbols=true)

if args[:arch] === nothing
    makeapp("x86_64")
    makeapp("i386")
else
    makeapp(args.arch)
end