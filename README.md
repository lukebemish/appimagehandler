# appimagehandler
A package-manager-like tool for integrating AppImages into the desktop environment

## Installation
appimagehandler can install itself. To integrate it:
 - Download an AppImage for the program from the [releases](https://github.com/lukebemish/appimagehandler/releases);
 - Run `chmod +x appimagehandler_<arch>.AppImage` to make it executable
 - Run `./appimagehandler_<arch>.AppImage integrate appimagehandler_<arch>.AppImage` to integrate it into your home directory.

 By default, appimagehandler integrates AppImages into the `~/.opt/appimagehandler/` directory. To change this directory for a given operation, use the
 `--store` argument.

 To easily use appimagehandler and other integrated AppImages from the command line, add `~/.opt/appimagehandler/bin` to your `$PATH`.

 ## Updating AppImages

 To update AppImages, you will additionally need appimageupdatetool integrated, which can be found [here](https://github.com/AppImageCommunity/AppImageUpdate/releases).
 Make sure you download and integrate the cli version, "appimageupdatetool", not the gui version "AppImageUpdate". Then, the `appimagehandler update` command
 can be used to update updatable AppImages.
