# Backrooms: Escape Together BET 0.14.6 update notes

Source: Steam news PDF captured 2026-06-07 and kept with the local-only dump snapshot under `local_dumps/BET-0.14.6_2026-06-07/` (ignored by git).

## Mod-relevant changes

- **Level 232 reworked loot and pricing**
  - Loot now spawns per-sector and per-player, weighted by dollar amount.
  - Overall amount of large grabbable items increased.
  - Price scaling across 1–6 players increased; solo runs earn a higher percentage.
  - Warehouse bonus time reduced by 30 seconds.
  - Warehouse size and loot density decreased.
  - Hard hats removed from the sellable item pool.
  - Performance improved by about 5–10%.

  **BETPlayerCap implication:** Level 232 should be re-dumped and re-tested. The patch note confirms `ScaledPricePercent` is an earned-percentage/income mechanic, so v2.19.3 scales it upward for >6 players alongside `LaneMultiplier` and `CouponMultiplier`.

- **Loading/travel fixes**
  - Fixed clients getting stuck on loading screen during level travel.
  - Level geometry now preloads asynchronously during travel, reducing long freezes.
  - Fixed infinite black loading screen at boot while shaders compiled.

  **BETPlayerCap implication:** Re-test Ctrl+J reload, Ctrl+K/L travel, elevator boarding, and spawn-fix assumptions after updated dump/live run.

- **Voice chat overhaul**
  - Voice routes through a more stable transport.
  - Voice self-heals after death, respawn, and level transitions.

  **BETPlayerCap implication:** Existing voice-log mitigation docs may be less important on 0.14.6, but the mod should not assume voice issues are solved until live-tested.

- **Level-specific changes**
  - Level -1 bedroom objective now scales with player deaths and players who leave mid-match; requirement lowered 70% -> 60%.
  - Level 0 fixed lower tape spawn rate caused by movie item.
  - Level 2 fixed elevator panel sometimes not interactable.
  - Level 3 added final-sector checkpoint, improved performance, fixed collisions, increased 3rd-sector loot-box item amount.
  - Level 6 added order decals, lowered sanity drain, fixed potential soft lock from walls/warehouse shelves.
  - Level 37 airlock soft-lock recovery and more forgiving sync window.
  - Level FUN fixed client light state, crash on leave, completion achievement, partygoer chase/kill issues.

  **BETPlayerCap implication:** Updated `BETGame.hpp` and object dump should be compared against the 2026-06-02 dump before trusting old offsets/fields for Level -1, 3, 6, 37, FUN, and 232.

## Full extracted text snapshot

The original PDF was generated from the Steam news page and includes the full change list. Use `pdftotext -layout <pdf> <txt>` locally if a fresh text extraction is needed.
