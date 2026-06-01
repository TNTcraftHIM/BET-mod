# Changelog

All notable changes to the BETPlayerCap UE4SS mod and the surrounding research workspace.

> Current install/use instructions are in `README.md` and `docs/USER_GUIDE.md`.
> Older entries preserve development history and may mention superseded keybinds or
> hypotheses.

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
