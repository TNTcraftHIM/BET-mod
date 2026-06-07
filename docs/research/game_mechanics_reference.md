# BET Game Mechanics Reference

> Extracted from `BETGame.hpp` (CXXHeaderDump, UE 5.7 MSVC shipping build, 2026-06-02).
> This document records **all gameplay-relevant fields** per class, organized by level.
> Field values are NOT available in the dump — only names, types, and offsets.

---

## Universal Structures

### `FLevelObjective` (per-objective data in every GameState)

| Field | Type | Offset | Description |
|-------|------|--------|-------------|
| `ObjectiveType` | `EObjectiveType` (enum) | 0x0000 | What kind of objective |
| `ObjectiveDescription` | `FText` | 0x0008 | UI description text |
| `ObjectiveAmount` | `int32` | 0x0018 | Target count (e.g. "collect 10 coins") |
| `ObjectiveContext` | `FGameplayTagContainer` | 0x0020 | Contextual tags |
| `bScalesWithPlayers` | `bool` | 0x0040 | **Whether this objective scales with player count** |
| `bDisplayAsPercentage` | `bool` | 0x0041 | Show progress as % |
| `ObjectiveProgress` | `int32` | 0x0044 | Current progress |
| `bIsComplete` | `bool` | 0x0048 | Whether done |

### `AMultiplayerGameState` (base class for ALL level GameStates)

| Field | Type | Offset | Description |
|-------|------|--------|-------------|
| `CurrentObjectives` | `TArray<FLevelObjective>` | 0x0450 | Array of active objectives |
| `CurrentLevelTag` | `FGameplayTag` | 0x0488 | Gameplay tag for current level |
| `EndingPathData` | `FBETEndingPathData` | 0x04D0 | Player-chosen route data |
| `ChunkManager` | `ABETChunkManagerBase*` | 0x0528 | Reference to level's chunk manager |
| `MatchState` | `FName` | 0x0428 | Current match state name |
| `JoinedPlayers` | `TArray<AActor*>` | 0x0378 | Players who have joined |

### `AElevator_Base` (base class for all elevators)

| Field | Type | Offset | Description |
|-------|------|--------|-------------|
| `PlayersInElevator` | `TArray<AActor*>` | varies | Players currently inside |
| `PlayersNeededToStartElevator` | `int32` | varies | How many players needed to depart |

### `AInteractableTeleporter` (teleporter pads)

| Field | Type | Offset | Description |
|-------|------|--------|-------------|
| `bRequiresAllPlayers` | `bool` | 0x2E0 | Requires everyone to stand on it |

### `ALevelExitBase` (level exit gates)

| Field | Type | Offset | Description |
|-------|------|--------|-------------|
| `bRequiresAllPlayers` | `bool` | 0x310 | Blocks progress until everyone present |

---

## Level 0 — Tutorial / Starting Level

### `ALevel0GameState` : `AMultiplayerGameState`
No extra fields. Minimal state — tutorial level.

### `ALevel0ChunkManager` : `ABETChunkManagerBase`
| Field | Type | Description |
|-------|------|-------------|
| `ElevatorShaftSkirt` | `UStaticMesh*` | Visual mesh for elevator shaft |

### `ALevel0Elevator` : `AElevator_Base`
Standard elevator with movement component, mesh, panel, and audio.

---

## Level 1 — Generator Level

### `ALevel1ChunkManager` : `ABETChunkManagerBase`

| Field | Type | Offset | Category | Our action |
|-------|------|--------|----------|------------|
| `NumberOfAlmondWater` | `int32` | 0x0760 | **Supply** | ✅ Scale up by `players/6` for >6 |
| `NumberOfGenerators` | `int32` | 0x0764 | **Requirement** | ✅ Cap at GENERATOR_CAP=10 |
| `NumberOfOfficeChunks` | `int32` | 0x0768 | Layout | — |
| `LightAmount` | `float` | 0x076C | Atmosphere | — |
| `MaxSkinStealers` | `int32` | 0x0770 | Monster | — |
| `NumberOfPuddles` | `int32` | 0x0774 | Hazard | — |
| `NumberOfBasementRooms` | `int32` | 0x077C | Layout | — |
| `HallwayRooms` | `int32` | 0x0780 | Layout | — |
| `HallwayLengthRange` | `FVector2D` | 0x0788 | Layout | — |

### `ALevel1GameState` : `AMultiplayerGameState`
No extra fields.

### `ALevel1Generator` : `ABETProceduralActor`
Generator object with mesh component. Count controlled by `NumberOfGenerators` above.

---

## Level 2 — Pipe/Valve Level

### `ALevel2GameState` : `AMultiplayerGameState`
No extra fields.

### `ALevel2HallwayManager` : `ABETHallwayManagerBase`

| Field | Type | Description |
|-------|------|-------------|
| `HallwayNumberRange` | `FIntPoint` | Range of hallway counts |
| `ImportantOffshootClass` | `TSubclassOf` | Key room class |
| `FillerOffshootClass` | `TSubclassOf` | Filler room class |

No player-scaled fields identified in dump.

---

## Level 3 — Fuse/Wire Repair Level

### `ALevel3ChunkManager` : `ABETChunkManagerBase`

| Field | Type | Offset | Category | Our action |
|-------|------|--------|----------|------------|
| `PlayerCountToWireCurve` | `UCurveFloat*` | 0x0800 | **Requirement (curve)** | Used by FuseBoard |
| `PlayerCountToRepairItemMultiplier` | `UCurveFloat*` | 0x0808 | **Supply (curve)** | ❓ Unclear direction |
| `SingleFuseLootboxWireSpawnCount` | `int32` | 0x0810 | **Supply** | ✅ Scale up by `players/6` |
| `SingleFuseLootboxTapeSpawnCount` | `int32` | 0x0814 | **Supply** | ✅ Scale up by `players/6` |
| `MultiFuseLootboxWireSpawnCount` | `int32` | 0x0818 | **Supply** | ✅ Scale up by `players/6` |
| `MultiFuseLootboxTapeSpawnCount` | `int32` | 0x081C | **Supply** | ✅ Scale up by `players/6` |
| `LootBoxSpawnRatio` | `float` | 0x0820 | Supply ratio | — |
| `MultiFuseBoxChance` | `float` | 0x0824 | Supply config | — |
| `NumberOfStaircases` | `int32` | 0x0828 | Layout | — |
| `MaxPartitions` | `int32` | 0x082C | Layout | — |
| `Sector1WallWireRepairCount` | `int32` | 0x0858 | **Requirement?** | ⚠️ Diagnostic only (uncertain) |
| `Sector2WallWireRepairCount` | `int32` | 0x085C | **Requirement?** | ⚠️ Diagnostic only (uncertain) |
| `Sector3WallWireRepairCount` | `int32` | 0x0860 | **Requirement?** | ⚠️ Diagnostic only (uncertain) |
| `RepairItemMultiplier` | `float` | 0x0864 | Supply multiplier | — |

### `AFuseBoard` : `ABETProceduralActor`

| Field | Type | Offset | Category | Our action |
|-------|------|--------|----------|------------|
| `PlayerCountFuseCurve` | `UCurveFloat*` | varies | **Requirement curve** | ✅ Read `GetFloatValue(6)` for cap |
| `RequiredFuseAmount` | `int32` | varies | **Requirement** | ✅ Cap to curve value (fallback 10) |

### `ALevel3GameState` : `AMultiplayerGameState`
No extra fields.

---

## Level 4 — Code Monitor Level

### `ALevel4PuzzleManager` : `ABETPuzzleManagerBase`

| Field | Type | Description |
|-------|------|-------------|
| `MonitorClass` | `TSubclassOf` | Code monitor actor class |
| `PuzzleMonitors` | `TArray<ALevel4CodeMonitor*>` | Active monitors |
| `KeypadClass` | `TSubclassOf` | Keypad class |
| `ClosedHallwayChunk` | `ULevel4ClosedHallwayChunk*` | Locked hallway |
| `L4ChunkManager` | `ALevel4ChunkManager*` | Chunk manager ref |

No player-scaled fields in dump. Puzzle manager uses `bScaleWithPlayers` on its parent `ABETPuzzleManagerBase` (if present).

### `ALevel4GameState` (not shown in search — likely minimal)
Known from earlier audit: `FacelingSpawnRateMultiplier` (fixed float). No player-scaled fields.

---

## Level 6 — Exhibition/Museum Level (BSP)

### `ALevel6ChunkManager` : `ABSPChunkManager`

| Field | Type | Description |
|-------|------|-------------|
| `VentDoorLocations` | `TArray<FIntVector>` | Vent door positions |
| `ClutterClasses` | `TArray<TSubclassOf>` | Clutter prefabs |
| `Sector1Chunks` | `TArray<UBETChunkBase*>` | Sector 1 chunks |
| `Sector2Chunks` | `TArray<UBETChunkBase*>` | Sector 2 chunks |
| `Sector3Chunks` | `TArray<UBETChunkBase*>` | Sector 3 chunks |
| `WireClass` | `TSubclassOf<APuzzleWire_Base>` | Wire puzzle class |
| `PuzzleManager` | `ALevel6PuzzleManager*` | Puzzle manager ref |

### `ALevel6PuzzleManager` : `ABETPuzzleManagerBase`

| Field | Type | Description |
|-------|------|-------------|
| `bScaleWithPlayers` | `bool` | **Explicitly scales with player count!** |
| `NumButtons` | `int32` | Number of sequence buttons |
| `HallucinationCount` | `int32` | Number of hallucination events |
| `SequenceButtons` | `TArray<ALevel6SequenceButton*>` | Active buttons |
| `Door` | `ALevel6PneumaticDoor*` | Puzzle door |

**Important:** `bScaleWithPlayers` is explicitly present on this puzzle manager. This is one of the few confirmed player-scaling fields outside Level 3/232.

### `ALevel6GameState` : `AMultiplayerGameState`
No extra fields.

---

## Level 37 — Water/Slide Level

### Classes Present
- `ALevel37PuzzleManager` with `PuzzleMonitors`, `Valves`, `Doors`, `AirlockButtons`
- `ALevel37WaterValve` with valve components
- `ALevel37WaterLever` with `ToggleOnCurve`, `ToggleOffCurve`, `ToggleResetCurve` (UCurveFloat)
- `ALevel37SlideActor` — slide/spiral geometry
- `ALevel37SlideStart` — tube spawn point

No ChunkManager or GameState with player-scaled fields identified.

---

## Level 232 — Supermarket/Store Level

### `ALevel232GameState` : `AMultiplayerGameState`

| Field | Type | Offset | Category | Our action |
|-------|------|--------|----------|------------|
| `RequiredQuota` | `float` | 0x05D0 | **Target amount** | — (read-only) |
| `ScaledPricePercent` | `float` | 0x05D4 | Global sell-price percentage multiplier | Scale up for >6 since v2.19.3; no-op at ≤6 |
| `SaleCatalog` | `TSoftObjectPtr<UBETStoreCatalog>` | 0x05F8 | Items players can sell | — |
| `PurchaseCatalog` | `TSoftObjectPtr<UBETStoreCatalog>` | 0x0620 | Items players can buy | — |
| `ItemsForSale` | `FLevel232ShopItemArray` | 0x0658 | Current sellable items | — |
| `ItemsForPurchase` | `FLevel232ShopItemArray` | 0x07A0 | Current purchasable items | — |
| `MaxNumberOfItemsForPurchase` | `int32` | 0x08E8 | Buy item cap | — |
| `HotCategoryMultiplierRange` | `FVector2D` | 0x08F0 | Hot item price multiplier | — |
| `FireSaleMultiplierRange` | `FVector2D` | 0x0900 | Fire sale price multiplier | — |
| `ColdItemMultiplier` | `float` | 0x0910 | Cold item price multiplier | — |
| `DayNightManager` | `ULevel232DayNightManager*` | 0x0918 | Day/night timer | — |
| `CurrentQuota` | `float` | 0x0920 | **Current earned amount** | — (read-only) |

### `FLevel232ShopItem` (per-item in sell/buy catalogs)

| Field | Type | Description |
|-------|------|-------------|
| `ItemDefinition` | `TSubclassOf<UBETInventoryItemDefinition>` | What item this is |
| `bIsGrabbable` | `bool` | Is it a grabbable object |
| `GrabbableItemClass` | `TSubclassOf<ABETGrabbableObject>` | Grabbable class |
| `CurrentValue` | `float` | **Current sell price** (changes with hot/cold/fire sale) |
| `BasePrice` | `float` | **Base sell price** |
| `bIsColdItem` | `bool` | Cold item flag |
| `bIsCategory` | `bool` | Is a category rather than single item |
| `CategoryTags` | `FGameplayTagContainer` | Category tags |
| `ItemStock` | `int32` | Stock count |

### `AALevel232CheckoutLane` : `ABETProceduralActor` (the checkout counter!)

| Field | Type | Offset | Description |
|-------|------|--------|-------------|
| `LaneMultiplier` | `float` | 0x0328 | This lane's price multiplier |
| **`CouponMultiplier`** | **`float`** | **0x0698** | **Coupon price multiplier!** |
| `CouponDuration` | `float` | 0x0678 | How long the coupon lasts |
| `CouponStartServerTime` | `float` | 0x06BC | When coupon started |
| `CouponExpiryServerTime` | `float` | 0x06C0 | When coupon expires |
| `SellDuration` | `float` | 0x0320 | Sell animation time |
| `SellableItemComponents` | `TArray<ULevel232SellableItemComponent*>` | 0x0730 | Items on belt |

Key methods:
- `ApplyCoupon(Instigator, InMultiplier)` — player activates coupon
- `SellItem(...)` / `SellGrabbableItem(...)` — execute sale
- `GetCouponMultiplier()` — get current coupon value
- `HasActiveCoupons()` — is coupon active?

### `ULevel232DayNightManager` : `UActorComponent`

| Field | Type | Description |
|-------|------|-------------|
| `TimeLimit` | `float` | Seconds per day |
| `DayAmount` | `int32` | Total number of days |
| `CurrentDayIndex` | `int32` | Current day number |
| `DayCycleWarningTime` | `float` | Warning before day ends |

### `ALevel232ChunkManager` : `ABETChunkManagerBase`

| Field | Type | Offset | Category | Our action |
|-------|------|--------|----------|------------|
| `ItemSpawnRates.PickupSpawnRange` | `FIntPoint` | 0x0B98 | **Supply** | ✅ Scale up by `players/6` |
| `ItemSpawnRates.GrabbableSpawnRange` | `FIntPoint` | 0x0BA0 | **Supply** | ✅ Scale up by `players/6` |
| `FacelingSpawnChunkInterval` | `int32` | 0x0BA8 | Monster spawn | — |
| `FacelingMarkerTargetCountPerChunk` | `int32` | 0x0BCC | Monster spawn | — |
| `NumGroceryStoreRobots` | `int32` | 0x0C40 | Enemy count | — |
| `ClusterAmount` | `int32` | 0x0774 | Layout | — |

### `ALevel232ShopActor` : `ABETProceduralActor` (vending machine to BUY items)

| Field | Type | Description |
|-------|------|-------------|
| `ShopMesh` | `UStaticMeshComponent*` | Machine mesh |
| `UpButtonClass/DownButtonClass/BuyButtonClass` | `TSubclassOf` | UI buttons |
| `PurchasedItem` | `ABETPickup*` | Last purchased item |
| `IndexState` | `FLevel232ShopIndexState` | Current item selection |
| `bIsOnCooldown` | `bool` | Purchase cooldown |

Key methods: `HandleBuyButtonPressed()`, `OnPurchaseSuccess(ItemIndex, Price)`, `OnPurchaseFailed(ItemIndex, Price, QuotaNeeded)`

### `ULevel232SellableItemComponent` : `UCapsuleComponent`

| Field | Type | Description |
|-------|------|-------------|
| `OwningCheckoutLane` | `TWeakObjectPtr<AALevel232CheckoutLane>` | Which lane |
| `OwningPlayer` | `ASurvivorCharacter*` | Who's selling |
| `ItemDefinition` | `TSubclassOf<UBETInventoryItemDefinition>` | What item |
| `bIsGrabbable` | `bool` | Is grabbable |
| `SellValue` | `float` | **How much this item sells for** |

### Gameplay Flow (Level 232)

1. **Day starts** → `DayNightManager` begins timer
2. **Items spawn** → `ItemSpawnRates` controls pickup/grabbable counts in chunks
3. **Players grab items** → free, stored in inventory
4. **Players sell at checkout** → `CheckoutLane.SellItem()` → adds to `GameState.CurrentQuota`
   - Sale price = `ShopItem.CurrentValue` × `LaneMultiplier` × `CouponMultiplier` (if active) × `ScaledPricePercent` (global)
   - "Hot" items get `HotCategoryMultiplierRange` multiplier
   - "Fire sale" items get `FireSaleMultiplierRange` multiplier
   - "Cold" items get `ColdItemMultiplier`
5. **Players can buy key items** → `ShopActor.HandleBuyButtonPressed()` → deducts from `CurrentQuota`
6. **Day ends** → if `CurrentQuota < RequiredQuota`, penalty applied
7. **All days complete** → level exit unlocks

### Price Calculation (reconstructed)

```
SellPrice = BasePrice
          × HotCategoryMultiplier  (if hot category)
          × ColdItemMultiplier     (if cold)
          × LaneMultiplier         (per checkout lane)
          × CouponMultiplier       (if coupon active on this lane)
          × ScaledPricePercent     (GameState global — player-count-related?)
```

**Key insight:** There are **multiple multipliers** in the chain. `ScaledPricePercent` is the global earned-percentage multiplier (confirmed by BET 0.14.6 patch notes), while `LaneMultiplier` and `CouponMultiplier` are per-lane links. v2.19.3 scales all three upward for >6 players from first observed runtime values.

---

## Level FUN — Warehouse/Arcade Level

### `ALevelFUNGameState` : `AMultiplayerGameState`

| Field | Type | Offset | Description |
|-------|------|--------|-------------|
| `TicketCount` | `int32` | 0x05E0 | Current tickets earned |
| `TicketCountMax` | `int32` | 0x05E4 | Maximum tickets (display cap) |

### `ALevelFUNChunkManager` : `ABETChunkManagerBase`

| Field | Type | Offset | Category | Our action |
|-------|------|--------|----------|------------|
| `WarehouseRequiredCoinsTotals` | `TArray<int32>` | 0x0750 | **Requirement** | ✅ Cap per element at 10 |
| `LockedDoorSpawnChance` | `float` | 0x0780 | Door config | — |
| `DoorCostRange` | `FIntPoint` | 0x0784 | Door cost range | — |
| `NumLanes` | `int32` | 0x0818 | Layout | — |
| `SideRoomChunkClasses` | `TArray<TSubclassOf>` | Layout | — |
| `MinigameModifiers` | `TArray<TSubclassOf>` | Minigames | — |

### `ALevelFunExitDoor` : `AInteractableDoor`

| Field | Type | Description |
|-------|------|-------------|
| `bTicketGoalCompleted` | `bool` | Whether ticket goal met |
| `RequiredTicketMilestone` | `int32` | Tickets needed to open |

### `ALevelFunExitPinger` : `ABETProceduralActor`

| Field | Type | Description |
|-------|------|-------------|
| `ItemAmountRequired` | `int32` | Items needed to activate |

### `APartyCelebrationSpeaker` : `AEnvSoundPlayer`

| Field | Type | Description |
|-------|------|-------------|
| `RequiredTicketMilestone` | `int32` | Ticket threshold |

### Gameplay Flow (Level FUN)

1. Players explore warehouse areas
2. Collect coins to open `LevelFunDoor`s (cost within `DoorCostRange`)
3. Each warehouse requires `WarehouseRequiredCoinsTotals[i]` coins
4. Tickets earned for milestones
5. `LevelFunExitDoor` opens when `RequiredTicketMilestone` reached
6. `LevelFunExitPinger` requires `ItemAmountRequired` items

---

## Level Hub — Central Hub / Level Select

### `ALevelHubGameState` : `AMultiplayerGameState`
No extra fields.

### `ALevelHubPuzzleChunkManager` : `ALevelHubChunkManager`

| Field | Type | Description |
|-------|------|-------------|
| `PartygoerSpawnChance` | `float` | Chance of partygoer spawn in puzzle area |
| `PuzzleManager` | `ALevelHubPuzzleManager*` | Crate puzzle manager |
| `AdditionalTunnelNum` | `FIntPoint` | Extra tunnels range |

### `ALevelHubExitDoor` : `ALevelExitBase`

| Field | Type | Description |
|-------|------|-------------|
| `bIsUnlocked` | `bool` | Whether this door is unlocked |
| `LevelDoor` | `TSoftObjectPtr<UBETLevel>` | Which level this door leads to |

---

## Level Neg1 — Basement / Shadow Level

### `ALevelNeg1Manager` : `ABETLevelManagerBase`

| Field | Type | Offset | Category | Our action |
|-------|------|--------|----------|------------|
| `MaxShadowSpawnAmount` | `int32` | 0x0320 | Monster cap | — (fixed ceiling) |
| `EntitySpawnChancePerPlayer` | `float` | 0x0324 | Monster difficulty | — (not capped) |
| `MinSpawnDistance` | `float` | 0x0328 | Spawn config | — |
| `MaxSpawnDistance` | `float` | 0x032C | Spawn config | — |
| `MinSurvivorClusterDistance` | `float` | 0x0330 | Spawn config | — |

### `ALevelNeg1ChunkManager` : `ABETChunkManagerBase`

| Field | Type | Description |
|-------|------|-------------|
| `LevelExitClass` | `TSubclassOf<AActor>` | Exit actor class |
| `StairWellDimensions` | `FIntVector` | Staircase size |
| `LightSwitchClass` | `TSubclassOf` | Light switch class |
| `DoorManager` | `ALevelNeg1DoorManager*` | Door manager |
| `BedroomManager` | `ALevelNeg1BedroomManager*` | Bedroom puzzle manager |
| `bBedroomsSolved` | `bool` | All bedrooms solved |
| `LootSpawnRatio` / `LootSpawnRatioMin` / `LootSpawnRatioMax` | `float` | Loot spawn rates |
| `RoomWidthRange` / `RoomLengthRange` | `FIntPoint` | Bedroom dimensions |
| `TutorialBedroomSpawnRange` | `FIntPoint` | Tutorial bedroom spawn range |

### Gameplay Flow (Level Neg1)

1. Players wake up in basement bedrooms
2. Must solve bedroom puzzles (light switches)
3. Shadow entities spawn with `EntitySpawnChancePerPlayer` chance per player, capped by `MaxShadowSpawnAmount`
4. `bBedroomsSolved` triggers level completion
5. Random door banging events via `ALevelNeg1Door.bIsBanging`

---

## Level Run — Chase Level

### `ALevelRunChunkManager` : `ABETChunkManagerBase`

| Field | Type | Description |
|-------|------|-------------|
| `LevelExitClass` | `TSubclassOf<AActor>` | Exit class |
| `InitialBreakingDoorsClass` | `TSubclassOf<AActor>` | Breaking door class |
| `SafeRoomEntryDoorClass` | `TSubclassOf<AActor>` | Safe room entry |
| `SafeRoomExitDoorClass` | `TSubclassOf<AActor>` | Safe room exit |

No player-scaled fields identified.

---

## Cross-Level Shared Actors

### `ACoinGate` : `ABETProceduralActor`

| Field | Type | Description |
|-------|------|-------------|
| `CoinsRequired` | `int32` | Coins needed to open |

### `AInteractableDoor` : `ABETProceduralActor`

| Field | Type | Description |
|-------|------|-------------|
| `ItemAmountRequired` | `int32` | Items needed to open |
| Plus inherited door state fields |

### `ARepairableElectricalBox` : `ABETProceduralActor`

| Field | Type | Description |
|-------|------|-------------|
| `RequiredFuseAmount` | `int32` | Fuses needed to repair |

### `AChristmasPresentQuestActor` : `ABETProceduralActor`

| Field | Type | Description |
|-------|------|-------------|
| `RequiredPresentsTags` | `FGameplayTagContainer` | Tag set, NOT a scalar int. Cannot cap via int path. |

---

## Inventory of All Mod Actions (v2.19.3)

| Target | Action | Trigger |
|--------|--------|---------|
| Lobby widget | Cap to 16 players | Widget hook |
| `AElevator_Base.PlayersNeededToStartElevator` | Cap at ≤6 | Scan + hooks |
| `Level1ChunkManager.NumberOfGenerators` | Cap at ≤10 | Scan + hooks |
| `FuseBoard.RequiredFuseAmount` | Cap at `GetFloatValue(6)` from `PlayerCountFuseCurve` | Curve read + hooks |
| `RepairableElectricalBox.RequiredFuseAmount` | Cap at ≤10 | Scan + hooks |
| `CoinGate.CoinsRequired` | Cap at ≤10 | Scan + hooks |
| `InteractableDoor.ItemAmountRequired` | Cap at ≤10 | Scan + hooks |
| `LevelFunExitDoor.RequiredTicketMilestone` | Cap at ≤10 | Scan + hooks |
| `LevelFunExitPinger.ItemAmountRequired` | Cap at ≤10 | Scan + hooks |
| `PartyCelebrationSpeaker.RequiredTicketMilestone` | Cap at ≤10 | Scan + hooks |
| `LevelFUNChunkManager.WarehouseRequiredCoinsTotals[]` | Cap each element at ≤10 | Int-array scan + hook |
| `FLevelObjective.ObjectiveAmount` (where `bScalesWithPlayers=true`) | Cap at ≤10 | GameState array scan |
| `bRequiresAllPlayers` on teleporters/exits | Force false when >6 players | Scan + hooks |
| `Level232GameState.ScaledPricePercent` | Read-only diagnostic | Log once |
| `Level1ChunkManager.NumberOfAlmondWater` | Scale up by `players/6` | Supply scan |
| `Level3ChunkManager` lootbox wire/tape counts | Scale up by `players/6` | Supply scan |
| `Level232ChunkManager.ItemSpawnRates` ranges | Scale up by `players/6` | Supply scan |
| Self pawn collision (Ctrl+N) | Toggle on/off | Keybind |
