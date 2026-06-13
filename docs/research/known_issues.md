# Known follow-up issues

## Difficulty curve: "some levels too hard with more players" (esp. Level 232) — IN PROGRESS (v2.19.10 diagnostics)

Players report some levels feel too hard at >6. A full parameter audit (dump + 0.14.6 notes + the v2.19.7 live log) found:

- **Only 7 fields in the whole game scale difficulty with player count:** `FLevelObjective.bScalesWithPlayers`→ObjectiveAmount (HANDLED, cap→10); `FuseBoard.PlayerCountFuseCurve` (fixed 9 in the live log; cap removed v2.19.8); `Level3 PlayerCountToWireCurve`/`PlayerCountToRepairItemMultiplier` (SUPPLY — more wire/repair with more players, helps); `Level6 bScaleWithPlayers` (HANDLED, →false); `FUN RedLight PlayerCountFailPenaltyCurve` (UNHANDLED, direction unknown); `Neg1 EntitySpawnChancePerPlayer` (UNHANDLED — more shadows with more players → genuinely harder).
- **Level 232 (the hardest) has NO player-count field at all.** Quota / time / days / Facelings / robots / loot are fixed or procedural — mechanically identical at 6 and >6, and 0.14.6 made its loot per-player (more players = more loot). The "harder" is systemic: 0.14.6 cut warehouse time 30s, shrank the warehouse, reduced loot density; plus big-group selling-throughput + monster-chaos + coordination. There is ZERO runtime data for 232 (never visited live).

### v2.19.10 (shipped): read-only diagnostics only
Added `[S232]` timer/checkout/monster logging and `[NEG1]` shadow logging. No balance number guessed blind. One live ≥7-player run hitting Level 232 + Level -1 will reveal the bottleneck.

### Pending decisions (need user call and/or live data)
1. **Generator cap — RESOLVED v2.19.11 (removed).** `NumberOfGenerators` is the scene spawn count, not the player-scaled requirement (that is the separately-capped `bScalesWithPlayers` `ObjectiveAmount`). The magic-10 cap (no ≤6 guard) was removed; difficulty stays ≤6p via the objective cap; the spawn count is vanilla.
2. **Monster policy (Neg1 `EntitySpawnChancePerPlayer`) — RESOLVED v2.19.11 (neutralized).** Per user direction, scaled DOWN to the 6-player-equivalent `base × 6 / players` (float-safe, anchored, only lowers, no-op at ≤6; bounded by `MaxShadowSpawnAmount`). The mod's first monster-field write. The `[NEG1]` diagnostic confirms the effect on a live run; if `MaxShadowSpawnAmount` already saturates at ≤6 the write is a harmless near-no-op.
3. **FUN RedLight `PlayerCountFailPenaltyCurve` — still pending.** Unhandled, curve direction unknown — do NOT cap blind (the v2.19.8 FuseBoard `GetFloatValue(6)`≈1 trap). Diagnose first (no diagnostic added yet — low priority, one minigame).
4. **Level 232 relief — still pending (needs a live run).** Level 232 has no player-count field, so any relief must be calibrated from the v2.19.10 `[S232]` diagnostics (timer/throughput/monsters/quota). After a live run, pick ONE lever (do not stack — v2.19.6 compounding trap): linear/`sqrt` income via `ScaledPricePercent`, OR cap `RequiredQuota` toward 6p, OR per-day time via `AddTimeToCurrentDay` (needs a day-start hook for idempotency). The mod already scales income; confirm it isn't already over-compensating given 0.14.6 per-player loot.


## Over-capping fixed/procedural level goals trivialized Level FUN & Level 3 — FIXED in v2.19.8

Found from a real ≥7-player (up to 9) BET 0.14.6 live session (mod v2.19.7), then confirmed by a per-field log+dump investigation with adversarial verification. Resolved 2026-06-13.

### Root cause

The mod's "numeric requirement" (`NUMERIC_CAP_*`), "int-array requirement" (`INT_ARRAY_CAP_*`), and curve (`CURVE_REQUIREMENT_*`) cap paths assumed several requirement fields scale UP with player count, and capped them to `GENERIC_OBJECTIVE_CAP=10` (or `ceil(PlayerCountFuseCurve:GetFloatValue(6))`). The design docs flagged the 10 as "a bounded fallback until live logging measures the authored values." The live log measured them and disproved the assumption — they are FIXED or PROCEDURAL level-design goals, not player-scaled, with NO `PlayerCount*`/`*PerPlayer` mechanism on their classes:

- `RequiredTicketMilestone` (LevelFunExitDoor + PartyCelebrationSpeaker) = constant **1500** at 8–9 players → capped to 10 (≈150× trivialization of Level FUN's exit/celebration goal).
- `WarehouseRequiredCoinsTotals[]` (LevelFUNChunkManager) = **per-generation procedural** (164/138/227 vs 124/150/155 at the SAME 9 players) → capped to 10.
- `RequiredFuseAmount` (FuseBoard) = fixed/seeded **9** at 7, 8 AND 9 players; the curve cap basis `GetFloatValue(6)` returned ~1 (a lerp-alpha between `RequiredFusesMin`/`Max`, not a fuse count) → slashed 9 → 1.

These caps also had **no `≤6` player guard**, so they fired even at the 6-player baseline — diverging from vanilla at every count and making >6 play far easier than 6 (the inverse of the design rule).

### Fix (v2.19.8)

Removed the three cap subsystems entirely (tables + `cap_numeric_requirements` / `cap_int_array_*` / `cap_curve_*` functions + the `FuseBoard:OnFuseBoardInitialized` and `LevelFUNChunkManager:AddWarehouseRequiredCoins` hook registrations). Because every removed field is identical at 6 and >6 players, NOT capping keeps ">6 = same as 6" and cannot make >6 harder; the levels' supply is still scaled up independently. The genuinely player-scaled caps are preserved: `PlayersNeededToStartElevator` (tracks count 1:1), `FLevelObjective.ObjectiveAmount` gated by the game's own `bScalesWithPlayers` flag (observed amount = players+4), the all-players gates, the Level 6 puzzle, and the generator safety cap.

### Still needs live data

- `CoinGate.CoinsRequired`, `InteractableDoor`/`LevelFunExitPinger.ItemAmountRequired`, and `RepairableElectricalBox.RequiredFuseAmount` were never encountered in the log; the dump shows no scaling mechanism. v2.19.9 gives them a proportional "6-player-equivalent" guard (`ceil(first_observed × 6 / players)`, no-op at ≤6) instead of removal — safe whether they are fixed (slightly easier) or player-scaled (clamped to 6p). A live encounter at varying counts would confirm which, and could upgrade them to "leave fully vanilla" (if fixed) like the other confirmed fields.
- Level 232 economy (`ScaledPricePercent` / `RequiredQuota`) was never visited this session — the v2.19.6 single-lever income model + the v2.19.7 write-verify remain unconfirmed in-game.
- `NumberOfGenerators` (cap 10) never fired; confirm on a Level-1 ≥7-player run that it does not exceed the baseline.

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
