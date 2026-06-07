# Local UE4SS dump versioning

Generated UE4SS dumps are large local research artifacts and are intentionally ignored by git. Keep them under `local_dumps/` using one directory per game build/date, for example:

```text
local_dumps/
  BET-0.14.6_2026-06-07/
    manifest.md
    UE4SS_ObjectDump.txt
    CXXHeaderDump/
      BETGame.hpp
    UE4SS.log
```

## How to generate a fresh dump

1. Install/verify UE4SS in the game folder:
   `F:\Steam\steamapps\common\Backrooms_Escape_Together\BET\Binaries\Win64\ue4ss`.
2. Launch the game through Steam, not by directly running the shipping exe, so Steam/EOS app state is correct.
3. At the main menu, use the bundled UE4SS Keybinds mod:
   - `Ctrl+J` — object dump (`UE4SS_ObjectDump.txt`)
   - `Ctrl+H` — C++ header dump (`CXXHeaderDump/`)
4. Exit the game after the dump completes.
5. Copy the generated artifacts into a new `local_dumps/<game-version>_<date>/` directory.
6. Add a `manifest.md` with:
   - game version / Steam build date if known
   - UE4SS version/settings notes
   - dump time
   - which keys were run
   - any crashes or warnings

## Current 0.14.6 notes

The 0.14.6 Steam news PDF is summarized in `docs/research/game_update_notes_0.14.6.md`. Re-audit Level 232, Level -1, Level 3, Level 6, Level 37, Level FUN, loading/travel, and voice-related assumptions after generating the fresh dump.

## Git policy

`local_dumps/`, `UE4SS_ObjectDump.txt`, `CXXHeaderDump/`, logs, and generated SDK/dump artifacts are ignored. Keep them locally for comparison; do not commit or ship them.
