# User guide

## Supported package

Current public package: **BETPlayerCap v2.14 full Windows package**.

The full package includes UE4SS runtime files, so normal users do **not** need to install
UE4SS or Python separately.

## Who installs it?

Only the **host** installs the mod. Other players can join normally.

## How to find the game folder

In Steam:

1. Right-click **Backrooms: Escape Together**.
2. Choose **Manage > Browse local files**.
3. The folder that opens should be `Backrooms_Escape_Together`.

If the installer cannot find the default path, drag that `Backrooms_Escape_Together` folder
onto `install.bat`, or run:

```bat
install.bat "D:\SteamLibrary\steamapps\common\Backrooms_Escape_Together"
```

## Install

1. Close the game.
2. Download the full release zip from GitHub Releases.
3. Extract it.
4. Run `install.bat`.
5. Launch the game through Steam.

## Uninstall

Run `uninstall.bat` from the same extracted folder. It uses the backup/manifest created by
`install.bat` to restore overwritten files and remove files that did not exist before.

## Files changed by the installer

Under the game folder:

- `BET/Binaries/Win64/dwmapi.dll`
- `BET/Binaries/Win64/ue4ss/`
- `BET/Binaries/Win64/ue4ss/Mods/BETPlayerCap/`
- `BET/Binaries/Win64/ue4ss/Mods/Keybinds/`
- `BET/Binaries/Win64/ue4ss/Mods/shared/UEHelpers/`

Under your user config folder:

- `%LOCALAPPDATA%\BET\Saved\Config\Windows\Engine.ini`

Backups are stored under:

- `BET/Binaries/Win64/.BETPlayerCapBackup/`

## Keybinds

See the root README for the current keybind table. All gameplay tools are host-only.

## Logs for bug reports

If something breaks, include:

- `%LOCALAPPDATA%\BET\Saved\Logs\BET.log`
- `<GameRoot>\BET\Binaries\Win64\ue4ss\UE4SS.log`
- Whether you were the host or a client
- Player count
- Package version
- Whether the game was launched through Steam
