# UE4SS setup notes

> **Historical research note.** This file preserves investigation details from development. It is not required for normal installation or use, and some hypotheses/keybinds may be superseded by the root README and changelog.


## Purpose

UE4SS is the preferred runtime route if launch-time cvars cannot raise the practical cap. The first UE4SS pass should only log/dump runtime names; value overrides come later.

## Target executable

```text
F:\Steam\steamapps\common\Backrooms_Escape_Together\BET\Binaries\Win64\BETGameSteam-Win64-Shipping.exe
```

## Initial checks before installing

1. Re-run `tools\check_install.py` and confirm no obvious EAC/BattlEye files appear.
2. Keep a copy of any files UE4SS places next to the executable so uninstall is clean.
3. Start with UE4SS defaults and verify the unmodified game reaches the main menu.
4. Copy `ue4ss_mods\BETPlayerCap` into the UE4SS `Mods` directory only after base UE4SS stability is confirmed.

## Runtime names to confirm

UI/settings targets:

- `UBETMultiplayerSettingsWidget`
- `DefaultMaxPlayers`
- `MinSelectablePlayers`
- `MaxSelectablePlayers`
- `SelectedMaxPlayers`
- `ClampMaxPlayers`
- `IncreaseMaxPlayers`
- `DecreaseMaxPlayers`
- `GetMaxPlayersText`
- `MaxPlayersValueText`

Lobby/session targets:

- `CreateGameBaseWidget`
- session creation / create game widget functions
- `PublicConnections`
- `NumPublicConnections`
- `MaxPublicConnections`
- `Session.MaxPlayers`
- `EOS_SessionModification_SetMaxPlayers`

## Runtime discovery pass

1. Enable UE4SS object/function dumps with no value overrides.
2. Launch through Steam, not the shipping executable directly, so Steam/EOS keeps AppId `2141730`.
3. Open the create-game screen and click max-player increase/decrease until the UI clamps at 6.
4. Create a private lobby if the base UE4SS install is stable.
5. Save UE4SS logs/dumps and search them for the names above.

Useful evidence to capture:

- The exact full path/name UE4SS uses for `UBETMultiplayerSettingsWidget`.
- Whether `IncreaseMaxPlayers`, `DecreaseMaxPlayers`, or `ClampMaxPlayers` are hookable Lua functions.
- The runtime value of `SelectedMaxPlayers` before and after clicking the UI buttons.
- The value passed into session creation as public/max connections.

## Hooking order after names are confirmed

1. Log-only hooks for `IncreaseMaxPlayers`, `DecreaseMaxPlayers`, and `ClampMaxPlayers`.
2. UI override: raise `MaxSelectablePlayers` and preserve `SelectedMaxPlayers` above 6.
3. Session override: ensure public/max connection values use the same raised cap.
4. Admission check reinforcement: keep `net.MaxPlayersOverride` set to the target cap during startup/session creation.

## First useful log result

The first successful result is not “cap raised”; it is a UE4SS log/dump proving which exact class/function owns the cap and where the selected value flows during lobby creation.
