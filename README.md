# RokuMenu

UE4SS in-game menu for **GON: God of Nothing**.

Tab opens it. Cheats, outfits, camera tools, saved mouse and volume. Does not replace game files.

![RokuMenu](banner.jpg)

## Download

Grab a version from **[Releases](https://github.com/mrdude2x/Roku-Menu/releases)**. Use the named zip on the release page, not GitHub's "Source code" zip.

| Version | Date | Download |
| --- | --- | --- |
| **v0.5** (latest, GON 1.3) | 2026-10-11 | [RokuMenu_v0.5.zip](https://github.com/mrdude2x/Roku-Menu/releases/download/v0.5/RokuMenu_v0.5.zip) |
| v0.4 | 2026-10-08 | [RokuMenu_v0.4.zip](https://github.com/mrdude2x/Roku-Menu/releases/download/v0.4/RokuMenu_v0.4.zip) |
| v0.3 | 2026-10-02 | [RokuMenu_v0.3.zip](https://github.com/mrdude2x/Roku-Menu/releases/download/v0.3/RokuMenu_v0.3.zip) |
| v0.2.1 | 2026-09-26 | [RokuMenu_v0.2.1.zip](https://github.com/mrdude2x/Roku-Menu/releases/download/v0.2.1/RokuMenu_v0.2.1.zip) |
| v0.2 | 2026-09-25 | [RokuMenu_v0.2.zip](https://github.com/mrdude2x/Roku-Menu/releases/download/v0.2/RokuMenu_v0.2.zip) |
| v0.1 | 2026-09-24 | [RokuMenu_v0.1.zip](https://github.com/mrdude2x/Roku-Menu/releases/download/v0.1/RokuMenu_v0.1.zip) |

## Needs

- GON: God of Nothing on Steam
- **Experimental** UE4SS (newest date on [experimental-latest](https://github.com/UE4SS-RE/RE-UE4SS/releases/tag/experimental-latest)). The GitHub "latest" 3.0.1 build does not run on Unreal 5.7.
- Windows 11 or 10. On Linux, add this to Steam launch options: `WINEDLLOVERRIDES="dwmapi=n,b" %command%`

## Install

See **[Install_Guide.pdf](Install_Guide.pdf)** in this repo or inside the zip.

1. Put Experimental UE4SS `dwmapi.dll` and the `ue4ss` folder next to `Roku3-Win64-Shipping.exe`.
2. Copy `RokuMenu` and `shared` from the zip into `ue4ss\Mods`.
3. The folder name must be exactly `RokuMenu`. Leave `enabled.txt` in it. Do not edit `mods.txt`.
4. NumLock on for numpad keys. Tab opens the menu.

## Package layout

```
RokuMenu/enabled.txt
RokuMenu/Scripts/main.lua
RokuMenu/Scripts/core.lua
shared/ModMenu/ModMenu.lua
ReadMe.txt
Install_Guide.pdf
```

`config.json` is created in-game. It stays on that PC and is not in this repo.

## Current version

v0.5 for GON 1.3. Full feature list is in `ReadMe.txt`.