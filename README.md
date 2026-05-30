# BET Player Cap Mod

Experimental workspace for investigating and attempting a private-lobby player cap increase for **Backrooms Escape Together**.

Default local paths used by the tools:

- Game install: `F:\Steam\steamapps\common\Backrooms_Escape_Together`
- Main executable: `BET\Binaries\Win64\BETGameSteam-Win64-Shipping.exe`

## Current status

The 6-player cap appears to be implemented in packaged Unreal Engine game logic rather than a simple exposed `.ini` value. The current low-risk path is:

1. Scan the installed game for cap/session strings.
2. Try reversible launch-time UE cvars such as `net.MaxPlayersOverride`.
3. If that is insufficient, use UE4SS for logging-only runtime discovery.
4. Only then attempt runtime value overrides.

## Safety

- Test only in private lobbies with consenting players.
- Do not use this for public matchmaking disruption.
- Do not bypass anti-cheat or detection systems.
- Prefer reversible launch options and runtime mods before modifying game files.
- Back up any game file before patching it.

## Quick commands

```bat
C:\Users\TNTcraft\anaconda3\python.exe tools\check_install.py
C:\Users\TNTcraft\anaconda3\python.exe tools\scan_bet_strings.py --write-doc docs\findings.md
launch\bet_modded_private_test.bat 12
C:\Users\TNTcraft\anaconda3\python.exe tools\install_ue4ss_mod.py install
```

Use `tools\install_ue4ss_mod.py` only after base UE4SS is installed and the unmodified game reaches the main menu through Steam.

## Files

- `tools/check_install.py` — verifies expected files and checks for obvious anti-cheat components.
- `tools/scan_bet_strings.py` — scans binaries/assets for multiplayer cap/session strings.
- `tools/install_ue4ss_mod.py` — copies/removes the local UE4SS Lua mod after UE4SS itself is installed.
- `docs/findings.md` — generated and curated findings.
- `docs/ue4ss_signatures.md` — current UE4SS signature blockers for this UE 5.7.4 build.
- `launch/bet_modded_private_test.bat` — starts the game with reversible test cvars.
- `ue4ss_mods/BETPlayerCap` — logging-first UE4SS mod skeleton.
