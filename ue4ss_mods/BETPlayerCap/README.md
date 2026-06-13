# BETPlayerCap (UE4SS Lua mod)

Raises the player cap above the default 6 in **Backrooms: Escape Together**, and
adds host-only tools to keep a 7+ player session working (gather, level switch,
reload a stuck level, board the elevator for level transitions). It also includes
an optional local self no-collision toggle for players who install the mod on their
own client.

The mod runs **only on the host** for the player cap and host tools. Clients do not
need it installed — they just join the host's lobby. A client may optionally install
it to use the local-only `Ctrl+N` self no-collision toggle.

## What it does

- **Raises the multiplayer player-count cap** (target 16) via the settings widget
  defaults, so the host can create a lobby for more than 6.
- **Auto spawn-fix** on normal level entry: if a player spawns on the wrong floor
  (an outlier far from the group), they are teleported to the group. Settling-gated
  so it never fires mid-elevator-descent, and outlier-only so it never rubber-bands
  someone who walks off on purpose.
- **Player-scaled requirement/supply handling:** requirements that genuinely scale with
  player count are capped to their 6-player baseline — the elevator presence gate
  (`PlayersNeededToStartElevator` → 6) and objectives the game itself flags
  `bScalesWithPlayers` (→ 10), plus a generator safety cap. Level goals that a live
  ≥7-player test confirmed are FIXED/procedural (FUN ticket milestones = 1500, warehouse
  coin totals, fuse-board amounts) are left fully vanilla — capping them only trivialized
  the level. Requirements never seen live (coin gates, item doors, repair-box fuses) get a
  conservative "never harder than 6" guard: capped down to their 6-player-proportional
  equivalent only when >6 players (no-op at ≤6). Confirmed integer supply counts are
  multiplied upward for >6 players, and Level 232 income (`ScaledPricePercent`) is scaled up
  by `players/6` for >6 (no-op at ≤6).
- **"All players" gate disabler:** when more than 6 players are present, teleporters
  (`AInteractableTeleporter`) and level exits (`ALevelExitBase`) have their
  `bRequiresAllPlayers` flag forced to false — otherwise a group of 7–16 cannot fit on
  pads built for ≤6.

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
| **Ctrl+N** | Optional local toggle: installed player's own pawn collision on/off |

`Ctrl+K`/`Ctrl+L` jump straight to a map and bypass the lobby/ending-path, so level
objectives may not initialize. `Ctrl+Arrows` / `Ctrl+PageUp/Down` move the host in
small no-collision steps (~100u/press, camera-relative horizontally) — a recovery tool to
get the host past a spot a 7+ player run can't pass normally. They ignore walls, so
tap carefully near ledges. Host tools are host-only; `Ctrl+N` is local-only and affects
only the installed player's pawn, not monsters or other players.

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
