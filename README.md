# BET Player Cap Mod

**English** | [中文](README.zh-CN.md)

A Windows UE4SS mod package for **Backrooms: Escape Together** that lets a private
lobby host play with more than the default 6 players (target cap: **16**) and adds
host tools for the main 7+ player pain points: gathering separated players, reloading
a stuck level, boarding elevators, capping player-scaled pass requirements to their
6-player baseline where the game exposes it, scaling confirmed supplies up for larger
groups, disabling "all players" gates when the group exceeds 6, and nudging through
geometry when a level was not built for that many bodies.

> **Host-only install for group-wide features.** Only the lobby host/listen-server needs
> the mod for the player cap and host tools. Friends can join normally with an unmodified
> game. If a non-host player also installs it, they can use the optional local-only
> self no-collision toggle below.
>
> **Private/consenting lobbies only.** Do not use this for public matchmaking or to
> disrupt other players.

## Download / install

Use the full Windows package from the GitHub Releases page:

```text
BETPlayerCap-v2.19.9-full.zip
```

A local build may also produce the same file under `dist/` for maintainer use.

Verify your download against the tracked checksum
([`dist/BETPlayerCap-v2.19.9-full.zip.sha256`](dist/BETPlayerCap-v2.19.9-full.zip.sha256));
see [`RELEASES.md`](RELEASES.md).

It includes the tested UE4SS runtime/proxy DLLs, BETPlayerCap, required Keybinds and
UEHelpers support files, an anti-lag `Engine.ini`, and no-Python install/uninstall
scripts.

1. Close the game.
2. **Recommended:** extract the zip directly **into your game folder**
   (`…\steamapps\common\Backrooms_Escape_Together`), then double-click `install.bat`.
   It detects the game folder from where it was extracted automatically.
3. If you extracted it somewhere else, `install.bat` opens a folder picker — select your
   `Backrooms_Escape_Together` folder. You can also pass it explicitly:
   ```bat
   install.bat "D:\SteamLibrary\steamapps\common\Backrooms_Escape_Together"
   ```
4. Launch through Steam and host a private lobby.

To find the game folder in Steam: right-click the game → **Manage → Browse local files**.

Uninstall with `uninstall.bat` from the same folder. The installer records what it changed
and restores backups where possible.

## Host keybinds

| Key | Action |
|-----|--------|
| **Ctrl+G** | Gather all players to the host |
| **Ctrl+J** | Reload the current level (helps players stuck on loading) |
| **Ctrl+K** | Previous level |
| **Ctrl+L** | Next level |
| **Ctrl+O** | Probe elevator state (read-only diagnostics) |
| **Ctrl+P** | Teleport all players into the elevator |
| **Ctrl+Arrow keys** | Noclip-nudge host: forward/back/strafe relative to where host looks |
| **Ctrl+PageUp/PageDown** | Noclip-nudge host up/down on Z axis |
| **Ctrl+N** | Optional local toggle for the installed player's own pawn collision |

Notes:

- The mod also has a spawn-time auto-fix for the known "one player spawns on the wrong
  floor" case. It is settling-gated and outlier-only.
- Noclip nudge ignores collision and moves about 100 units per press. Tap carefully near
  ledges or voids.
- Ctrl+N is local to the player who installed the mod: it toggles collision on that
  player's pawn only. It does not alter monsters or other players.
- Ctrl+K/L jump maps directly and can bypass normal objective/ending-path setup. They are
  convenience tools, not a faithful progression system.

## Known limitations

- **Occasional stuck loading** is a game-native Iris replication race, especially after
  rapid level travel. Use **Ctrl+J** to reload the current level and retry.
- **Voice chat failures for individual players** also occur without this mod. They appear
  to be base-game/EOS RTC/client-network issues, not BETPlayerCap. The included anti-lag
  config only suppresses the worst voice log flood; it does not fix EOS voice itself.
- Some levels were not designed for 7+ players. The objective cap targets player-scaled
  requirements (elevators, generators, puzzles) using a 6-player baseline where the game
  exposes one, scales confirmed supplies up for larger groups, and disables "all players"
  gates when the group exceeds 6. Geometry/loading issues can still require practical
  workarounds. The elevator and noclip tools are not official level support.

## What the package installs

- UE4SS proxy/runtime files under `BET/Binaries/Win64/` (`dwmapi.dll`, `ue4ss/UE4SS.dll`,
  signatures, settings, and runtime DLL dependencies).
- `ue4ss/Mods/BETPlayerCap/`.
- Required UE4SS support mods: `Keybinds` and `shared/UEHelpers`.
- User config anti-lag file:
  `%LOCALAPPDATA%\BET\Saved\Config\Windows\Engine.ini`.

The release package intentionally excludes local logs/dumps/development artifacts such as
`UE4SS.log`, `UE4SS_ObjectDump.txt`, `CXXHeaderDump/`, crash dumps, and debug sample mods.

## Building / source install

The source tree is kept for development and auditability. Most users should use the full
zip above.

If you already have UE4SS installed and only want to copy the Lua mod from source:

```bat
python tools\install_ue4ss_mod.py install
```

For a non-default game path:

```bat
python tools\install_ue4ss_mod.py install --game-root "D:\SteamLibrary\steamapps\common\Backrooms_Escape_Together"
```

## Repository layout

- `dist/` — built release zip (gitignored) plus its tracked `.sha256` checksum.
- `ue4ss_mods/BETPlayerCap/` — Lua mod source.
- `config/Engine.ini` — anti-lag log-suppression config used by installers.
- `tools/` — source/developer install, release-build, and check helpers.
- `tools/research/` — historical scanners/signature tools; not needed for normal use.
- `docs/troubleshooting/` — user-facing diagnostics and troubleshooting notes.
- `docs/research/` — historical investigation notes kept for traceability.
- `CHANGELOG.md` — detailed version history.
- `THIRD_PARTY_NOTICES.md` — notes for bundled UE4SS runtime files.

## Safety / scope

- This is a cooperative private-lobby mod, not a public matchmaking tool.
- It does not bypass anti-cheat or implement detection evasion.
- It ships reversible installers and avoids destructive game-file patching.
- It is unofficial and may break after game updates.
