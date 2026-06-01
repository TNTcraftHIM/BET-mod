# BET Level / Spawn Structure (read-only investigation, 2026-05-31)

> **Historical research note.** This file preserves investigation details from development. It is not required for normal installation or use, and some hypotheses/keybinds may be superseded by the root README and changelog.


All findings via read-only string extraction from game files. No game files modified.

## Levels

13 main-level `.umap` files, path pattern `/Game/Maps/MainLevels/Level_<N>/L_Level_<N>`
(umaps live in `pakchunk10-Windows.utoc`; asset table in `pakchunk0-Windows.utoc`):

| Map (umap)          | GameMode class                |
|---------------------|-------------------------------|
| `L_Level_Neg1`      | `BP_LevelNeg1GameMode_C`      |
| `L_Level_0`         | `BP_Level0GameMode_C`         |
| `L_Level_1`         | `BP_Level1_GameMode_C`        |
| `L_Level_2`         | `BP_Level2GameMode_C`         |
| `L_Level_3`         | `BP_Level3GameMode_C`         |
| `L_Level_4`         | `BP_Level4GameMode_C`         |
| `L_Level_6`         | `BP_Level6GameMode_C`         |
| `L_Level_37`        | `BP_Level37GameMode_C`        |
| `L_Level_232`       | `BP_Level232GameMode_C`       |
| `L_Level_FUN`       | `BP_LevelFUNGameMode_C`       |
| `L_Level_Hub`       | `BP_LevelHubGameMode_C`       |
| `L_Level_HubPuzzle` | `BP_LevelHubPuzzleGameMode_C` |
| `L_Level_Run`       | `BP_LevelRunGameMode_C`       |

Menu/system maps: `/Game/Maps/BR_MainMenu/L_Startup` and `.../BR_MainMenu`
(both `BP_LobbyGameMode_C`), plus `/Game/Maps/MiscMaps/TransitionMap` (seamless-travel).
All gamemodes derive from C++ base `BETGameModeBase`. Each level also has a matching
`GameState` and usually a `ChunkManager` + `Manager` + `PuzzleManager`.

Level transitions use SeamlessTravel (observed in BET.log for lobby -> L_Level_0 -> return).

## Spawn / PlayerStart

Spawn class is a custom C++ `BETPlayerStart` (subclass of `APlayerStart`), spawned at
runtime by the PCG (procedural generation) system. PlayerStarts are differentiated by a
runtime `Suffix` string, NOT by separate classes. Suffixes seen in Level_0 logs and their
PlayerStart-frame Z:

- `Level0Checkpoint` — Z = -8400 (elevator-arrival 3x3 grid, X/Y in {-333,0,333})
- `Neg1PlayerStart` — Z = -7900 and -8300 (basement bedroom grid, X≈-13650..-14550)
- `Neg1EntranceDoor` — Z = -8400

So within a single world, multiple PlayerStart groups coexist at different Z bands. This
is geometry-driven (basement vs. elevator shaft), NOT a universal "Z = level index" scheme.

IMPORTANT caveat: the PlayerStart frame (Z≈-8400) differs from the runtime pawn frame
(correct players settle at Z≈98) by a ~+8500 offset. **Absolute-Z thresholds are invalid;
detection must be relative / outlier-based, or anchored to a live actor.**

Player pawn: `BP_SurvivorCharacter` (controller `BP_SurvivorPlayerController`, state
`BP_SurvivorPlayerState`); spectator: `BP_BETSpectatorPawn`.

Engine spawn machinery (in exe): `AssignPlayerStartsToLocations`, `ChoosePlayerStart`,
`FindPlayerStart`, `RestartPlayerAtPlayerStart`, `PlayerStartTag`.

## Elevator actors

The elevator is the spawn mechanism (players spawn inside, it descends as a cutscene),
not just decoration. Per-level variants — there is NO generic base class:

- `BP_ElevatorFinal` — base / Level0 elevator
- `BP_ElevatorFinal_Level2` — Level 2 variant
- `BP_Elevator_Level4` — Level 4 variant
- `BP_ElevatorPanel`, `BP_Level2ElevatorPanel` — interaction panels

Elevator exposes properties `PlayersInElevator`, `PlayersNeededToStartElevator`, method
`StartElevator`. Because the class name varies per level and some levels (Hub/Run/232/FUN)
may not use an elevator at all, the elevator is NOT a clean level-independent anchor.

## Assessment: most level-independent anchor

1. **Host pawn cluster (best).** The host (listen server) always rides the normal spawn
   path. Anchor on the host pawn's live position (or the majority-cluster centroid) and
   flag pawns far from it. Fully class- and level-independent; sidesteps the +8500 frame
   offset. **This is what v2.5 implements.**
2. **Elevator actor (partial).** Canonical spawn origin but class name varies and not every
   level has one. Usable as a secondary anchor only where present (match name-contains
   "Elevator").
3. **Checkpoint/PlayerStart (weakest).** `BETPlayerStart` is universal as a class, but the
   meaningful grouping is in the runtime-only `Suffix` string (per-level named), and the
   PlayerStart frame differs from the runtime pawn frame — poor live reference.

Recommendation (implemented v2.5): detect misspawns by relative clustering of pawn world
locations, teleport outliers to the HOST pawn position; provide a host keybind to gather
all players on demand. No per-level constants, no class-name table, no absolute-Z.

## Level PROGRESSION model — NOT a numeric order (verified 2026-05-31)

Confirmed from the game's own class dump (`BET/Binaries/Win64/ue4ss/CXXHeaderDump/
BETGame.hpp`) that BET has **no fixed numeric level sequence**. Progression is a
runtime, branching, player-chosen **"ending path"**:

- `ALevelExitBase.NextLevel : TSoftObjectPtr<UBETLevel>` — each level EXIT actor points
  to a next-level data asset. The "next level" is a graph edge baked into the exit, not
  `L_Level_<N+1>`.
- `UBETGameInstance`: `ExpandLevelTree(out levels)`, `GetCachedLevels() : TMap<
  FGameplayTag, UBETLevel>` (levels keyed by **GameplayTag**, not index), `AdvanceLevel(
  level)`, `BETServerTravel(level)`, plus `StartLevel` / `EndLevel` anchors.
- `UBETLevelOptions.Levels : TMap<UBETLevel, float>` — a **weighted pool** of candidate
  next levels (random/weighted selection).
- `UEndingPathBoardWidget.SelectLevel(...)` / `OnLevelSelected`, and
  `FBETEndingPathData.VisitedLevels` (+ `FBETEndingPathNetState`) — players literally
  **pick** their next level on a board, and the game records the route taken per match.
- `UStateTreeTask_SelectLevel` — selection is driven by a StateTree task.

Gameplay tags actually present (string-extracted from `pakchunk*-Windows.ucas`):
`Level.Neg1, Level.0, Level.1, Level.2, Level.3, Level.4, Level.6, Level.37, Level.232,
Level.Fun, Level.Hub, Level.HubPuzzle, Level.Run, Level.Menu`. Level data assets seen:
`DA_Level_0/3/4/37/FUN/Hub/HubPuzzle/Menu` (others compressed). The real `StartLevel` is
**Level 0** (the Lobby), confirmed by community guides; Neg1 is a sub-area reached within
a level, not "level −1 in a line".

**Implication for the mod's Ctrl+H jumper:** the old Neg1→0→1→…→Run cycle was an
ARBITRARY file-order traversal, never the canonical flow. Harmless for a *test* jumper
(every `L_Level_*` path is a valid, servertravel-reachable map — all 14 confirmed present
in the ucas), but it does NOT represent how players actually move between levels, and it
bypasses the lobby start + elevator + ending-path board so OBJECTIVES won't initialize.
v2.7 relabels the list as a "test traversal" (Level 0 first) and documents this honestly.
A *faithful* in-game advance would call `AdvanceLevel` / `BETServerTravel(UBETLevel)` with
the level's data asset, or drive the ending-path board — deferred (not needed for spawn
testing). The edges themselves (which `NextLevel` each exit points to) live inside
compressed data assets and can't be read by string extraction — would need FModel/asset
parsing to map the full graph.
