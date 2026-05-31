# Multiplayer lag / host stutter — diagnosis (2026-05-31)

## Symptom

7-player session: remote clients report very high latency / heavy lag; the host
also has stuttery FPS.

## Root cause: voice-chat log flood drags the listen-server host (NOT the mod)

Evidence from `%LOCALAPPDATA%/BET/Saved/Logs/BET.log` after a 7-player session:

- The log grew to **76 MB / ~405,000 lines**. The BETPlayerCap mod's own log
  (`UE4SS.log`) was only **227 KB / 1083 lines** — so the flood is the GAME, not
  the mod.
- In the last 200k lines, the dominant category by far is
  `LogTriiodideVoiceChatSynth: Warning`, at a density of **~44–50 lines per frame**.
- The repeated message is always:
  ```
  LogTriiodideVoiceChatSynth: Warning: OnGenerateAudio: Playback underrun
  shortfall=1024 buffered_ms=0.00 room=conf+<n> player=<id>
  ```
  i.e. the voice synth's audio buffer **underruns every frame** (`buffered_ms=0.00`,
  never recovers) and logs once per speaker per frame.

### Why a log flood causes network lag here

BET runs as a **listen server** (host = server). Formatting and flushing tens of
log lines to a growing 76 MB file every frame steals host CPU and disk I/O, which
drops the server's tick rate. On a listen server, a slow host tick raises latency
for **every** remote client and stutters the host's own frame rate. So the log
spam is an **amplifier**: a network/voice problem becomes a whole-lobby lag spike.

### The underrun itself (the source, network-side)

Underruns are concentrated on a few players (counts of 1569 / 1247 / 1106 / 674,
then a sharp drop to 71 and none for the rest), and `buffered_ms` is **always
0.00** — those players' voice streams never arrive in time. That pattern points to
an **uplink/bandwidth bottleneck** on the host saturated by 7-way voice + game
state replication. The Triiodide voice synth's jitter/buffer params are baked into
native C++ (`UTriiodideVoiceChatSynthComponent` exposes no tunable UPROPERTY in the
class dump), so this can't be retuned from local config.

## Mitigation applied (reversible)

Created `%LOCALAPPDATA%/BET/Saved/Config/Windows/Engine.ini` (a copy is kept here as
`config/Engine.ini`) that raises the log threshold for the noisy categories so they
stop being written every frame:

```ini
[Core.Log]
LogTriiodideVoiceChatSynth=Error
LogTriiodideVoiceChat=Error
LogBETVoice=Error
LogEOSVoiceChat=Error
LogNetPlayerMovement=Error
```

This removes the **logging amplifier** (the per-frame disk flood) without touching
gameplay, audio, or netcode. The underrun itself is unchanged — it's a network /
voice-buffer condition. **Delete the file to fully revert.**

## What this does NOT fix

- The actual voice underrun (host uplink saturation). Real fixes are network-side:
  better host upload bandwidth, fewer simultaneous speakers, or the devs tuning the
  voice jitter buffer. None are reachable from the mod or local config.
- The IrisGate stuck-loading race on rapid travel (separate issue; mitigate with
  Ctrl+J reload).

## How to verify the mitigation worked

After a session with the Engine.ini in place, check BET.log size and the
`LogTriiodideVoiceChatSynth: Warning` line count — both should be dramatically
lower. If host FPS / client latency improve in tandem, the amplifier was a real
contributor.
