# UE4SS BETPlayerCap

Logging-first UE4SS mod skeleton for Backrooms Escape Together.

## Intended target

Install UE4SS against:

`F:\Steam\steamapps\common\Backrooms_Escape_Together\BET\Binaries\Win64\BETGameSteam-Win64-Shipping.exe`

This folder is source material for the mod. Copy or symlink `BETPlayerCap` into the UE4SS `Mods` directory only after UE4SS is installed and basic launch stability is verified.

## First objective

Do not override values immediately. First collect runtime names and confirm whether the expected classes/functions exist:

- `UBETMultiplayerSettingsWidget`
- `DefaultMaxPlayers`
- `MinSelectablePlayers`
- `MaxSelectablePlayers`
- `SelectedMaxPlayers`
- `ClampMaxPlayers`
- `IncreaseMaxPlayers`
- `DecreaseMaxPlayers`
- `GetMaxPlayersText`
- session creation functions around `CreateGameBaseWidget`
- functions/objects involving `PublicConnections`, `NumPublicConnections`, `MaxPublicConnections`, `Session.MaxPlayers`, or EOS session max players

## Test procedure

1. Install and validate base UE4SS first, without this mod enabled.
2. Launch through Steam so the game keeps AppId `2141730`.
3. Enable this mod and confirm its log lines appear.
4. Open create-game settings and click the player-count controls until the UI clamps at 6.
5. Save UE4SS logs/dumps for hook-name lookup.

## Escalation path

1. Log object/function availability.
2. Log calls around multiplayer settings UI.
3. Log selected/default/max player values.
4. Override only after call paths and value names are confirmed.
