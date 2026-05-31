# Changelog

All notable changes to the BETPlayerCap UE4SS mod and the surrounding research workspace.

## v2.7-levelorder (2026-05-31)

### Level order is NOT numeric — corrected the Ctrl+H test jumper's framing

Investigated the user's concern that a Backrooms game's level order isn't `0→1→2→…`.
Confirmed from the game's OWN class dump (`ue4ss/CXXHeaderDump/BETGame.hpp`, read-only)
that **BET has no fixed numeric sequence** — progression is a runtime, branching,
player-chosen **"ending path"**:

- `ALevelExitBase.NextLevel : TSoftObjectPtr<UBETLevel>` — each level EXIT carries its own
  pointer to the next-level data asset (a graph edge, not `L_Level_<N+1>`).
- `UBETGameInstance.GetCachedLevels() : TMap<FGameplayTag, UBETLevel>` — levels keyed by
  **GameplayTag**, plus `ExpandLevelTree`, `AdvanceLevel`, `BETServerTravel`, `StartLevel`/
  `EndLevel`.
- `UBETLevelOptions.Levels : TMap<UBETLevel, float>` — a **weighted pool** of next-level
  candidates.
- `UEndingPathBoardWidget.SelectLevel` + `FBETEndingPathData.VisitedLevels` /
  `UStateTreeTask_SelectLevel` — players literally **pick** their next level on a board;
  the game records the route per match.

String-extracted from the paks: tags `Level.Neg1/0/1/2/3/4/6/37/232/Fun/Hub/HubPuzzle/Run/
Menu`; the real `StartLevel` is **Level 0** (the Lobby). Neg1 is a sub-area within a level,
not "−1 in a line".

Changes in `main.lua`:

- **`LEVEL_MAPS` relabeled as a TEST TRAVERSAL, not canonical order.** Reordered to put
  **Level 0 first** (the real StartLevel); added the previously-missing entry is N/A (232
  was already present); list is now 0,1,2,3,4,6,37,232,FUN,Run,Hub,Neg1. All 14 `L_Level_*`
  map paths re-confirmed present in `pakchunk*-Windows.ucas`.
- **`LEVEL_GM_BY_INDEX` reordered to stay parallel** with `LEVEL_MAPS` (so "detect current
  level, step to next" still maps correctly).
- Extensive in-code comment block documenting the ending-path model and that Ctrl+H is a
  SPAWN/travel test aid that bypasses the lobby/elevator/ending-path (objectives won't init).
- No behavior change to the spawn fix or Ctrl+G summon. Full detail in
  `docs/level_structure.md` (new "Level PROGRESSION model" section).

Deferred: a *faithful* in-game advance (call `AdvanceLevel`/`BETServerTravel(UBETLevel)` or
drive the ending-path board) and mapping the actual exit→NextLevel graph edges (they live
in compressed data assets; need FModel/asset parsing). Not required for spawn testing.

## v2.6-levelswitch (2026-05-31)

### Test tooling: one-key level switch + clarified summon availability

- **New host keybind Ctrl+H = "cycle to next level"** (test aid). Uses
  `servertravel <map>?listen` — the same seamless `ProcessServerTravel` mechanism
  BET itself uses (confirmed in BET.log), so all connected clients are carried
  along and nobody is dropped. Detects the current level from its live GameMode
  instance and advances to the next in the canonical order
  (Neg1→0→1→2→3→4→6→37→232→FUN→Hub→Run→wrap). Map paths follow the confirmed
  `/Game/Maps/MainLevels/Level_<N>/L_Level_<N>` pattern.
- **Auto-bring + summon on arrival**: after a Ctrl+H switch, the mod re-arms its
  per-level state and, a couple of ticks after the new level is detected (pawns
  possessed + settled), runs a one-shot `summon_all_to_host` so everyone ends up
  together at the new spawn. Console-command travel with a KismetSystemLibrary
  fallback (`StaticFindObject` of the CDO — confirmed available via other shipped mods).
- Caveat documented in-code: jumping straight to a level bypasses the lobby start
  and elevator progression, so level OBJECTIVES may not initialize. This is a
  SPAWN/travel test aid, not a way to play through normally.

### Summon availability (clarification, no behavior change from v2.5)

- The **automatic** spawn fix is **spawn-time-only** (gated to `FIX_MAX_TICKS` after
  level load, then self-disables) so it never rubber-bands a player who walks into
  Neg1 on purpose later.
- The **Ctrl+G "Summon All"** keybind has **no time gate** — usable **anytime** for
  the whole session, repeatable. It is the manual escape hatch.

## v2.5-host-anchor (2026-05-31)

### Level-INDEPENDENT spawn gathering: host anchor + host summon keybind

v2.4's cluster-fix was confirmed working in a live 7-player test (the wrong-floor
player was teleported up to the group, verified). But Z-axis clustering is specific
to level-0 geometry — later levels may not separate floors by Z. This release makes
the system level-independent. Design backed by multi-agent research (REPO `/sa`,
Lethal Company, Content Warning all use the same pattern) and confirmed against the
shipped `SplitScreenMod` on this exact build (it uses `RegisterKeyBind` + pawn teleport).

Changes in `main.lua`:

- **Anchor switched from cluster median to the HOST pawn's live position.** The host
  is the listen-server authority and always spawns with the group on any level,
  standing in valid walkable geometry — a level-independent gather target with no
  coordinate assumptions. Resolved via `UEHelpers.GetPlayerController().Pawn`,
  re-read every time (never cached; pawns are recreated across travel).
- **Host-is-outlier fallback**: if the host pawn isn't in the majority cluster (or
  can't be resolved / UEHelpers missing), fall back to the cluster median so we never
  gather everyone onto a misplaced host.
- **New host "Summon All" keybind: Ctrl+G.** Manual, host-only (only the host runs the
  mod), one-shot per press. Gathers every other possessed player to the host in a ring.
  This is the escape hatch for ANY separation on ANY future level, independent of
  whether auto-clustering classifies correctly. Registered once a real level is detected.
- **Fixed the teleport flag**: writes now use `bTeleport=true` (`K2_SetActorLocation(...,
  true)` / `K2_TeleportTo`) so clients SNAP instead of interpolating/sweeping across the
  map. v2.4 incorrectly used `bTeleport=false`.
- **Ring spread + `+50` Z lift**: outliers/summoned players fan out in a 150u ring around
  the anchor and are lifted slightly so they settle onto the floor instead of stacking
  (telefrag) or clipping into geometry. Replaces the old grid offset.
- **`ForceNetUpdate()`** after each teleport to push the corrected position to clients.
- Shared `teleport_pawn()` / `ring_dest()` used by both the auto-fix and the keybind.
- Collision-toggle (`SetActorEnableCollision`) deliberately NOT used — unverified on this
  build and the ring+lift avoids stacking without it. Documented as a last-resort fallback.

Confirmed primitives on this build (so the design rests on observed facts, not theory):
- `K2_GetActorLocation` reads in-level — confirmed v2.4 test.
- `K2_SetActorLocation` writes AND replicates to remote clients — confirmed v2.4 test
  (the wrong-floor player was actually moved and the move verified).
- `RegisterKeyBind` + modifier + pawn teleport — confirmed by shipped `SplitScreenMod`.

Still unverified (next live test must confirm): the Ctrl+G keybind firing in-game, and
that summoned remote clients visually snap cleanly. Watch `[SUMMON]` and `[SPAWN]` lines.

## v2.4-cluster-fix (2026-05-31)

### Spawn fix: RE-ENABLED with relative cluster-outlier detection

Context: a clean 7-player test (no late-join, all 7 in the lobby before start) produced
the first genuine in-level diagnostic capture. Findings:

- Normal players spawn inside an **elevator** that descends as a cutscene to the real
  spawn point. In the DIAG log they read Z≈7486 (mid-cutscene), then settle together at
  Z≈98.
- Exactly one player was dropped directly onto a **Neg1 (basement) bedroom PlayerStart**
  (Z≈-7900) and never rode the elevator — that is the wrong-floor player.
- The **runtime coordinate frame differs from the PlayerStart frame** (~+8500 offset):
  correctly-placed players are at Z≈98 at runtime, not their PlayerStart's Z=-8400.

Consequence: the old **absolute-Z threshold (-8150) is invalid** — it labels every real
player as "wrong floor" and discriminates nothing. (Adversarially verified, high
confidence, survived refutation.)

### What changed in `main.lua`

- Replaced absolute-Z spawn detection with **relative clustering**: collect all
  possessed in-level characters, take the median Z, and flag anyone more than
  `CLUSTER_GAP` (2500u) from the median as an outlier. Intra-floor jitter is ~100s of
  units; the inter-floor gap is ~8000u, so the separation is unambiguous.
- Teleport target = the **majority cluster's median runtime position** (NOT a PlayerStart
  constant — the frame offset would send players to the wrong place).
- **Settling gate**: median Z must be stable across two consecutive reads before acting,
  so we never teleport players mid-elevator-cutscene.
- **Spawn-time-only window** (`FIX_MAX_TICKS`): only attempt the fix shortly after level
  detection. Neg1 is a legitimately explorable area later, so after the window we leave
  positions alone — no rubber-banding of players who descend on purpose.
- **Write verification**: after each teleport, re-read the actor's position and log
  whether it actually moved (`K2_SetActorLocation`/`K2_TeleportTo` writes were historically
  unverified on this build). Retries next tick if a write fails.
- `collect_players()` gates on **possession** (Controller present) to exclude
  lobby/CDO/spectator pawns; drops garbage reads (Z==0 sentinels, unreadable).
- Phase-4 diagnostics now report each player's Z plus signed distance from the group
  median and a `cluster(ok)` / `OUTLIER(wrong-floor?)` tag (replacing the meaningless
  absolute-threshold label).
- Avoided Lua 5.4-only `//` operator in favor of `math.floor` for version safety.

### Safety caveats respected (from adversarial refutation)

1. Spawn-time only, never continuous.
2. Target is cluster median, never a PlayerStart constant.
3. Writes are verified after the fact.
4. Late-joiners/spectators are never teleported.
5. Keys on spatial outlier, not slot index (`Player#7` was just enumeration order).

## v2.3-diag-names (2026-05-31)

- Added `get_player_name()` (Character → Controller → PlayerState) so diagnostics name
  WHO is on the wrong floor.
- Phase-4 diagnostics log per-player name + Z + floor classification.
- PlayerStart scan retries each tick until it succeeds (`scan_done`).

## v2.2-cdofix (2026-05-31)

- Fixed a **CDO false-positive bug**: `FindFirstOf`/`FindAllOf` return `Default__<Class>`
  Class Default Objects that exist in memory even in the lobby, so level detection fired
  in the menu and all "in-level" diagnostics were actually collected in the lobby.
- Added `is_real_instance()` (rejects `Default__` names + `IsValid()` check),
  `find_first_instance()`, and `in_gameplay_level()` (uses only gameplay-specific
  GameMode classes / a possessed Survivor character).
- All `FindAllOf` loops now guard each item with `is_real_instance`.

## v2.1-adaptive (2026-05-31)

- **Removed `net.MaxPlayersOverride`**: it also sets `AGameSession.MaxPlayers` and was
  implicated in wrong-floor spawn assignment. The 12-slot session cap comes from the
  OSS/widget `MaxPlayers` and survives without the console command (verified:
  `NumPublicConnections: 12` in BET.log with no override).
- Widget override (`MaxSelectablePlayers`/`DefaultMaxPlayers`/`SelectedMaxPlayers`)
  remains the active cap-raising mechanism.

## v2.0-adaptive (2026-05-31)

- Adaptive class-name resolution (exact names with parent-class fallbacks).
- 5-method position reader (GetActorLocation → K2_GetActorLocation →
  RootComponent.RelativeLocation → RootComponent.X/Y/Z → GetTransform().Translation),
  locking the first that works.
