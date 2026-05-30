# Reversible launch tests

## `bet_modded_private_test.bat`

Launches the game through Steam with:

```text
steam.exe -applaunch 2141730 -ExecCmds="net.MaxPlayersOverride <cap>"
```

Usage:

```bat
launch\bet_modded_private_test.bat 12
```

This does not modify game files. It tests whether Unreal's built-in `net.MaxPlayersOverride` affects the host/session admission path while preserving the Steam context required by EOS.

Do not launch the shipping `.exe` directly for multiplayer tests. Direct launch produces `AppId: 0`, Steam initialization failures, EOS platform failures, repeated online subsystem retries, and severe stutter.

## Logs

Current game log location:

```text
%LOCALAPPDATA%\BET\Saved\Logs\BET.log
```

Useful lines to check:

- `LogInit: Command Line:` — confirms the launch flags reached the game.
- `STEAM: [AppId: ...]` — should not be `0` when launched through Steam.
- `FOnlineSubsystemEOS::PlatformCreate()` — should not repeatedly fail during a valid online launch.

## What to observe

Use a private lobby and record:

1. Does the create-game UI still clamp at 6?
2. Does the lobby display or advertise the requested cap?
3. Can player 7 join by invite/code?
4. If joining fails, where does it fail?
   - UI says full
   - platform/session says full
   - loading starts then rejects
   - gameplay loads but spawn/state fails
5. Are logs produced under `%LOCALAPPDATA%` or the game directory?

## Expected limitation

This cvar may affect only Unreal `AGameSession` full-server checks. If the game separately passes 6 to EOS/Steam session creation, player 7 may still be rejected before reaching gameplay.
