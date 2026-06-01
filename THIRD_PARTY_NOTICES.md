# Third-party notices

This repository's release zip includes runtime files from the following third-party
projects so end users do not need to assemble the UE4SS installation manually.

## UE4SS / RE-UE4SS

The full release package includes UE4SS proxy/runtime files (`dwmapi.dll`,
`ue4ss/UE4SS.dll`, `UE4SS-settings.ini`, `UE4SS_Signatures/`, Keybinds, shared
UEHelpers, and supporting runtime DLLs) copied from the tested local UE4SS install.

The UE4SS license file is included inside the release payload at:

```text
payload/Win64/ue4ss/LICENSE
```

For source and upstream license details, see the UE4SS / RE-UE4SS project.

## BETPlayerCap

`ue4ss_mods/BETPlayerCap/` contains this repository's Lua mod source.

## Game files

The release package intentionally does **not** include Backrooms: Escape Together game
executables, assets, PAK/UCAS/UTOC files, logs, dumps, or generated SDK/header dumps.
Users must own and install the game separately through Steam.
