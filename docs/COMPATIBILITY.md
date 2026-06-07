# Compatibility

**English** | [中文](COMPATIBILITY.zh-CN.md)

## Tested target

The last known confirmed build is **v2.19.5** against the Steam Windows release of
**Backrooms: Escape Together** using Unreal Engine **5.7.x** and UE4SS **3.0.x**.
The exact engine version, UE4SS runtime files, and signatures may change as the game
updates — consult the changelog for the most recent tested configuration.

## Update policy

This mod relies on UE4SS signatures and game class/function names. A game update can break
it even if the installer still copies files successfully.

Common breakage symptoms:

- The game launches but no `[BETPlayerCap]` lines appear in `UE4SS.log`.
- UE4SS reports signature scan failures.
- Keybinds do nothing in a real level.
- The player-cap UI no longer changes above 6 (or the new cap is not reflected).
- Travel/gather/elevator tools log object/class resolution failures.

If any of these happen after a Steam update, use `uninstall.bat` and wait for an updated
release.

## Multiplayer/voice notes

- Only the host needs the mod for the player cap and host tools; clients may optionally
  install it too for the local-only self no-collision toggle.
- Voice chat is the base game's EOS RTC system. Some player-specific voice failures have
  been observed even without this mod.
- The included `Engine.ini` only suppresses a noisy voice-synth underrun log category; it
  does not change EOS voice networking.

## Anti-cheat note

No anti-cheat bypass is included. Do not use this in public matchmaking. Private lobbies
with consenting players only.
