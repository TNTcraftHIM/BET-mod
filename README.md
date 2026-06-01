# BET Player Cap Mod

A UE4SS mod for **Backrooms Escape Together** that raises the multiplayer player
cap above the default **6** (target **12**), plus host tools to keep a 7+ player
run working: gather scattered players, switch/reload levels, and board the elevator
for level transitions.

> Only the **host** installs this. Clients just join the host's lobby normally.
> Test in **private lobbies with consenting friends** — not public matchmaking.

## Requirements

- **Backrooms Escape Together** on Steam (UE 5.7.4 shipping build).
- **UE4SS v3.0.1** installed for the game (third-party — see *Install UE4SS* below).
- **Python 3** to run the installer (any recent Python; Anaconda is fine).

## Host keybinds

| Key | Action |
|-----|--------|
| **Ctrl+G** | Gather all players to the host (manual, anytime) |
| **Ctrl+J** | Reload the current level (un-stick a player stuck on loading) |
| **Ctrl+K** | Previous level |
| **Ctrl+L** | Next level |
| **Ctrl+O** | Probe the elevator (READ-ONLY: logs gate values + box geometry) |
| **Ctrl+P** | Teleport all players into the elevator (for 7+ level transitions) |
| **Ctrl+Arrows** | Noclip-nudge the host (camera-relative: ↑ forward, ↓ back, ←/→ strafe) |
| **Ctrl+PageUp/Down** | Noclip-nudge the host up / down (Z axis) |

`Ctrl+Arrows` / `Ctrl+PageUp/Down` move the host in small no-collision steps —
a cheat to get past a spot a 7+ player run can't pass normally. Each press steps
~100 units and ignores walls, so tap carefully near ledges.

A wrong-floor player is also **auto-gathered on normal level entry** (settling-gated,
outlier-only — it won't yank someone who walked off on purpose).

## Install

### Recommended: full no-Python release zip

Use `dist/BETPlayerCap-v2.14-full.zip`. It includes the tested UE4SS runtime/proxy
DLLs, the BETPlayerCap mod, Keybinds/UEHelpers dependencies, anti-lag `Engine.ini`,
and double-click installers.

1. Close the game.
2. Extract `BETPlayerCap-v2.14-full.zip` anywhere.
3. Double-click `install.bat`.
   - Default game path: `F:\Steam\steamapps\common\Backrooms_Escape_Together`
   - If the game is elsewhere, drag the game root folder onto `install.bat`, or run:
     ```bat
     install.bat "D:\SteamLibrary\steamapps\common\Backrooms_Escape_Together"
     ```
4. Launch through Steam and host a lobby. Only the host needs this package.

Uninstall with `uninstall.bat` from the same extracted folder.

### Developer/source install

If you already installed UE4SS manually and want to install from source instead of the
full zip:

```bat
python tools\install_ue4ss_mod.py install
```

This source installer copies only the mod and anti-lag config; it expects base UE4SS to
already exist. Pass `--game-root "D:\path\to\Backrooms_Escape_Together"` for a non-default
path.

### Source uninstall

```bat
python tools\install_ue4ss_mod.py uninstall
```
Removes the mod folder, restores the `mods.txt` state, and restores/removes `Engine.ini`
from its backup.

### UE4SS note

The full zip bundles the tested UE4SS runtime needed by this mod. The source installer
path does **not** bundle/install UE4SS; it only checks that UE4SS exists.

## Anti-lag Engine.ini

7-player sessions can lag because the game's voice chat logs a per-frame "underrun"
warning that floods `BET.log` (seen at **76 MB / 405k lines**), and on a listen
server that disk flood drops the host tick rate — raising latency for everyone.
The bundled `config/Engine.ini` raises the log threshold for the single worst
category (`LogTriiodideVoiceChatSynth`) so the per-frame audio-synth underrun flood
stops being written. Other voice channel logs remain visible so player-specific
voice issues can still be diagnosed. It changes logging only, not gameplay, and is
reversible (the uninstaller restores your original). Details in
[`docs/performance_lag_diagnosis.md`](docs/performance_lag_diagnosis.md).

## Known issues

- **Stuck on loading after rapid level switches** — a game-native replication race
  (IrisGate) with no retry. Press **Ctrl+J** to reload and re-roll it. Normal
  elevator progression spaces travels out enough to mostly avoid it.
- **Voice underrun itself** is network-side (host uplink saturation under 7-way
  voice); the anti-lag ini removes the logging amplifier but can't fix the uplink.

## Repository layout

- `ue4ss_mods/BETPlayerCap/` — the mod source (Lua + metadata). This is what ships.
- `config/Engine.ini` — anti-lag logging override (installed to the user config dir).
- `tools/install_ue4ss_mod.py` — one-command install/uninstall.
- `tools/check_install.py` — verifies game files and checks for anti-cheat.
- `tools/scan_bet_strings.py`, `tools/aob_scanner_v*.py` — research scanners.
- `docs/` — findings, level structure, signatures, and the lag diagnosis.
- `CHANGELOG.md` — full version history (currently **v2.14**).

## Safety

- Private lobbies with consenting players only; not for public matchmaking.
- No anti-cheat bypass or detection evasion (none was found in this game's files).
- All changes are reversible; the installer backs up files before replacing them.
