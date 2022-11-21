module appimagehandler

using ArgParse
using TOML

function xdgdatahome()
    xdgDataHome = joinpath(homedir(),".local/share/")
    if haskey(Main.ENV, "XDG_DATA_HOME")
        xdgDataHome = Main.ENV["XDG_DATA_HOME"]
    end
    return xdgDataHome
end

function makeDesktopTemplate(name, comment, filepath, iconpath; terminal=false)
    return """
[Desktop Entry]
Name=$name
Exec=$filepath
Terminal=$terminal
Type=Application
Icon=$iconpath
Comment=$comment"""
end

function disable(args;purge=false)
    store = joinpath(pwd(),args[:store])

    file = joinpath(store, args[:appimage]*".AppImage")
    newfile = joinpath(store, args[:appimage]*".AppImage.disabled")

    if purge
        if isfile(file)
            rm(file)
        end
        if isfile(newfile)
            rm(newfile)
        end
    end

    desktopfile = joinpath(xdgdatahome(), "applications","appimage-"*args[:appimage]*".desktop")
    icon = joinpath(store, "icons", args[:appimage])

    if isfile(icon*".png")
        rm(icon*".png")
    elseif isfile(icon*".svg")
        rm(icon*".svg")
    elseif isfile(icon*".xpm")
        rm(icon*".xpm")
    end

    if isfile(desktopfile)
        rm(desktopfile)
    end

    if isfile(file)
        mv(file, newfile)
    end

    if purge
        println("Purged AppImage $(args[:appimage]) in $store.")
    else
        println("Disabled AppImage $(args[:appimage]) in $store.")
    end
end

function enable(args)
    store = joinpath(pwd(),args[:store])

    newfile = joinpath(store, args[:appimage]*".AppImage")
    file = joinpath(store, args[:appimage]*".AppImage.disabled")

    if isfile(file)
        mv(file, newfile)
    end

    integrate(merge(args,Dict(:appimage=>newfile)))
end

function readDesktopSection(lines, name)
    vals = [replace(i,"$name="=>"") for i in filter(x->startswith(x,"$name="),lines)]
    if length(vals) > 0
        return vals[1]
    else
        return nothing
    end
end

struct CacheData
    version::String
end

function getCache(store, partial)
    cacheDir = joinpath(store, "cache")
    if !isdir(cacheDir)
        mkpath(cacheDir)
    end

    cacheFile = joinpath(cacheDir, partial*".cache")
    
    text = read(cacheFile, String)

    err = TOML.tryparse(text)

    if err <: TOML.ParserError
        return nothing
    else
        return CacheData(err["version"])
    end
end

function writeCache(store, partial, cache)
    cacheDir = joinpath(store, "cache")
    if !isdir(cacheDir)
        mkpath(cacheDir)
    end

    cacheFile = joinpath(cacheDir, partial*".cache")
    open(cacheFile, "w") do f
        TOML.print(f, Dict("version"=>cache.version))
    end
end

function displayCache(store, partial, cache)
    println("AppImage $(partial):")
    println("Version: $(cache.version)")
end

function removeCache(store, partial)
    cacheDir = joinpath(store, "cache")
    if !isdir(cacheDir)
        mkpath(cacheDir)
    end

    cacheFile = joinpath(cacheDir, partial*".cache")
    if isfile(cacheFile)
        rm(cacheFile)
    end
end

function extractAndRead(appImageFile)
    filename = split(appImageFile,"/")[end]
    mountpoint = joinpath(tempdir(),filename*string(time_ns()))
    mkpath(mountpoint)
    startpath = pwd()
    cd(mountpoint)
    run(pipeline(`$appImageFile --appimage-extract`, stdout=devnull))
    cd("squashfs-root")
    outpath = pwd()
    cd(startpath)
    return outpath
end

function integrate(args; reenable=false)
    store = joinpath(pwd(),args[:store])
    if !isfile(store) && !isdir(store)
        mkpath(store)
    end
    iconStore = joinpath(store, "icons")
    if !isfile(iconStore) && !isdir(iconStore)
        mkpath(iconStore)
    end

    startPath = joinpath(pwd(),args[:appimage])

    filename = let parts=splitpath(startPath); parts[length(parts)] end

    extracted = extractAndRead(startPath)

    dirIcon = joinpath(extracted,".DirIcon")
    desktop = filter(x->endswith(x,".desktop"),readdir(extracted))
    partial = replace(filename,".AppImage"=>"")
    iconExtension = ""

    name = partial
    comment = name
    append = ""
    if length(desktop)>0
        partial = replace(desktop[1],".desktop"=>"")
        lines = split(read(joinpath(extracted,desktop[1]),String),"\n")

        fname = readDesktopSection(lines,"Name")
        fcomment = readDesktopSection(lines,"Comment")
        categories = filter(x->startswith(x,"Categories="),lines)
        
        if fname !== nothing
            name = fname
            comment = name
        end
        if fcomment !== nothing
            comment = fcomment
        end
        if length(categories)>0
            append *= "\n$(categories[1])"
        end

        if isfile(joinpath(extracted,partial*".png"))
            iconExtension = ".png"
        elseif isfile(joinpath(extracted,partial*".svg"))
            iconExtension = ".svg"
        elseif isfile(joinpath(extracted,partial*".xpm"))
            iconExtension = ".xpm"
        end
    end

    targetPath = joinpath(store,partial*".AppImage")
    iconPath = joinpath(iconStore,partial*iconExtension)

    template = makeDesktopTemplate(name, comment, targetPath, iconPath)*append*"\n"

    if relpath(startPath, targetPath) != "."
        mv(startPath, targetPath)
    end

    applications = joinpath(xdgdatahome(),"applications")
    if !isdir(applications)
        mkpath(applications)
    end

    write(joinpath(applications,"appimage-"*partial*".desktop"), template)

    cp(dirIcon, iconPath; follow_symlinks=true)

    rm(mountpoint; recursive=true)

    if reenable
        println("Re-integrated AppImage $partial in $store.")
    else
        println("Integrated AppImage $partial in $store.")
    end
end

function list(args)
    store = joinpath(pwd(),args[:store])
    appImages = filter(x->endswith(x,".AppImage.disabled")||endswith(x,".AppImage"),readdir(store))
    println("Installed AppImages in $store:")
    for name in appImages
        if endswith(name,".disabled")
            printstyled(" (disabled) $(replace(name,".AppImage.disabled"=>""))\n"; color = :white)
        else
            printstyled(" $(replace(name,".AppImage"=>""))\n"; color = :green)
        end
    end
end

function main_cli()
    defaultStore = joinpath(homedir(),".opt/appimagehandler")

    argsGlobal = ArgParseSettings()
    @add_arg_table argsGlobal begin
        "integrate"
            help = "Integrate an AppImage into the system"
            action = :command
        "disable"
            help = "Disable an installed AppImage"
            action = :command
        "enable"
            help = "Enable an installed AppImage"
            action = :command
        "list"
            help = "List integrated AppImages"
            action = :command
        "purge"
            help = "Remove installed AppImage completely"
            action = :command
    end

    @add_arg_table argsGlobal["integrate"] begin
        "appimage"
            help = "AppImage file to integrate"
            required = true
        "--store"
            help = "AppImage storage location"
            default = defaultStore
    end

    @add_arg_table argsGlobal["enable"] begin
        "appimage"
            help = "AppImage to enable"
            required = true
        "--store"
            help = "AppImage storage location"
            default = defaultStore
    end

    @add_arg_table argsGlobal["list"] begin
        "--store"
            help = "AppImage storage location"
            default = defaultStore
    end

    @add_arg_table argsGlobal["disable"] begin
        "--store"
            help = "AppImage storage location"
            default = defaultStore
        "appimage"
            help = "AppImage to disable"
            required = true
    end

    @add_arg_table argsGlobal["purge"] begin
        "--store"
            help = "AppImage storage location"
            default = defaultStore
        "appimage"
            help = "AppImage to purge"
            required = true
    end


    parsedGlobal = parse_args(ARGS, argsGlobal; as_symbols=true)

    if parsedGlobal[:_COMMAND_] == :integrate
        integrate(parsedGlobal[:integrate])
    elseif parsedGlobal[:_COMMAND_] == :list
        list(parsedGlobal[:list])
    elseif parsedGlobal[:_COMMAND_] == :disable
        disable(parsedGlobal[:disable])
    elseif parsedGlobal[:_COMMAND_] == :purge
        disable(parsedGlobal[:purge];purge=true)
    elseif parsedGlobal[:_COMMAND_] == :enable
        enable(parsedGlobal[:enable])
    end

    return Int32(0)
end

end
