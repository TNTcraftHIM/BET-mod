# Full Player-Scaling Audit (v2.17)

> Line-by-line read of every `LevelNChunkManager` / `GameState` / `GameMode` /
> progression actor in `BETGame.hpp` (2026-06-02 dump, UE 5.7 MSVC shipping build).
> This is the data that drives the per-class caps and gate-disables in main.lua v2.17+.

---

## "All players must be present" gates — disable when > ALL_PLAYERS_GATE_CAP (6)

| Class | Field | Offset | Notes |
|-------|-------|--------|-------|
| `AInteractableTeleporter` | `bRequiresAllPlayers` (bool) | 0x2E0 | Teleporter pads that require every player to stand on them. 16 players physically cannot fit. |
| `ALevelExitBase` | `bRequiresAllPlayers` (bool) + `OnAllPlayersPresent()` | 0x310 | Level exit gates the same way. Blocks progress for >6. |

**Action:** scan these classes, set `bRequiresAllPlayers = false` whenever possessed players > ALL_PLAYERS_GATE_CAP. Also post-hook their "all present" callbacks (`OnAllPlayersPresent`, `OnSurvivorOverlap`) to re-assert.

---

## Level 232 — ScaledPricePercent floor

| Class | Field | Type | Notes |
|-------|-------|------|-------|
| `Level232GameState` | `ScaledPricePercent` (float) | float | The game multiplies item sale price by this value. More players → lower value → harder to meet the sell-out quota. User-confirmed as a blocking issue at >6. |

**Config:** `S232_PRICE_FLOOR = 0.50` (i.e. minimum 50% of original price). Clamp when the game drives it below this floor due to player count.

---

## Numeric requirement caps — cap per-class fields at GENERIC_OBJECTIVE_CAP (10)

These are player-count-scaled numeric requirements, not spawn counts or progress trackers:

| Class | Field | Cap | Notes |
|-------|-------|-----|-------|
| `FuseBoard` | `RequiredFuseAmount` | 10 | Level 3 fuse puzzle — scales via `PlayerCountFuseCurve`. |
| `RepairableElectricalBox` | `RequiredFuseAmount` | 10 | Same as above, another repairable box type. |
| `CoinGate` | `CoinsRequired` | 10 | Coins needed to open the gate. |
| `InteractableDoor` | `ItemAmountRequired` | 10 | Door that requires a certain number of items placed on it. |
| `LevelFunExitDoor` | `RequiredTicketMilestone` | 10 | FUN level exit door — ticket count threshold. |
| `LevelFunExitPinger` | `ItemAmountRequired` | 10 | Same as InteractableDoor but for the pinger variant. |
| `ChristmasPresentQuestActor` | tag-count (TArray<int32>) | 10 per entry | Cap each element of the required-present-tags array at 10. |

**Action:** use the same `cap_props_on_classes()` pattern as elevator/generator caps. For `ChristmasPresentQuestActor`, iterate the TArray and cap individual elements.

---

## Confirmed: scales with players (via curve / per-player field) — not directly capped, need live test

| Class | Field(s) | Curve/Per-Player Evidence | Notes |
|-------|----------|---------------------------|-------|
| `ALevel3ChunkManager` | `PlayerCountToWireCurve`, `PlayerCountToRepairItemMultiplier` | UCurveFloat + multiplier name | Level 3 wire/repair-item spawn scaling. Covered by the generic `CurrentObjectives` path if these feed into it; otherwise needs explicit cap. |
| `AFuseBoard` | `PlayerCountFuseCurve` (UCurveFloat) → `RequiredFuseAmount` | Curve indexed by player count, then written to RequiredFuseAmount | The cap on RequiredFuseAmount above covers the result of this curve. |
| `ALevelNeg1Manager` | `EntitySpawnChancePerPlayer` + `MaxShadowSpawnAmount` | Per-player float with fixed ceiling | Shadow spawn rate scales but is bounded by MaxShadowSpawnAmount (fixed). Not a blocking gate, just harder at >6. **Not capped** — this is monster difficulty, not an objective requirement. |
| `Level232GameState` | `ScaledPricePercent` | Decreases per player | See above: clamped to S232_PRICE_FLOOR. |

---

## Confirmed FIXED (not player-scaled) — do NOT cap these

### Level 1 (`Level1ChunkManager`)
- `MaxSkinStealers` — fixed int, does not grow with players.
- `NumberOfAlmondWater` — fixed int, does not grow.
- `NumberOfGenerators` — covered separately by GENERATOR_CAP = 10 (fixed value, not per-player; the cap is just a safety net if the game initializes it above 10).
- `NumberOfPuddles` — fixed int.

### Level 232 (`Level232GameState`)
- `ItemSpawnRates` — `FIntPoint` min/max ranges for item spawn counts. Fixed per-chunk, no player-count field. (These are *supply* levels; more players = less per-player supply, but the absolute count doesn't increase.)
- `FacelingSpawnChunkInterval`, `FacelingMarkerTargetCountPerChunk` — fixed ints.

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

## Summary of all caps applied by v2.17+ mod logic

| What | Cap value | Method |
|------|-----------|--------|
| Lobby/session player cap (`TARGET_CAP`) | 16 (EOS hard limit) | Widget override + post-hooks on InitializeSelection/ClampMaxPlayers/IncreaseMaxPlayers |
| Elevator presence gate (`Elevator_Base.PlayersNeededToStartElevator`) | ≤6 | `cap_props_on_classes()` per-class scan + hooks |
| Generator count (`Level1ChunkManager.NumberOfGenerators`) | ≤10 | Same pattern |
| Generic player-scaled objectives (`FLevelObjective.ObjectiveAmount` where `bScalesWithPlayers=true`) | ≤10 | Array scan across all GameStates |
| Numeric requirement fields (FuseBoard, CoinGate, InteractableDoor, etc.) | ≤10 | Per-class property cap |
| "All players present" gates (`bRequiresAllPlayers` on teleporters/level exits) | false when >6 possessed | Instance scan + post-hooks |
| Level 232 sale-price discount (`ScaledPricePercent`) | ≥0.50 | Per-instance clamp on `Level232GameState` |
