# Changelog

All notable changes to the BETPlayerCap UE4SS mod and the surrounding research workspace.

> Current install/use instructions are in `README.md` and `docs/USER_GUIDE.md`.
> Older entries preserve development history and may mention superseded keybinds or
> hypotheses.

## v2.19.5 (2026-06-07)

- **Fix (audit follow-up): supply scaling could compound on a re-detect.** v2.19.4's
  `reset_per_level_state()` cleared `supply_scaled_original` (the per-object
  first-observed base map). If a re-detect fired while the supply objects still
  held an already-scaled value, the next pass re-captured that scaled value as the
  new base and scaled it again — compounding toward factor² (e.g. 1.33× → 1.77×).
  The reset no longer clears that map; the first-observed base is preserved across
  re-detects, keeping supply scaling idempotent. The log-dedup maps
  (`objective_cap_changed`, `s232_price_logged`, `l6_scale_logged`) are still
  cleared so a re-detected level re-logs its caps. No change to the second-run
  cap-reapply fix from v2.19.4. Found by a full adversarial code+docs audit.
- **Docs/comments:** corrected the `S232_PRICE_CLASSES` comment (it scales prices
  *up* for >6, not "prevents too cheap"); fixed the `game_mechanics_reference.md`
  action inventory (ScaledPricePercent is actively scaled, not read-only; added the
  `LaneMultiplier` / `CouponMultiplier` rows); noted that `S232_PRICE_FLOOR` was
  superseded in v2.19.3 in the historical v2.17.0 entry.

## v2.19.4 (2026-06-07)

- **Fix: caps now re-apply on a second playthrough.** `level_detected` previously
  latched `true` on the first gameplay level and was reset only by the mod's own
  Ctrl+K/L/J handlers, so a game-driven transition (finishing a level through the
  in-game elevator, returning to the lobby, or starting a fresh run from a cleared
  save) never re-ran the immediate full cap/scale pass and kept stale per-level
  bases. The monitor now watches the live world name and calls a new
  `reset_per_level_state()` on any change, which re-arms detection and clears
  `supply_scaled_original` / `objective_cap_changed` / `objective_cap_hook_fired`
  / `s232_price_logged` / `l6_scale_logged`. The reset only ever forces
  re-application; it never removes a cap. See `docs/research/known_issues.md`.

## v2.19.3 (2026-06-07)

- **Hotfix: Ctrl+G never gathers monsters.** `collect_players()` now uses exact
  survivor pawn classes only and requires a valid `Controller -> PlayerState`
  chain before any actor is eligible for Ctrl+G, spawn-fix, elevator boarding, or
  player-count-sensitive caps. It no longer depends on the generic `Character`
  fallback that could include AI/monster pawns.
- **Hotfix: Level 232 income scaling.** BET 0.14.6 confirms Level 232 price
  scaling is an earned-percentage mechanic. For >6 players, the mod now scales
  `Level232GameState.ScaledPricePercent` upward from its first observed runtime
  value in addition to the checkout-lane `LaneMultiplier` / `CouponMultiplier`
  links. All of this remains a no-op at ≤6 players.
- **Local dump management.** Added ignored `local_dumps/` / UE4SS dump patterns so
  updated game dumps can be kept versioned locally for audits without syncing
  generated SDK/object dumps into git or release packages.

## v2.19.2 (2026-06-07)

- **Code audit cleanup.** Removed unused/stale implementation scaffolding that no
  longer participates in the current host-anchor spawn fix or objective/supply cap
  paths: the old PlayerStart fallback scan state, the unused one-object elevator cap
  wrapper, the unused Level 232 `ScaledPricePercent` props table, and the disabled
  Level 3 wire-cap placeholder table. The Level 3 wire decision remains documented
  as "do not cap until live testing proves it is a requirement."
- **Safer diagnostics and gate scans.** Direct `collect_players()` consumers in the
  all-players gate scan and elevator probe now fall back to an empty table if the
  forward-declared collector is not available yet, matching the defensive style used
  by `effective_player_count()`.
- **Level 232 side-effect accounting.** `cap_s232_price()` still leaves
  `ScaledPricePercent` read-only, but now returns the number of successfully scaled
  `CouponMultiplier` / `LaneMultiplier` writes instead of always returning `0`.
- **Log/doc consistency.** Startup logging now correctly says Ctrl+K/L previous/next
  level keybinds are enabled by default, matching the current release config.

## v2.19.1 (2026-06-04)

- **Bugfix: Level 6 puzzle scale guard.** `cap_level6_puzzle_scale()` previously
  forced `bScaleWithPlayers=false` unconditionally, which could make the museum
  puzzle easier than intended at ≤6 players (where scale is normal difficulty).
  Now guarded with `effective_player_count() > ALL_PLAYERS_GATE_CAP` — only
  disables scaling when >6 possessed, matching every other cap function.

## v2.19.1-comprehensive-scaling (2026-06-04)

### Full-level audit pass — every level checked against dump, new caps & supplies

After a line-by-line read of all 13 level ChunkManagers and GameStates from
`BETGame.hpp` (documented in `docs/research/game_mechanics_reference.md`),
this version adds level-specific caps and supply scaling where the dump
exposes player-count fields.

**New difficulty caps (keep ≤6-player difficulty):**
- **Level 6 `ALevel6PuzzleManager.bScaleWithPlayers`** forced to false when >6
  possessed. This puzzle explicitly scales with player count (more buttons /
  harder sequence); preventing the scale-up keeps the museum puzzle at ≤6
  difficulty. Also logs `NumButtons` for diagnostics.

**New supply scaling (scale UP for >6 players):**
- **Level 3 `RepairItemMultiplier`**: repair-item spawn multiplier now scaled up
  by `players/6` (more repair materials for larger groups).
- **Level Neg1 `LootSpawnRatio`**: loot density ratio now scaled up by
  `players/6` (more items to find in basement bedrooms).
- **Level 232 `AALevel232CheckoutLane.CouponMultiplier`**: per-checkout-lane
  coupon price multiplier now scaled up by `players/6`. Higher coupon = items
  sell for more money = quota easier to meet.
- **Level 232 `AALevel232CheckoutLane.LaneMultiplier`**: per-lane base price
  multiplier also scaled up for larger groups.

**Expanded Level 232 diagnostics:**
- First detection now logs the full price chain: `ScaledPricePercent`,
  `RequiredQuota`, `CurrentQuota`, `MaxNumberOfItemsForPurchase`, and
  `ColdItemMultiplier`. This will reveal whether `RequiredQuota` itself scales
  with player count (couldn't determine from the dump).

**Level 232 full price-chain analysis** (documented in game_mechanics_reference):
```
SellPrice = BasePrice × HotCategoryMultiplier × ColdItemMultiplier
          × LaneMultiplier × CouponMultiplier × ScaledPricePercent
```
We now scale the `LaneMultiplier` and `CouponMultiplier` links in this chain;
`ScaledPricePercent` remains read-only pending live ≥7-player observation.

**Comprehensive mechanics reference:**
- `docs/research/game_mechanics_reference.md`: all gameplay-relevant fields
  from every LevelNChunkManager, GameState, and key actor in `BETGame.hpp`,
  with offsets, types, categories (requirement/supply/monster/layout), and
  current mod actions.

---

## v2.18.0-dynamic-six-player-baseline (2026-06-04)

### Stop using one universal "10" for everything; add supply scaling for larger groups

Follow-up audit conclusion: `GENERIC_OBJECTIVE_CAP=10` was a practical placeholder,
not a verified 6-player value for every objective. The dump exposes fields and curve
pointers, but not Blueprint defaults or `UCurveFloat` key data, so exact authored
6-player values require runtime reads. v2.18 switches the parts that *can* be read at
runtime to dynamic baselines and keeps static caps only where no curve/value source is
available yet.

- **Curve-backed requirements now use the actual 6-player curve value** where available.
  `FuseBoard.RequiredFuseAmount` is capped to `FuseBoard.PlayerCountFuseCurve:GetFloatValue(6)`,
  rounded up, instead of blindly using 10. If the curve cannot be read, it falls back to
  `GENERIC_OBJECTIVE_CAP=10` and logs through the normal `[OBJCAP]` path.
- **Supply/resource fields now scale UP for >6 players** instead of being capped down.
  When possessed players > `SUPPLY_BASE_PLAYERS=6`, confirmed supply fields are multiplied
  by `players / 6` from their first observed runtime value (so the 10s monitor cannot
  repeatedly multiply them):
  - Level 1 `NumberOfAlmondWater`
  - Level 3 lootbox wire/tape counts (`SingleFuseLootbox*`, `MultiFuseLootbox*`)
  - Level 232 `ItemSpawnRates.PickupSpawnRange` / `GrabbableSpawnRange`
- **Level 232 `ScaledPricePercent` is not modified.** The dump cannot prove the
  authored 6-player value or direction; changing it blindly risks making the quota
  harder. Level 232 instead gets easier via the existing `ItemSpawnRates` supply
  scaling (more items to sell = more money). The function logs the current value
  once for future diagnostics. This may be revisited once live ≥7-player values
  are observed.
- **Level 3 wire requirements remain diagnostic/off by default.** The dump shows
  `PlayerCountToWireCurve` and sector wire repair counts, but cannot prove whether those
  counts represent required repairs versus available repairable wires. Do not cap them
  until a live run confirms they are requirements, not supply.
- **Still NOT supply-scaled by default (v2.18; updated in v2.19):** monster difficulty fields. Level Neg1 `LootSpawnRatio`, Level 3 `RepairItemMultiplier`, and Level 232 `CouponMultiplier`/`LaneMultiplier` added to supply scaling in v2.19.
- **Optional local self no-collision toggle:** `Ctrl+N` toggles collision on the
  installed player's own pawn. This is intentionally local-only for clients who choose
  to install the mod too; it does not scan or modify monster actors or other players.
- **Keybind sanity check:** current active shortcuts are `Ctrl+G` gather, `Ctrl+J` reload,
  `Ctrl+K/L` previous/next level, `Ctrl+O` probe, `Ctrl+P` board elevator,
  `Ctrl+Arrows`/`Ctrl+PageUp/PageDown` host nudge, and `Ctrl+N` self no-collision.

## v2.17.1-requirement-audit (2026-06-04)

### Tighten the requirement-vs-supply split after a full dump re-audit

A line-by-line re-read of `BETGame.hpp` / `UE4SS_ObjectDump.txt` confirmed which
player-scaled fields are *requirements* (cap them down) versus *supply/spawns* (must
NOT be capped, or larger groups get less) versus *monster difficulty* (out of scope
for the objective cap). See `docs/research/full_player_scaling_audit.md`.

- **Level FUN warehouse coins**: `LevelFUNChunkManager.WarehouseRequiredCoinsTotals`
  (`TArray<int32>`) is a requirement total per warehouse. Added a real int-array
  capper (`cap_int_array_prop` / `cap_int_array_requirements`) that clamps each
  element to `GENERIC_OBJECTIVE_CAP=10`, wired into startup/level-detect/monitor and
  a hook on `AddWarehouseRequiredCoins`. (Previously the table existed but was never
  executed.) **Live TArray mutation still needs a ≥7-player Level FUN confirmation.**
- **`PartyCelebrationSpeaker.RequiredTicketMilestone`** added to the numeric cap list
  (≤10) — it is a ticket-goal gate like `LevelFunExitDoor`.
- **`ChristmasPresentQuestActor` corrected**: `RequiredPresentsTags` is an
  `FGameplayTagContainer`, not an int array, so the scalar cap never applied to it.
  Removed it from `NUMERIC_CAP_CLASSES` rather than leave a no-op that the docs
  claimed was active. The generic `CurrentObjectives` path still covers it if the
  game publishes a scaled objective.
- **All-player gates now event-driven**: added hooks on `LevelExitBase:OnSurvivorOverlap`,
  `LevelExitBase:OnAllPlayersPresent`, and `InteractableTeleporter:OnActivationStateChange`/
  `AreAllPlayersPresent` so `bRequiresAllPlayers` is re-disabled immediately, not just
  by the 10s monitor scan. (Docs previously claimed these hooks existed; now they do.)
- **Level 232 price floor raised `0.50` → `1.00`**: strict "more players is never
  harder" policy — player count can no longer discount sell prices at all. The dump
  has no authored 6-player `ScaledPricePercent` value to match, so 1.00 is the safe
  no-harder choice until live logging proves a lower vanilla floor.
- **Removed a duplicate** `Elevator_Base:CheckForPlayersInElevator` hook registration.
- **Explicitly NOT capped** (confirmed supply/difficulty, not requirements): Level 3
  `PlayerCountToWireCurve`/`PlayerCountToRepairItemMultiplier`/lootbox wire+tape spawn
  counts, Level 232 `ItemSpawnRates`, Level 1 almond water, and all monster spawn
  fields (skin stealers, facelings, partygoers, Level -1 shadow chance). Capping these
  would make larger groups *harder*, the opposite of the goal.

## v2.17.0-generic-cap (2026-06-04)

### Comprehensive player-scaling cap across all levels

Design principle: **same difficulty as ≤6 players, just with up to 16 people.**

- **"All players" gates** (`bRequiresAllPlayers` on `AInteractableTeleporter` and
  `ALevelExitBase`): when possessed players > 6, force the boolean false so a 7–16
  player group is not blocked by geometry built for ≤6. Re-asserted via the periodic
  scan and also post-hook on `OnAllPlayersPresent` / `OnSurvivorOverlap`.
- **Level 232 `ScaledPricePercent`**: the game's player-scaled discount makes items
  too cheap to sell (user-confirmed at >6). Clamped to a configurable floor
  (`S232_PRICE_FLOOR = 0.50`, i.e. 50% minimum price).
  *(Superseded in v2.19.3: the `S232_PRICE_FLOOR` clamp was removed in favor of
  scaling `ScaledPricePercent` / `LaneMultiplier` / `CouponMultiplier` upward from
  their first-observed runtime value. The constant no longer exists in current code.)*
- **Extended objective-requirement caps**: based on a full class-dump audit of every
  level manager / GameState / progression actor in BETGame.hpp:
  - `FuseBoard.RequiredFuseAmount ≤ 10`
  - `RepairableElectricalBox.RequiredFuseAmount ≤ 10`
  - `CoinGate.CoinsRequired ≤ 10`
  - `InteractableDoor.ItemAmountRequired ≤ 10`
  - `LevelFunExitDoor.RequiredTicketMilestone ≤ 10`
  - `LevelFunExitPinger.ItemAmountRequired ≤ 10`
  - `ChristmasPresentQuestActor` tag-count cap (≤ 10 present tags)
- **Reorganized config block** at the top of main.lua: `TARGET_CAP=16`,
  `OBJECTIVE_CAP=6`, `GENERATOR_CAP=10`, `GENERIC_OBJECTIVE_CAP=10`,
  `ALL_PLAYERS_GATE_CAP=6`, `S232_PRICE_FLOOR=0.50`.
- All new scans are host-authority-only, CDO-filtered, and use the same proven
  periodic + hook model. Design documents the full audit catalog (which systems
  are player-scaled vs fixed) in project memory.

### Full audit: which systems scale with player count

> From a line-by-line read of every LevelNChunkManager / GameState / GameMode /
> progression actor in BETGame.hpp (v2.16 dump), with line numbers and offsets.
> See `docs/research/full_player_scaling_audit.md` for the complete table.

- **Scales with players (confirmed by curve / per-player field):**
  - Level 3 wire/repair-item spawning (`PlayerCountToWireCurve`,
    `PlayerCountToRepairItemMultiplier`)
  - Level 3 fuse requirement (`AFuseBoard.PlayerCountFuseCurve`)
  - Level -1 shadow spawn chance (`EntitySpawnChancePerPlayer`, but hard-capped
    by `MaxShadowSpawnAmount`)
  - Level 232 sale-price discount (`ScaledPricePercent`)
- **Fixed (not player-scaled) — do NOT cap:**
  - Level 1: `MaxSkinStealers`, `NumberOfAlmondWater`, `NumberOfGenerators` (fixed),
    `NumberOfPuddles`
  - Level 232: `ItemSpawnRates` (fixed FIntPoint ranges), `FacelingSpawnChunkInterval`
  - Level 4: `FacelingSpawnRateMultiplier`
  - Level Hub: `PartygoerSpawnChance`
  - Base game mode: `SpawnPointsPerChunk`, `BoltCutterNum`
- **Uncertain — need live test:**
  - Level FUN `WarehouseRequiredCoinsTotals` (TArray<int32> — Lua array mutation
    is unverified). The generic `CurrentObjectives` cap via `OnRep_CurrentObjectives`
    hook covers most other player-scaled objectives if they set the flag, but this
    specific array has not been confirmed.

## v2.16.4-cap16 (2026-06-03)

- `TARGET_CAP` set to **16** — live-tested as the highest value that can still create
  a lobby. 17+ fails session creation (an EOS-level limit the mod can't raise). The
  objective/generator caps are unchanged.
- Documented (from the game's own class dump) which systems scale with player count,
  to answer "do supplies / monsters increase with more players?":
  - **Loot / item supply — partly player-scaled.** Level 3 repair-item spawning is
    player-scaled via `ALevel3ChunkManager.PlayerCountToWireCurve` and
    `PlayerCountToRepairItemMultiplier`; Level 3 fuse requirement via
    `AFuseBoard.PlayerCountFuseCurve`. The global `UBETLootManagerComponent` only
    tracks/replicates pickups (it does not itself scale counts), and the PCG loot
    tables control *which* items appear, not *how many per player*. So general loot
    is not provably player-scaled from the dump; Level 3 repair items clearly are.
  - **Monsters — mostly fixed caps, one per-player chance.** Level -1 shadow spawns
    use `ALevelNeg1Manager.EntitySpawnChancePerPlayer` (more players → higher spawn
    chance) but are hard-capped by a fixed `MaxShadowSpawnAmount`. Level 1
    `MaxSkinStealers`, Level 4 `FacelingSpawnRateMultiplier`, Level 2.32
    `FacelingSpawnChunkInterval`, and Level Hub `PartygoerSpawnChance` are FIXED and
    do **not** grow with player count.
  - Caveat: the player-count curves were authored for the game's intended ≤6 players;
    their shape past 6 (and whether the loot manager / store spawn ranges respond to
    headcount at runtime) is unverified and needs a live 7+ player test.

## v2.16.3-capfix (2026-06-03)

### Adapt the player-cap override to the 2026-06-03 game update

- A game patch (shipping exe rebuilt 2026-06-03) changed the multiplayer settings
  menu so hosts saw **max 6 / default 4** again even though the mod's widget write
  succeeded. The widget class/fields are byte-name identical in the new exe (verified
  by string scan), so UE4SS signatures and our class names are intact — this was a
  **clamp/timing** change, not a signature break. No re-dump was required; UE4SS PS
  scan still succeeds and the engine is still 5.7.
- Fix: in addition to the existing one-shot + 5s write, the mod now post-hooks the
  widget's own `InitializeSelection` / `ClampMaxPlayers` / `IncreaseMaxPlayers` and
  re-asserts `MaxSelectablePlayers = 12` right after the game runs them, so the range
  can no longer be pinned below the target. Live log confirmed `before-override
  Min=1 Max=6 Default=4` → after hooks the host could select up to 12.
- Cleaned up four harmless startup hook errors that were NOT caused by the update:
  `Elevator_Base:StartElevator` / `OnAllPlayersJoined` (BlueprintImplementableEvents,
  not hookable), `Level1ChunkManager:GenerateChunks` (defined on the base
  `BETChunkManagerBase`), and `MultiplayerGameState:OnCurrentObjectivesUpdated` (a
  delegate signature). Removed from the hook list; property coverage is unchanged via
  the periodic scan and the base-class hook.
- Logging: per-click `[CAPDIAG]` widget spam is OFF by default (`ENABLE_WIDGET_DIAG`),
  but a one-time `before-override` line still logs each launch so a future range change
  is immediately visible. The `[OBJCAP] … -> N` lines (the signal that a generator /
  objective / elevator requirement was actually capped) are always logged.

> Verification note: the objective-requirement cap (elevator=6, generators=10, generic
> `bScalesWithPlayers` objectives=10) registered all four hooks with no errors, but the
> 2026-06-03 session was single-player on Level 0/Neg1, so nothing needed capping and no
> `[OBJCAP] … -> N` line appeared yet. Confirming generator/objective capping requires a
> 7+ player run that actually reaches Level 1 (generators) or a level with player-scaled
> objectives.

## v2.16-generic-objective-cap (2026-06-03)

### Generic cap for player-scaled objective requirements

- Added separate caps so the 12-player session limit does not force level objectives
  above the amount the maps were designed to support:
  - `OBJECTIVE_CAP = 6` for the confirmed elevator presence gate
    (`PlayersNeededToStartElevator`).
  - `GENERATOR_CAP = 10` for Level 1's generator count (`NumberOfGenerators`).
  - `GENERIC_OBJECTIVE_CAP = 10` for replicated `FLevelObjective` entries that are
    explicitly marked `bScalesWithPlayers`.
- The generic path targets `MultiplayerGameState.CurrentObjectives`: if an objective
  entry has `bScalesWithPlayers=true` and `ObjectiveAmount > 10`, the host attempts
  to clamp `ObjectiveAmount` to 10 and verifies by re-reading the owning array rather
  than only trusting a local UE4SS struct wrapper.
- Kept the approach bounded: no global `GetNumPlayers()` override, no progress/current
  counter writes, no forced objective completion, no `PlayersInElevator` writes, and
  no arbitrary UObject sweep. The monitor uses exact class/property scans plus the
  replicated objective array, all host-authority and CDO-filtered.
- Added hooks around elevator evaluation, Level 1 chunk generation, and objective
  replication/update callbacks so requirements are capped near the points where the
  game initializes or republishes them.

## v2.15-objective-cap (2026-06-03)

### Cap player-scaled pass requirements at 6 while keeping 12-player sessions

- Added a separate `OBJECTIVE_CAP = 6` constant. `TARGET_CAP` remains 12 for the
  lobby/session/player-cap override; the new cap is only for known progression
  requirements that scale from connected player count.
- Added a narrow, release-safe objective capper for the confirmed elevator gate:
  live `Elevator_Base` subclasses have `PlayersNeededToStartElevator`, and the
  mod now clamps that property to 6 if the game initializes it above 6. It does
  **not** change `PlayersInElevator`, force `StartElevator`, synthesize objective
  completion, or globally override `GetNumPlayers()`.
- Registered guarded hooks around the elevator's own evaluation points
  (`CheckForPlayersInElevator`, `StartElevator`, `OnAllPlayersJoined`,
  `OnObjectiveCompleted`) and also performs a tiny exact class/property scan at
  the existing 10s monitor cadence. Hook params are unwrapped synchronously to
  avoid stale UE4SS `RemoteUnrealParam` wrappers; writes are host-authority only
  and CDO-filtered.
- Left broader puzzle/item/quest counters diagnostic-only by design. Several dump
  fields (`RequiredTagCount`, Level 232 quota, Level FUN coins, Level 3 curves,
  Level 37 puzzle data) may be item/tag/puzzle requirements rather than
  player-derived requirements, so they are not capped without live proof.

## v2.14-nudge (2026-06-01)

### Ctrl+Arrow noclip nudge + Ctrl+K/L are normal features again

- **New host keybinds: Ctrl+Arrows / Ctrl+PageUp-Down = noclip-nudge the host.**
  Snaps the host pawn a small (~100u) step with no collision, to work around a spot
  a 7+ player run can't pass normally (stuck geometry, a player-count-gated section).
  Horizontal is **camera-relative** — computed from the controller's yaw, so Ctrl+Up
  = where the host is looking (flattened to horizontal), Ctrl+Down = back, Ctrl+Left/
  Right = strafe. Ctrl+PageUp/PageDown move ±Z in world space. Reuses the verified
  replicating teleport (`teleport_pawn`: `bSweep=false, bTeleport=true` + `ForceNetUpdate`),
  so it ignores walls and the new position reaches clients exactly like Ctrl+G/Ctrl+P.
  Host-only (guarded by `require_host`). Key names verified against this build's
  UE4SS valid-keys list (`UP_ARROW`/`DOWN_ARROW`/`LEFT_ARROW`/`RIGHT_ARROW`/`PAGE_UP`/
  `PAGE_DOWN`). Logs `[NUDGE]` lines. Caveat: presses accumulate and ignore collision,
  so repeated taps toward a ledge can walk the host off it — tap carefully.
- **Ctrl+K / Ctrl+L are normal user features again** (`ENABLE_LEVEL_TEST_KEYS=true`).
  The v2.13 audit had defaulted them off as "test tools"; per user direction they are
  ordinary level prev/next controls and are enabled by default. `ENABLE_PERIODIC_DIAG`
  stays off (pure diagnostics).

### Voice issue: confirmed NOT mod-related

User confirmed the player-specific voice failure also happens **without the mod
installed**, so it is a base-game / EOS RTC / client-network issue, not anything this
mod does. Removed from the mod's todo; kept non-identifying diagnostic notes in memory
for reference only.

Validation: Lua opener/end balance `284 == 284`; 12 keybinds registered with no
collisions (G/J/K/L/O/P + 6 arrow/page binds).

## v2.13-audit-hardening (2026-05-31)

Release audit pass + voice-failure investigation prep. This pass intentionally reduces
release risk more than it adds features.

### Code/release hardening

- **Fixed a CDO/live-instance bug in the player-cap widget override.** `apply_overrides()`
  was still using `FindFirstOf(wclass)` directly, bypassing the CDO filter that the rest
  of the mod relies on. It now uses `find_first_instance(wclass)` so it writes only to a
  real live widget instance, not `Default__` archetypes/stale objects.
- **Added explicit host/listen-server guards** for host-only actions (`Ctrl+G` gather,
  `Ctrl+J` reload, `Ctrl+O` probe, `Ctrl+P` board elevator, and diagnostic level-switch
  functions). Non-host clients now log a clear refusal instead of doing confusing local-only
  operations or no-ops. Authority detection uses the standard Unreal fact that only the
  server/listen-host owns a live GameMode; CDO-safe `find_first_instance` avoids false host
  positives.
- **Release defaults now disable risky/debug-heavy features:**
  - `ENABLE_LEVEL_TEST_KEYS=false` disables Ctrl+K/Ctrl+L previous/next level jumps by
    default (they bypass objectives and are for diagnostics only).
  - `ENABLE_PERIODIC_DIAG=false` disables the periodic 30s player-position diagnostic loop
    after spawn repair is done, reducing reflection/logging during normal play.
- **Installer hardened:** now copies from an allowlist (`enabled.txt`, `README.md`,
  `Scripts/main.lua`) rather than recursively copying any stray logs/backups; removes the
  old installed mod folder before copying so deleted/renamed files cannot survive an upgrade;
  stores structured `mods.txt` state in the manifest and restores it on uninstall; detects
  an already-current `Engine.ini` instead of backing up an identical file.
- **Engine.ini suppression narrowed:** only `LogTriiodideVoiceChatSynth=Error` is active by
  default. Broader voice categories are left visible so player-specific voice-room/RTC
  diagnostics are not hidden; optional extra suppressions remain commented out.

Validation: Lua opener/end balance `255 == 255`; installer `py_compile` passed.

### Voice issue investigation

Host log evidence suggested some affected players joined gameplay normally but did not
appear as normal EOS RTC voice-room participants from the host's point of view. This was
later confirmed to reproduce without the mod installed, so it is treated as a base-game /
EOS RTC / client-network issue, not a BETPlayerCap issue. Public troubleshooting notes are
kept in `docs/troubleshooting/README.md`.

## v2.12.0 — release prep (2026-05-31)

First packaged release. No gameplay/logic change to the mod from v2.12-rebind;
this pass makes the repo installable by someone other than the author.

- **One-command installer** (`tools/install_ue4ss_mod.py` rewritten). `install` now:
  verifies the game + base UE4SS are present (refuses with a clear message if not),
  copies the mod, **enables it in `ue4ss/Mods/mods.txt`**, and **installs the
  anti-lag `Engine.ini`** into the user config dir (backing up any existing one).
  `uninstall` reverses all three (removes the mod, disables the mods.txt line,
  restores/removes Engine.ini from backup). Verified idempotent against the live
  install. Supports `--game-root` for non-default install paths.
- **README rewritten** from an "investigation workspace" doc into a real release
  README: requirements, keybind table, install/uninstall, UE4SS prerequisite,
  anti-lag explanation, known issues, and repo layout.
- **Mod metadata updated**: `enabled.txt` version `0.1.0` → `2.12.0` with an
  accurate description; mod-folder `README.md` rewritten to describe actual
  features + keybinds.
- **Cleanup**: removed the stray `ue4ss_mods/BETPlayerCap/mods.txt` from source
  (UE4SS generates that listing in the live folder; it doesn't belong in the mod).

## v2.12-rebind (2026-05-31)

### Remap keybinds to reduce mis-presses (user request, mid-playtest)

Keybinds rearranged so the "dangerous" elevator-teleport isn't next to the level
controls and the two destructive actions sit apart:

| Key | Before | After |
|---|---|---|
| **Ctrl+G** | gather all to host | gather all to host (unchanged) |
| **Ctrl+J** | reload current level | reload current level (unchanged) |
| **Ctrl+K** | cram into elevator | **prev level** |
| **Ctrl+L** | — | **next level** |
| **Ctrl+H** | next level | *removed* (replaced by Ctrl+L) |
| **Ctrl+O** | — | **elevator probe/detect (READ-ONLY)** |
| **Ctrl+P** | elevator probe | **teleport all into elevator** |

Changes in `main.lua`:

- `cycle_next_level` refactored into `do_level_step(delta, tag)` so we now have BOTH
  directions: `cycle_next_level` (delta +1, Ctrl+L) and `cycle_prev_level` (delta -1,
  Ctrl+K). Wrap-around math fixed to be symmetric (`((cur-1+delta) % N) + 1`) so prev
  from level 1 wraps to the last entry.
- `ensure_levelsw_keybind` now registers Ctrl+L (next) and Ctrl+K (prev); Ctrl+H removed.
- Probe rebound from Ctrl+P to **Ctrl+O**; board/cram rebound from Ctrl+K to **Ctrl+P**.
- Updated all `[PROBE]`/`[BOARD]`/`[LEVELSW]` startup + function-header log strings.

No behavior change beyond the key mapping; the gather/spawn/elevator logic from
v2.10/v2.11 is untouched. Final host keybind set: **Ctrl+G** gather · **Ctrl+J** reload ·
**Ctrl+K** prev level · **Ctrl+L** next level · **Ctrl+O** elevator probe ·
**Ctrl+P** teleport into elevator.

## v2.11-host-exclude (2026-05-31)

### Fix: Ctrl+G "Summon All" was teleporting the HOST too (UObject identity bug)

User report: pressing Ctrl+G doesn't leave the host in place — the host also snaps to
a spot that feels random or "a few seconds delayed" (where the host stood a moment ago).

**Root cause (confirmed in the v2.9 UE4SS.log):** the summon excluded the host with
`players[i].char ~= host`. UE4SS wraps every object access in a NEW Lua userdata, so the
SAME pawn obtained two different ways — `get_host_pawn()` (PlayerController.Pawn) vs
`FindAllOf(character)` — compares **unequal** under `~=`. So the host was never removed
from the move list: it logged `gathering 6 players` with 6 possessed and moved the host
itself (`[SUMMON] Host @ (1239,-60,63)` then the first move `Z=63 -> 113`). The host got a
ring slot (`anchor + XY offset, +50 Z`) instead of staying put; because the anchor is
sampled a tick before the snap applies while the host is usually walking, it looks like
the host jumps **backward** to its position a moment ago — exactly the "延迟/随机" feel.

Fix in `main.lua`:

- **New `actor_id()` / `same_actor()` helpers** — compare UObjects by underlying address
  (`GetAddress`, `GetFullName` fallback) instead of wrapper-identity `~=`. This is the
  correct way to test "is this the same actor" on this UE4SS build.
- **Summon exclusion now uses `same_actor(char, host)`** so the host is genuinely dropped
  from the gather list and stays exactly where it is. Logs a warning if the host isn't
  found in the possessed list (so a future regression is visible).
- No other behavior change. The spawn-fix host-anchor path already used a Z-distance test
  (not `~=`), so it was unaffected.

With v2.10 (tight gather, no auto-summon, box-sized cram) + v2.11 (host stays put), the
gather/board behavior is considered DONE pending a final confirm. The only remaining known
issue is the game-native IrisGate stuck-loading race on rapid travel (no Lua-callable fix;
mitigate with Ctrl+J reload) — see `bet_irisgate_diagnosis`.

## v2.10-gather-fix (2026-05-31)

### Fix players falling off the map on gather/board + make the Ctrl+K cram actually register

A live 7-player test of v2.9 (UE4SS.log this build) exposed three concrete failures,
all now diagnosed from the log and fixed:

1. **Auto-summon-on-travel was flinging players into the void — REMOVED.** The Phase 3b
   post-travel auto-gather fired DURING the elevator-descent cutscene: the host pawn read
   `Z=23120` / `Z=21202` mid-drop (`[SUMMON] Host @ (-97,20,23120)`), so it gathered the
   whole group to a mid-air point. Worse, on Level 1 it placed 7 players in a wide ring at
   `Z=-653`, and 10s later 3 of them had fallen to `Z=-18853 / -12257 / -19473`
   (`[SPAWN] Outlier ... at Z=-18853`) — the 150u ring reached past the spawn-platform
   edge and dropped them off-map. Auto-gather can't know when the descent/spawn has
   settled, so it is inherently unreliable. **Gathering is now MANUAL (Ctrl+G), on the
   user's timing** — which the user correctly proposed. The settling-gated, outlier-only
   Phase 3 spawn fix still runs automatically to rescue a genuinely wrong-floor player.
2. **Gather ring tightened so it can't reach off the platform.** `ring_dest` dropped from a
   fixed 150u ring to a capped, slowly-growing footprint: first pawn on the anchor, the
   rest in a ring of radius `min(45 + (n-1)*4, 80)` u — so even 12 players stay within a
   ~160u footprint, comfortably on one floor tile. Player capsules interpenetrate and the
   engine nudges them apart (no telefrag death in this game), so a tight cluster is SAFE
   whereas a wide ring is NOT. Applies to both Ctrl+G summon and the auto spawn-fix.
3. **Ctrl+K cram now lands INSIDE the trigger box.** The Ctrl+P probe was decisive:
   `BoxExtent(half)=(32,32,32)` — the elevator `CollisionBox` is only a **64u cube**. The
   v2.9 cram used a **120u** ring, putting every player OUTSIDE the box, so
   `CheckForPlayersInElevator()` returned **false** despite a stale `In=7`
   (`[PROBE] ... In=7 Needed=7` then `Check -> false`), and the wide ring shoved edge
   players off the platform. v2.10 reads the live `BoxExtent` and crams everyone to a ring
   of radius `min(halfX,halfY)*0.4` (≈13u for a 32u half-extent) — well inside the volume.
   Logs `R=` and `half=` and the live `Check=` return so the next test shows whether the
   overlap finally registers.

Also confirmed working from the same log (kept as-is): the auto spawn-fix correctly
rescued the wrong-floor player on normal Level-0 entry; Ctrl+H level-switch and Ctrl+J
reload both travel cleanly; the stale-`In` vs live-`Check` mismatch is exactly the
geometry bug above, not a replication problem.

STILL UNVERIFIED / not fixed here: the IrisGate stuck-loading race (no Lua-callable entry
point; reload re-rolls it — see `bet_irisgate_diagnosis`); and whether, once players are
correctly inside the 64u box, the game's `CheckForPlayersInElevator()` actually fires
`StartElevator -> ProcessServerTravel` for 7 (the gate operator and the descent/ride
animation for the 7th remain to be confirmed live). Next test: Ctrl+P to confirm box +
gate, then a tight Ctrl+K, watch `[BOARD] ... Check=true` + BET.log `ProcessServerTravel`.

## v2.9-elevator (2026-05-31)

### 7+ player level transition: cram into the elevator (Ctrl+K) + read-only probe (Ctrl+P)

Overturns the long-standing assumption that "the elevator physically can't hold >6, so
extra players must suicide before a transition." A multi-agent investigation of the game's
own class dump (`BETGame.hpp`), with adversarial verification of every decisive
replication/authority claim (14 confirmed / 12 refuted / 6 uncertain), established:

- **The elevator gate is a COUNT check, not a physical-capacity limit.** `AElevator_Base`
  has a single `UBoxComponent CollisionBox` (trigger), `int PlayersInElevator`,
  `int PlayersNeededToStartElevator`, and the predicate `CheckForPlayersInElevator()`.
- **A `UBoxComponent` is an overlap volume, not a blocker** — player capsules interpenetrate,
  so any number of pawns can register inside one box regardless of how crowded it looks.
  Physical fit and the count are **decoupled**. No need to disable collision or make anyone
  die: just put everyone in the box and let the game's own authoritative code run
  `StartElevator -> move -> ServerTravel` (which inherently carries all clients), exactly as
  it already does for ≤6.

**Approach chosen — Plan 1 "cram", host-only.** It changes only WHO stands in the trigger
box, reusing ONLY the already-verified position-replicating teleport (`K2_SetActorLocation`
+ `ForceNetUpdate`). It makes NO new replication/authority assumptions — all the
authority/travel work is delegated to the game's own code. **Plan 2 (host writes
`PlayersInElevator` / directly calls `StartElevator`) was REFUTED as unsafe** (the counter
is recomputed+overwritten by the predicate and has no `OnRep`; a server writing a replicated
prop doesn't fire its own `OnRep`; `StartElevator` authority/sequencing is unverified and
calling it out of sequence may skip the travel wiring). We do NOT force it.

Changes in `main.lua`:

- **New host keybind Ctrl+P = READ-ONLY elevator probe.** Resolves the live elevator
  (`find_elevator` over base + per-level + BP class names, CDO-safe), logs the real
  `PlayersInElevator`/`PlayersNeededToStartElevator`, the `CollisionBox` world pos +
  half-extents, and the (read-only) `CheckForPlayersInElevator()` return. Run this FIRST to
  confirm the count-gate model and the live threshold before cramming. Zero side effects.
- **New host keybind Ctrl+K = cram all players into the elevator.** Teleports every possessed
  player (incl. host) into a tight 120u ring inside the `CollisionBox`, then calls the game's
  own `CheckForPlayersInElevator()` to let it re-evaluate — never forces `StartElevator`,
  never writes the counter. Logs before/after counts.
- Trigger target is read from the LIVE `CollisionBox` world position (with actor-origin
  fallback) — no per-level constants, level-independent.
- No change to the spawn fix, summon, level-switch, or reload behavior.

Still UNVERIFIED (next live test must confirm): the gate comparison operator (`>=` vs `==`)
and the live `PlayersNeededToStartElevator` value; the box extents; whether a host-side
`CheckForPlayersInElevator()` call is side-effect-free; and the `OnMoveComplete -> travel`
wiring actually firing. Test order: **Ctrl+P first** (read the gate), then a 7-player
**Ctrl+K** with objectives completed. Watch UE4SS.log `[PROBE]`/`[BOARD]` lines and BET.log
for `ProcessServerTravel` + all 7 controllers re-appearing on the destination map. See
`bet_elevator_capacity_issue` memory.

## v2.8-reload (2026-05-31)

### Ctrl+J = reload current level (un-stick loading) + fixed post-travel summon timing

Diagnosed from a real 7-player level-switch test (UE4SS.log + BET.log, this build). Using
Ctrl+H to rapidly servertravel through Level 0→1→2→3→4, the user saw: Level 0 fine, **some
players stuck on the loading screen** on Level 1 (3 stuck) and Level 3 (2 stuck), Level 2
fine. Game not frozen, voice still worked.

**Root cause (game-native, NOT the mod):** BET's own `[IrisGate]` system gates replication
across SeamlessTravel — it `Disallow`s every player at travel start, then `Allow`s each one
after `OnPlayerGenerationComplete`. The BET.log shows the Allow count varying per travel:
Level 0 = 7/7 Allow, Level 1 = **4/7**, Level 2 = 7/7, Level 3 = **5/7**, Level 4 = 6/7.
The players who only got `Disallow` and never `Allow` are exactly the ones stuck loading.
Accompanied by floods of `LogIrisRpc: Error: Rejected RPC ... missing object` — pawns whose
NetRefHandle wasn't registered when the Allow pass ran. This is a **replication race with no
retry/timeout**, exposed by rapid back-to-back servertravel (normal elevator progression
spaces levels far enough apart to rarely hit it). See `bet_irisgate_diagnosis` memory.

Changes in `main.lua`:

- **New host keybind Ctrl+J = "reload current level".** Re-travels to the SAME map via the
  same seamless `servertravel <map>?listen`, which re-runs the IrisGate Disallow→Allow pass
  for everyone — giving stuck players a fresh load attempt. The escape hatch for the
  stuck-loading case. `get_current_map_path()` resolves the live map via GameMode match,
  with a world-name suffix fallback so reload works even on maps reached by normal
  progression (incl. ones not in the test list).
- **Fixed post-travel auto-summon timing.** The old code summoned a fixed 2 ticks after
  level-detect, which the log showed firing too early: `Could not resolve host pawn —
  aborting` (host pawn not re-resolved yet) on Level 3/4, and only 5 of 7 players readable
  on Level 1 (stuck players hadn't possessed). v2.8 now WAITS until the host pawn resolves
  AND a group is readable, retrying up to `SUMMON_WAIT_TICKS` (6), then summons once;
  best-effort if the window expires. No more yanking a half-loaded group around.
- Reload re-arms per-level state (spawn_fix_applied/level_detected/scan_done/median/settled)
  and the post-travel summon, same as Ctrl+H.

Note: Ctrl+J/Ctrl+H both rely on rapid servertravel which is what *triggers* the IrisGate
race in the first place — a reload usually re-rolls who (if anyone) gets stuck. It's a
mitigation, not a cure. A real fix would require hooking BET's IrisGate Allow pass (no
Lua-callable entry point found yet — `BETGame.hpp` exposes no `AllowReplication`-style
UFUNCTION). Deferred. The stuck-loading is largely a fast-travel-testing artifact; normal
elevator progression spaces transitions far enough apart to mostly avoid it.

Separately observed (not mod-related): the game **hangs on exit** waiting on telemetry
uploads — BET.log end shows `amazonaws.com/.../ingest` HTTP timeout (30s) + Sentry
`WinHttpSendRequest` code `12007` retrying 6×. Cosmetic shutdown stall; could be mitigated
by blocking those domains but out of scope.

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
