# Tools

Most users do **not** need anything in this folder. Use the full release zip instead.

## Public/developer tools

- `install_ue4ss_mod.py` — source/developer installer. Requires UE4SS to already exist.
- `check_install.py` — verifies a local game install and basic expected files.
- `build_release.ps1` — builds the full Windows release zip from a local tested UE4SS install.

## Research tools

The AOB scanners and signature helpers are historical development tools for investigating
UE4SS signatures and game strings. They are not needed to install or use the mod and may
need adjustment after game updates.

Most tools accept the default example path or the `BET_GAME_ROOT` environment variable:

```powershell
$env:BET_GAME_ROOT = "D:\SteamLibrary\steamapps\common\Backrooms_Escape_Together"
```
