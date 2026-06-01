# UE4SS signature status

> **Historical research note.** This file preserves investigation details from development. It is not required for normal installation or use, and some hypotheses/keybinds may be superseded by the root README and changelog.


The latest installed RE-UE4SS build is still not enough for this UE 5.7.4 shipping executable.

Verified progress in `ue4ss/UE4SS.log`:

- `GUObjectArray` is found.
- `GMalloc` is found.
- `FName::ToString` is found.
- `ConsoleManagerSingleton` is found.
- `GameEngineTick` is found.

Remaining scan blockers:

- `FName::FName(wchar_t*)` → `UE4SS_Signatures/FName_Constructor.lua`
- `StaticConstructObject_Internal` → `UE4SS_Signatures/StaticConstructObject.lua`
- `FUObjectHashTables::Get()` → `UE4SS_Signatures/GUObjectHashTables.lua`
- `GNatives` → `UE4SS_Signatures/GNatives.lua`

`BETPlayerCap` cannot run until UE4SS completes this scan phase.

## Current local configuration

Keep this override in `ue4ss/UE4SS-settings.ini`:

```ini
[EngineVersionOverride]
MajorVersion = 5
MinorVersion = 7
```

Without it, UE4SS may fall back to failing engine-version detection.

## Next route

Since the latest UE4SS build still fails, the next runtime-mod route is custom signatures for this specific executable build.

Useful fixed context:

- Game executable: `F:\Steam\steamapps\common\Backrooms_Escape_Together\BET\Binaries\Win64\BETGameSteam-Win64-Shipping.exe`
- Executable size in UE4SS log: `212239360` bytes
- Steam build id from manifest: `23480779`
- Engine version from game log: `5.7.4-0+UE5`

Suggested order:

1. Find or derive `FName_Constructor.lua` first.
2. Find or derive `StaticConstructObject.lua` next, because built-in mods use `StaticConstructObject`.
3. Add `GUObjectHashTables.lua` and `GNatives.lua` only if UE4SS still treats them as fatal for Lua mod startup.
4. Re-test until `BETPlayerCap` prints its first log line.

Do not proceed to player-cap value overrides until UE4SS loads Lua mods successfully.
