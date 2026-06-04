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

**Config:** `S232_PRICE_FLOOR = 1.00` (strict policy: player count is not allowed to discount sell prices at all, so a 16-player run is no harder than ≤6 on the quota). The dump does not expose the authored 6-player curve value (`ScaledPricePercent` has no `UCurveFloat`/data-table in the header), so a measured ≤6-player floor would require live logging; until then, 1.00 is the safe "not harder" choice.

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
| `PartyCelebrationSpeaker` | `RequiredTicketMilestone` | 10 | FUN celebration speaker ticket threshold. |

**Action:** use the same `cap_props_on_classes()` pattern as elevator/generator caps.

## Requirement arrays (capped per element at GENERIC_OBJECTIVE_CAP)

| Class | Field | Type | Notes |
|-------|-------|------|-------|
| `LevelFUNChunkManager` | `WarehouseRequiredCoinsTotals` | `TArray<int32>` | Per-warehouse coin requirement totals. Capped element-wise via `cap_int_array_prop()` and re-asserted by a hook on `AddWarehouseRequiredCoins`. **Live TArray mutation needs ≥7-player confirmation.** |

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
| Level 232 sale-price discount (`ScaledPricePercent`) | ≥1.00 | Per-instance clamp on `Level232GameState` (strict no-discount policy) |
| Level FUN warehouse coin requirements (`WarehouseRequiredCoinsTotals[]`) | ≤10 per element | Int-array scan + `AddWarehouseRequiredCoins` hook |
| "All players present" gates (`bRequiresAllPlayers` on teleporters/level exits) | false when >6 possessed | Instance scan + `OnSurvivorOverlap`/`OnAllPlayersPresent`/teleporter hooks |
