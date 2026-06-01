# BETPlayerCap (UE4SS Lua mod)

Raises the player cap above the default 6 in **Backrooms Escape Together**, and
adds host-only tools to keep a 7+ player session working (gather, level switch,
reload a stuck level, and board the elevator for level transitions).

The mod runs **only on the host** (the listen-server authority). Clients do not
need it installed — they just join the host's lobby.

## What it does

- **Raises the multiplayer player-count cap** (target 12) via the settings widget
  defaults, so the host can create a lobby for more than 6.
- **Auto spawn-fix** on normal level entry: if a player spawns on the wrong floor
  (an outlier far from the group), they are teleported to the group. Settling-gated
  so it never fires mid-elevator-descent, and outlier-only so it never rubber-bands
  someone who walks off on purpose.

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

`Ctrl+K`/`Ctrl+L` jump straight to a map and bypass the lobby/ending-path, so level
objectives may not initialize. `Ctrl+Arrows` / `Ctrl+PageUp/Down` move the host in
small no-collision steps (~100u/press, camera-relative horizontally) — a recovery tool to
get the host past a spot a 7+ player run can't pass normally. They ignore walls, so
tap carefully near ledges. All of these are host-only.

## Install

See the repo root `README.md` for the one-command installer
(`tools/install_ue4ss_mod.py`). In short: install base UE4SS first, then run the
installer to copy this folder into `…/BET/Binaries/Win64/ue4ss/Mods/`, enable it in
`mods.txt`, and drop in the anti-lag `Engine.ini`.

## Notes

- Built and tested on the UE 5.7.4 MSVC shipping build with UE4SS v3.0.1.
- Requires UEHelpers (ships with UE4SS) for host-pawn resolution.
- Logs everything it does to `UE4SS.log` with `[SPAWN]`/`[SUMMON]`/`[LEVELSW]`/
  `[RELOAD]`/`[PROBE]`/`[BOARD]` tags.
- See the repo `CHANGELOG.md` for the full version history and `docs/` for the
  diagnostics behind each design decision.
