# Troubleshooting

**English** | [中文](README.zh-CN.md)

## Player stuck on loading

Use **Ctrl+J** on the host to reload the current level. This re-runs the game's seamless
travel / replication setup and usually frees players who got stuck in the game-native Iris
replication race.

This is not fully fixed by the mod because the relevant Iris allow/retry logic is not
exposed as a Lua-callable game function.

## Players separated / wrong floor

- On normal level entry, the mod attempts a one-time spawn outlier fix automatically.
- If the group is separated later, host presses **Ctrl+G** to gather everyone to the host.
- If a level physically blocks progress with 7+ people, host can use **Ctrl+Arrow keys** or
  **Ctrl+PageUp/PageDown** to noclip-nudge through geometry.

## Elevator transition with 7+ players

1. Host may press **Ctrl+O** to log the elevator trigger/gate state (read-only).
2. Host presses **Ctrl+P** to teleport all possessed players into the elevator trigger.
3. Let the game's own elevator/travel logic run.

## Lag / high latency

The package installs an `Engine.ini` that suppresses the worst known voice-chat log flood
(`LogTriiodideVoiceChatSynth` underrun warnings). That removes a large disk/CPU amplifier
on the listen-server host, but it does not fix real network saturation or EOS voice issues.

See [performance_lag_diagnosis.md](performance_lag_diagnosis.md).

## Some players cannot hear or be heard

This has been observed even without BETPlayerCap installed. It appears to be a base-game /
EOS RTC / client-network issue rather than this mod.

Useful checks for the affected player:

- Restart the game and Steam.
- Disable VPN/proxy temporarily.
- Allow the game through Windows Firewall.
- Check Windows microphone privacy/device selection.
- Try a small 2-player lobby. If voice fails there too, it is not related to 7+ player count.
- If collecting logs, look in `%LOCALAPPDATA%\BET\Saved\Logs\BET.log` for `LogEOSVoiceChat`,
  `LogEOSRTC`, `RTCRoom JoinRoom`, `OnJoinRoom`, `OnLobbyChannelConnectionChanged`,
  `SetChannelLocalReceiveEnabled`, `AudioDisabled`, and `InitializeLocalVoiceCapture`.
