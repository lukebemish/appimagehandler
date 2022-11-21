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

function makeDesktopTemplate(name, comment, filepath, iconpath)
    return """
[Desktop Entry]
Name=$name
Exec=$filepath
Terminal=false
Type=Application
Icon=$iconpath
Comment=$comment"""
end

unknownVersionString = "unknown"

function disable(args, sharedArgs;mode=:disable)
    store = joinpath(pwd(),sharedArgs[:store])

    file = joinpath(store, args[:appimage]*".AppImage")
    newfile = joinpath(store, args[:appimage]*".AppImage.disabled")

    if mode==:purge || mode==:overwrite
        if isfile(file)
            rm(file)
        end
        if isfile(newfile)
            rm(newfile)
        end
        removeCache(store, args[:appimage])
    end

    desktopfile = joinpath(xdgdatahome(), "applications","appimage-"*args[:appimage]*".desktop")
    icon = joinpath(store, "icons", args[:appimage])
    link = joinpath(store, "bin", args[:appimage])

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

    if islink(link)
        rm(link)
    end

    if mode==:purge
        println("Purged AppImage $(args[:appimage]) in $store.")
    elseif mode==:overwrite
        println("Overwriting AppImage $(args[:appimage]) in $store.")
    else
        println("Disabled AppImage $(args[:appimage]) in $store.")
    end
end

function enable(args, sharedArgs)
    store = joinpath(pwd(),sharedArgs[:store])

    newfile = joinpath(store, args[:appimage]*".AppImage")
    file = joinpath(store, args[:appimage]*".AppImage.disabled")

    if isfile(file)
        mv(file, newfile)
    end

    complexIntegrate(merge(args,Dict(:appimage=>newfile)),sharedArgs;mode=:reenable)
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

function cacheversion(cache::CacheData)
    cache.version
end

function cacheversion(cache::Nothing)
    unknownVersionString
end

function getCache(store, partial)
    cacheDir = joinpath(store, "cache")
    if !isdir(cacheDir)
        mkpath(cacheDir)
    end

    cacheFile = joinpath(cacheDir, partial*".cache")
    
    if !isfile(cacheFile)
        return nothing
    end

    text = read(cacheFile, String)
    err = TOML.tryparse(text)

    if err isa TOML.ParserError
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

function removeExtracted(extracted)
    startdir = pwd()
    cd(extracted)
    cd("../")
    d = pwd()
    cd(startdir)
    rm(d;recursive=true)
end

function integrate(store, targetPath, startPath, partial, terminal, template, dirIcon, iconPath, extracted, version; mode=:integrate)
    if relpath(startPath, targetPath) != "."
        mv(startPath, targetPath)
    end

    run(`chmod +x $targetPath`)
    # make bin symlink
    bindir = joinpath(store,"bin")
    mkpath(bindir)
    symlink(targetPath, joinpath(bindir,partial))

    applications = joinpath(xdgdatahome(),"applications")
    if !isdir(applications)
        mkpath(applications)
    end

    if !terminal
        write(joinpath(applications,"appimage-"*partial*".desktop"), template)
        cp(dirIcon, iconPath; follow_symlinks=true)
    end

    writeCache(store, partial, CacheData(version))

    removeExtracted(extracted)

    if mode==:reenable
        println("Re-integrated AppImage $partial in $store.")
    elseif mode==:replacefailed
        println("Failed to install existing AppImage $partial in $store; attempting to revert...")
    else
        println("Integrated AppImage $partial in $store.")
    end
end

function list(args, sharedArgs)
    store = joinpath(pwd(),sharedArgs[:store])
    if !isdir(store)
        mkpath(store)
    end
    appImages = filter(x->endswith(x,".AppImage.disabled")||endswith(x,".AppImage"),readdir(store))
    if isempty(appImages)
        println("No AppImages installed in $store.")
        return
    end
    println("Installed AppImages in $store:")
    for name in appImages
        partial = replace(name,".AppImage.disabled"=>"",".AppImage"=>"")
        cache = getCache(store, partial)
        version = cacheversion(cache)
        if endswith(name,".disabled")
            printstyled(" $(strikethrough(partial)) ($version, disabled)\n"; color = :white)
        else
            printstyled(" $partial ($version)\n"; color = :green)
        end
    end
end

function complexIntegrate(args, sharedArgs; mode=:integrate)
    overwrite = args[:overwrite]
    store = joinpath(pwd(),sharedArgs[:store])

    store = joinpath(pwd(),sharedArgs[:store])
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
    partial = replace(filename,".AppImage"=>""," "=>"")
    iconExtension = ""

    name = partial
    comment = name
    append = ""
    version = unknownVersionString
    terminal = false
    if length(desktop)>0
        partial = replace(desktop[1],".desktop"=>"")
        lines = split(read(joinpath(extracted,desktop[1]),String),"\n")

        name = something(readDesktopSection(lines,"Name"), name)
        comment = name
        comment = something(readDesktopSection(lines,"Comment"), name)
        version = something(readDesktopSection(lines,"X-AppImage-Version"), version)
        partial = replace(something(readDesktopSection(lines,"X-AppImage-Name"), partial), " "=>"")
        terminal = something(readDesktopSection(lines,"Terminal"), terminal)
        if terminal isa String
            terminal = lowercase(terminal) == "true"
        end
        
        categories = filter(x->startswith(x,"Categories="),lines)
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

    targetPath = abspath(joinpath(store,partial*".AppImage"))
    iconPath = joinpath(iconStore,partial*iconExtension)

    template = makeDesktopTemplate(name, comment, targetPath, iconPath)*append*"\n"
    
    checkFailure = false
    wasDisabled = false

    if (isfile(targetPath) || isdir(targetPath*".disabled")) && relpath(startPath, targetPath) != "."
        if !overwrite
            println("AppImage $partial already exists in $store.")
            return
        end
        if isfile(targetPath*".backup")
            rm(targetPath*".backup")
        end
        if isfile(targetPath)
            mv(targetPath, targetPath*".backup")
        else
            wasDisabled = true
            mv(targetPath*".disabled", targetPath*".backup")
        end
        disable(merge(args,Dict(:appimage=>partial)),sharedArgs; mode=:overwrite)
        checkFailure = true
    end

    try
        integrate(store, targetPath, startPath, partial, terminal, template, dirIcon, iconPath, extracted, version; mode=mode)
    catch e
        if !checkFailure
            throw(e)
        end
        @error "Something went wrong while installing AppImage $partial in $store:" exception=(e, catch_backtrace())
        disable(merge(args,Dict(:appimage=>partial)),sharedArgs; mode=:overwrite)
        mv(targetPath*".backup", targetPath)
        integrate(store, targetPath, targetPath, partial, terminal, template, dirIcon, iconPath, extracted, version; mode=:replacefailed)
        if wasDisabled
            disable(merge(args,Dict(:appimage=>partial)),sharedArgs; mode=:disable)
        end
        if isfile(targetPath*".backup")
            rm(targetPath*".backup")
        end
    end
end

function strikethrough(text)
    return "\e[9m$text\e[0m"
end

function main_cli()
    nodesktopintegration = joinpath(homedir(),".local/share/appimagekit/no_desktopintegration")
    if !isfile(nodesktopintegration)
        mkpath(dirname(nodesktopintegration))
        touch(nodesktopintegration)
    end

    defaultStore = joinpath(homedir(),".opt/appimagehandler")

    argsGlobal = ArgParseSettings()
    
    @add_arg_table argsGlobal begin
        "--store"
            help = "AppImage storage location"
            default = defaultStore
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
        "--overwrite"
            help = "Overwrite existing AppImage"
            nargs = 0
    end

    @add_arg_table argsGlobal["enable"] begin
        "appimage"
            help = "AppImage to enable"
            required = true
    end

    @add_arg_table argsGlobal["list"] begin
    end

    @add_arg_table argsGlobal["disable"] begin
        "appimage"
            help = "AppImage to disable"
            required = true
    end

    @add_arg_table argsGlobal["purge"] begin
        "appimage"
            help = "AppImage to purge"
            required = true
    end


    parsedGlobal = parse_args(ARGS, argsGlobal; as_symbols=true)

    if parsedGlobal[:_COMMAND_] == :integrate
        complexIntegrate(parsedGlobal[:integrate], parsedGlobal)
    elseif parsedGlobal[:_COMMAND_] == :list
        list(parsedGlobal[:list], parsedGlobal)
    elseif parsedGlobal[:_COMMAND_] == :disable
        disable(parsedGlobal[:disable], parsedGlobal)
    elseif parsedGlobal[:_COMMAND_] == :purge
        disable(parsedGlobal[:purge], parsedGlobal;mode=:purge)
    elseif parsedGlobal[:_COMMAND_] == :enable
        enable(parsedGlobal[:enable], parsedGlobal)
    end

    return Int32(0)
end

end
