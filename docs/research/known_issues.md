# Known follow-up issues

## Second-run cap reapplication can fail after a completed save

Priority: low / follow-up investigation.

User report (2026-06-07): after a save has already cleared the game once, a second playthrough can sometimes stop reapplying requirement caps on levels that were capped on the first run. Example: Level 1 generator requirement can return to an uncapped value instead of staying at the intended <=6/10-player baseline.

Initial investigation targets:

- Per-level state reset around `level_detected`, `spawn_fix_applied`, and monitor re-entry after returning to earlier levels.
- Whether object identity keys in `objective_cap_changed` or `supply_scaled_original` suppress logs/writes for newly spawned second-cycle objects with reused names.
- Whether `BETChunkManagerBase:GenerateChunks` / objective hooks fire differently on second-cycle levels.
- Whether `NumberOfGenerators` is rewritten by game progression after the mod's startup/level-detect cap pass and before the 10s monitor pass.
- Whether completed-save progression uses alternate GameMode/ChunkManager classes not covered by `GENERATOR_CAP_CLASSES` or `GENERIC_OBJECTIVE_CLASSES`.

Do not change behavior until reproduced or supported by a fresh UE4SS dump/log from a second-playthrough session.
