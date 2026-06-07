# Known follow-up issues

## Second-run cap reapplication can fail after a completed save — FIXED in v2.19.4

Priority: was low / follow-up investigation. Resolved 2026-06-07.

User report (2026-06-07): after a save has already cleared the game once, a second playthrough can sometimes stop reapplying requirement caps on levels that were capped on the first run. Example: Level 1 generator requirement can return to an uncapped value instead of staying at the intended <=6/10-player baseline.

### Root cause

`level_detected` latched `true` on the first gameplay level and was reset **only** by the mod's own Ctrl+K/L/J handlers (`do_level_step`, `reload_current_level`). A GAME-DRIVEN transition — finishing a level through the in-game elevator, returning to the lobby, or starting a fresh run from a cleared save — never reset it. The immediate full cap/scale pass in monitor Phase 1 (`cap_*`, `scale_supply_for_more_players`, etc.) only fires on the `false -> true` edge of `level_detected`, so it never re-ran on the new level — leaving it to rely entirely on the `BETChunkManagerBase:GenerateChunks` hook plus the 10s monitor (the fragile path).

A secondary effect: the per-level **log-dedup** maps (`objective_cap_changed`, `s232_price_logged`, `l6_scale_logged`) were never cleared, so a re-detected level suppressed its re-application logs.

> Note (corrected in v2.19.5): the original write-up here also theorized that a stale `supply_scaled_original` base made `scale_supply_number` "compute too low a target and skip the write." That theory was **wrong** — see the v2.19.5 section below. `supply_scaled_original` only ever stores the FIRST-OBSERVED base and is the anchor that keeps supply scaling idempotent; clearing it is harmful, not helpful.

### Fix (v2.19.4)

- Added `reset_per_level_state(reason)` which re-arms `spawn_fix_applied` / `level_detected` / settle state and clears the log-dedup maps.
- The two manual handlers (`do_level_step`, `reload_current_level`) now call it instead of resetting fields inline.
- Monitor Phase 0 watches the live world name (`UEHelpers.GetWorld():GetName()`); on a change while already `level_detected`, it calls `reset_per_level_state("world-change")`. This covers game-driven transitions, not just the mod's own keybinds.

The reset only ever forces caps/scales to be re-applied from the current level's authored values; it never removes a cap. Still worth a live ≥7-player second-playthrough confirmation, but the latch root cause is addressed.

> **v2.19.4 caveat that was corrected in v2.19.5:** as first shipped, `reset_per_level_state()` *also* cleared `supply_scaled_original`. That introduced a real compounding hazard (see below). The v2.19.4 latch fix itself is sound; only the supply-map clear was wrong.

## Supply scaling could compound on a re-detect — FIXED in v2.19.5

Priority: was a regression introduced by v2.19.4. Resolved 2026-06-07 (found by a full adversarial code+docs audit).

`reset_per_level_state()` (v2.19.4) cleared `supply_scaled_original`, the per-object map of the FIRST-OBSERVED runtime value (keyed by full object path). `scale_supply_number` always scales `base * factor` from that stored base, never the already-scaled value — so the map is what keeps supply scaling **idempotent**. If a re-detect (world-change / Ctrl+K-L-J) fired while a supply object still held an already-scaled value, clearing the map made the next pass re-capture that scaled value as the new base and scale it *again*, compounding toward `factor²` (e.g. 1.33× → 1.77× → …).

### Fix (v2.19.5)

- `reset_per_level_state()` no longer clears `supply_scaled_original`. The first-observed base now persists across every re-detect, keeping supply scaling idempotent.
- The per-level **log-dedup** maps (`objective_cap_changed`, `objective_cap_hook_fired`, `s232_price_logged`, `l6_scale_logged`) are still cleared, so a re-detected level re-logs its caps. These behave OPPOSITELY to `supply_scaled_original` — they are meant to be wiped, the base map is meant to be preserved.

Stale `supply_scaled_original` entries for unloaded objects are harmless: new objects get new full-path keys, and a genuinely persistent object keeps its true first-observed base — exactly what we want.
