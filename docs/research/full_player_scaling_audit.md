# Full Player-Scaling Audit (v2.19.10)

> Line-by-line read of every `LevelNChunkManager` / `GameState` / `GameMode` /
> progression actor in `BETGame.hpp` (2026-06-02 dump, UE 5.7 MSVC shipping build).
> This is the data that drives the per-class caps, curve-backed baselines,
> supply scaling, and gate-disables in main.lua v2.19.10+.

---

## "All players must be present" gates — disable when > ALL_PLAYERS_GATE_CAP (6)

| Class | Field | Offset | Notes |
|-------|-------|--------|-------|
| `AInteractableTeleporter` | `bRequiresAllPlayers` (bool) | 0x2E0 | Teleporter pads that require every player to stand on them. 16 players physically cannot fit. |
| `ALevelExitBase` | `bRequiresAllPlayers` (bool) + `OnAllPlayersPresent()` | 0x310 | Level exit gates the same way. Blocks progress for >6. |

**Action:** scan these classes, set `bRequiresAllPlayers = false` whenever possessed players > ALL_PLAYERS_GATE_CAP. Also post-hook their "all present" callbacks (`OnAllPlayersPresent`, `OnSurvivorOverlap`) to re-assert.

---

## Level 232 — sell-price (scale ONLY `ScaledPricePercent` up for >6)

| Class | Field | Type | Notes |
|-------|-------|------|-------|
| `Level232GameState` | `ScaledPricePercent` (float) | float | Global sell-price percentage. BET 0.14.6 patch notes confirm this is an earned-income percentage mechanic. **The single lever the mod scales.** |
| `AALevel232CheckoutLane` | `LaneMultiplier` / `CouponMultiplier` | float | Per-lane sell-price multipliers; coupon applies when active. **Left at vanilla — see below.** |

**Action:** for >6 possessed players, scale ONLY `ScaledPricePercent` upward (linearly, `players/6`) from its first-observed runtime value. No-op at ≤6.

**Why only one lever (v2.19.6):** the sell price multiplies `LaneMultiplier × CouponMultiplier × ScaledPricePercent`. v2.19.3–2.19.5 scaled all three by `players/6`, compounding income to `factor²`–`factor³` (4×–8× at 12 players with a coupon) — a large over-compensation versus ">6 = same difficulty as 6". `Level232ChunkManager.ItemSpawnRates` loot scaling was also removed: 0.14.6 now spawns Level 232 loot per-sector AND per-player, so scaling the count again double-counts. Live ≥7-player testing should confirm the 0.14.6 runtime values and whether `RequiredQuota` scales with player count (if it does, capping it would be the alternative to income scaling).

---

## Numeric / curve / int-array requirement caps — old magic-number cap removed (v2.19.8/9)

These were capped to 10 (or a misread curve) on the assumption they scale up with player
count. A live ≥7-player 0.14.6 session + per-field log+dump investigation DISPROVED that for
the observed fields. Two treatments: CONFIRMED-fixed/procedural fields are left fully vanilla
(removed v2.19.8); UNOBSERVED fields get a principled 6-player-equivalent guard instead of the
magic number (v2.19.9). See `docs/research/known_issues.md`.

| Class | Field | Live finding | Treatment |
|-------|-------|--------------|-----------|
| `FuseBoard` | `RequiredFuseAmount` | fixed/seeded 9 at 7/8/9 players; `PlayerCountFuseCurve:GetFloatValue(6)`≈1 is a lerp-alpha (between `RequiredFusesMin`/`Max`), not a fuse count → had slashed 9→1 | **vanilla (cap removed v2.19.8)** |
| `LevelFunExitDoor` / `PartyCelebrationSpeaker` | `RequiredTicketMilestone` | fixed 1500 across 8-9 players | **vanilla (cap removed v2.19.8)** |
| `LevelFUNChunkManager` | `WarehouseRequiredCoinsTotals[]` | per-generation procedural (164/138/227 vs 124/150/155 at same 9p) | **vanilla (cap removed v2.19.8)** |
| `RepairableElectricalBox` | `RequiredFuseAmount` | no curve / `bRandomizeFuseAmount` seeded; never observed | **6p-equiv guard (v2.19.9)** |
| `CoinGate` | `CoinsRequired` | no player-count mechanism; never observed | **6p-equiv guard (v2.19.9)** |
| `InteractableDoor` / `LevelFunExitPinger` | `ItemAmountRequired` | no player-count mechanism; never observed | **6p-equiv guard (v2.19.9)** |

The 6p-equiv guard caps DOWN to `ceil(first_observed × 6 / players)` when >6 (no-op at ≤6,
only lowers, anchored so it never compounds) — never harder than 6 whether the field is fixed
or actually player-scaled.

## NOT a numeric requirement — do NOT cap via the scalar/array path

| Class | Field | Type | Reason |
|-------|-------|------|--------|
| `ChristmasPresentQuestActor` | `RequiredPresentsTags` | `FGameplayTagContainer` | This is a *tag set*, not an int. It is the number of distinct present tags required. Safely reducing it would mean dropping tags from the container or intercepting the completion comparison — both unverified and risky. Left uncapped pending a live test; the generic `CurrentObjectives` path may still cover it if the game publishes a scaled objective. |

---

## Confirmed: scales with players (via curve / per-player field) — not directly capped, need live test

| Class | Field(s) | Curve/Per-Player Evidence | Notes |
|-------|----------|---------------------------|-------|
| `ALevel3ChunkManager` | `PlayerCountToWireCurve`, `PlayerCountToRepairItemMultiplier` | UCurveFloat + multiplier name | Level 3 wire/repair-item spawn scaling. Covered by the generic `CurrentObjectives` path if these feed into it; otherwise needs explicit cap. |
| `AFuseBoard` | `PlayerCountFuseCurve` (UCurveFloat) → `RequiredFuseAmount` | Curve indexed by player count, then written to RequiredFuseAmount | The cap on RequiredFuseAmount above covers the result of this curve. |
| `ALevelNeg1Manager` | `EntitySpawnChancePerPlayer` + `MaxShadowSpawnAmount` | Per-player float with fixed ceiling | Shadow spawn rate scales UP with players (harder at >6), bounded by MaxShadowSpawnAmount. **Under review (v2.19.10):** the one monster field that provably makes >6 harder than 6; a read-only `[NEG1]` diagnostic now logs it — pending a live value to decide whether to neutralize it to the 6-player level. See `known_issues.md`. |
| `Level232GameState` | `ScaledPricePercent` | Scaled by player count | Scaled up for >6 since v2.19.3 (sole income lever since v2.19.6); 0.14.6 patch notes confirm this is income percentage scaling. |

---

## Fixed supply/spawn fields — do NOT cap down as requirements

These fields are fixed or supply-oriented rather than pass requirements. For >6 players,
confirmed supply fields are scaled upward from their first observed runtime value; monster
and hazard fields remain untouched unless live testing proves a separate need.

### Level 1 (`Level1ChunkManager`)
- `MaxSkinStealers` — fixed monster count; left unchanged.
- `NumberOfAlmondWater` — fixed supply count; **scaled up by `players / 6` for >6 players**.
- `NumberOfGenerators` — currently capped at GENERATOR_CAP = 10, but this is a fixed/procedural field (not per-player) and the cap has NO ≤6 guard. **Flagged for removal (v2.19.10, see `known_issues.md`)** — same category error as the v2.19.8 over-caps; the real generator objective is the separately-capped `bScalesWithPlayers` `ObjectiveAmount`.
- `NumberOfPuddles` — fixed hazard count; left unchanged.

### Level 232 (`Level232GameState` / `Level232ChunkManager`)
- `ItemSpawnRates` — `FIntPoint` min/max ranges for item spawn counts. **No longer scaled (v2.19.6):** 0.14.6 spawns Level 232 loot per-sector AND per-player, so scaling the range too would double-count.
- `ScaledPricePercent` — global earned-income %; **scaled up by `players / 6` for >6 players** from its first observed runtime value (the single income lever).
- `LaneMultiplier`, `CouponMultiplier` — per-lane sell-price multipliers; **left at vanilla (v2.19.6):** scaling them on top of `ScaledPricePercent` compounded income.
- `FacelingSpawnChunkInterval`, `FacelingMarkerTargetCountPerChunk` — fixed monster-spawn fields; left unchanged.

### Level 4 (`Level4GameState`)
- `FacelingSpawnRateMultiplier` — fixed float.

### Level Hub (`HubGameState` / similar)
- `PartygoerSpawnChance` — fixed float.

---

## Uncertain — need live ≥7-player test to confirm

| Class | Field(s) | Reason for uncertainty |
|-------|----------|------------------------|
| Any GameState (via UE4SS `CurrentObjectives`) | `bScalesWithPlayers` + `ObjectiveAmount` in `FLevelObjective[]` | The generic path (`OnRep_CurrentObjectives`, periodic scan of all GameStates' CurrentObjectives arrays) is registered. Whether the game actually sets these flags on any entry outside Level 3 has not been observed at ≥7 players yet. |
| `LevelFUNGameState` | `WarehouseRequiredCoinsTotals` (TArray<int32>) | Array size or per-element values *could* scale with player count, but static dump doesn't show a direct curve reference. Lua can mutate TArray elements in UE4SS but this is unverified. |

---

## Summary of all caps/scales applied by v2.19.10+ mod logic

| What | Cap / scale value | Method |
|------|-------------------|--------|
| Lobby/session player cap (`TARGET_CAP`) | 16 (EOS hard limit) | Widget override + post-hooks on InitializeSelection/ClampMaxPlayers/IncreaseMaxPlayers |
| Elevator presence gate (`Elevator_Base.PlayersNeededToStartElevator`) | ≤6 (live-confirmed player-scaled) | `cap_props_on_classes()` per-class scan + hooks |
| Generator count (`Level1ChunkManager.NumberOfGenerators`) | ≤10 (safety net) | Same pattern |
| Generic player-scaled objectives (`FLevelObjective.ObjectiveAmount` where `bScalesWithPlayers=true`) | ≤10 (game's own flag; observed amount = players+4) | Array scan across all GameStates |
| Unobserved scalar requirements (`CoinGate.CoinsRequired`, `InteractableDoor`/`LevelFunExitPinger.ItemAmountRequired`, `RepairableElectricalBox.RequiredFuseAmount`) | `ceil(first_observed × 6 / players)` when >6 (no-op at ≤6) | Startup + level-detect + monitor; anchored, only-lowers (v2.19.9) |
| Level 232 income (`ScaledPricePercent` only) | scale up by `possessed_players / 6` when >6 | First-observed runtime value is retained as base; no-op at ≤6. `LaneMultiplier`/`CouponMultiplier` left at vanilla (v2.19.6, anti-compounding) |

> Old magic-number cap removed v2.19.8. Left fully vanilla (confirmed fixed/procedural): `FuseBoard.RequiredFuseAmount`, `LevelFunExitDoor`/`PartyCelebrationSpeaker.RequiredTicketMilestone`, `LevelFUNChunkManager.WarehouseRequiredCoinsTotals[]`. Given the 6p-equivalent guard instead (unobserved, v2.19.9): `RepairableElectricalBox.RequiredFuseAmount`, `CoinGate.CoinsRequired`, `InteractableDoor`/`LevelFunExitPinger.ItemAmountRequired` — see the table above.
| "All players present" gates (`bRequiresAllPlayers` on teleporters/level exits) | false when >6 possessed | Instance scan + `OnSurvivorOverlap`/`OnAllPlayersPresent`/teleporter hooks |
| Level 6 puzzle difficulty (`ALevel6PuzzleManager.bScaleWithPlayers`) | `false` when >6 possessed (no-op at ≤6; v2.19.5 guard) | Instance scan with `effective_player_count() > ALL_PLAYERS_GATE_CAP` guard |
| Confirmed integer supply counts (Level 1 almond water, Level 3 lootbox wire/tape counts) | scale up by `possessed_players / 6` when >6 | First-observed runtime value is retained as base to avoid repeated multiplication. Float fields (RepairItemMultiplier, LootSpawnRatio) and Level 232 ItemSpawnRates removed v2.19.6 — see notes above |
