# Known follow-up issues

## Second-run cap reapplication can fail after a completed save — FIXED in v2.19.4

Priority: was low / follow-up investigation. Resolved 2026-06-07.

User report (2026-06-07): after a save has already cleared the game once, a second playthrough can sometimes stop reapplying requirement caps on levels that were capped on the first run. Example: Level 1 generator requirement can return to an uncapped value instead of staying at the intended <=6/10-player baseline.

### Root cause

`level_detected` latched `true` on the first gameplay level and was reset **only** by the mod's own Ctrl+K/L/J handlers (`do_level_step`, `reload_current_level`). A GAME-DRIVEN transition — finishing a level through the in-game elevator, returning to the lobby, or starting a fresh run from a cleared save — never reset it. Consequences on a second run:

- The immediate full cap/scale pass in monitor Phase 1 (`cap_*`, `scale_supply_for_more_players`, etc.) only fires on the `false -> true` edge of `level_detected`, so it never re-ran. The new level relied entirely on the `BETChunkManagerBase:GenerateChunks` hook plus the 10s monitor — the fragile path.
- The per-level maps were never cleared: `supply_scaled_original` keys a base by object name, so a re-used name on the new run kept a stale (already-scaled or larger) base, making `scale_supply_number` compute too low a target and skip the write. `objective_cap_changed`, `s232_price_logged`, and `l6_scale_logged` similarly suppressed work/logs.

### Fix (v2.19.4)

- Added `reset_per_level_state(reason)` which re-arms `spawn_fix_applied` / `level_detected` / settle state AND clears `supply_scaled_original`, `objective_cap_changed`, `objective_cap_hook_fired`, `s232_price_logged`, `l6_scale_logged`.
- The two manual handlers (`do_level_step`, `reload_current_level`) now call it instead of resetting four fields inline.
- Monitor Phase 0 watches the live world name (`UEHelpers.GetWorld():GetName()`); on a change while already `level_detected`, it calls `reset_per_level_state("world-change")`. This covers game-driven transitions, not just the mod's own keybinds.

The reset only ever forces caps/scales to be re-applied from the current level's authored values; it never removes a cap. Still worth a live ≥7-player second-playthrough confirmation, but the latch/stale-base root cause is addressed.
