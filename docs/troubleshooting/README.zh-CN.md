# 疑难解答

[English](README.md) | **中文**

## 玩家卡在加载界面

在主机端使用 **Ctrl+J** 重新加载当前关卡。这会重新运行游戏的无缝旅行 / 复制（seamless
travel / replication）初始化流程，通常能够解救那些卡在游戏原生 Iris
复制竞争中的玩家。

这个问题尚未被该 mod 彻底修复，因为相关的 Iris allow/retry 逻辑并没有
作为可供 Lua 调用的游戏函数对外暴露。

## 玩家被分散 / 处于错误楼层

- 在正常进入关卡时，mod 会自动尝试进行一次性的出生点异常修复。
- 如果之后队伍被分散，主机按 **Ctrl+G** 将所有人集合到主机处。
- 如果某个关卡在 7 名及以上玩家时从物理层面阻碍了进度，主机可以使用 **Ctrl+Arrow keys** 或
  **Ctrl+PageUp/PageDown** 进行穿模微调（noclip-nudge）以穿过几何体。

## 7 名及以上玩家的电梯过渡

1. 主机可以按 **Ctrl+O** 记录电梯触发器/闸门状态（只读）。
2. 主机按 **Ctrl+P** 将所有已附身（possessed）的玩家传送到电梯触发器内。
3. 让游戏自身的电梯/旅行逻辑运行。

## 卡顿 / 高延迟

该安装包会安装一个 `Engine.ini`，用于抑制已知最严重的语音聊天日志洪流
（`LogTriiodideVoiceChatSynth` underrun 警告）。这能消除监听服务器（listen-server）主机上一个巨大的磁盘/CPU 放大因素，
但它无法修复真正的网络饱和或 EOS 语音问题。

参见 [performance_lag_diagnosis.md](performance_lag_diagnosis.md)。

## 部分玩家听不到声音或无法被听到

即使在未安装 BETPlayerCap 的情况下也观察到过这种现象。它看起来是基础游戏 /
EOS RTC / 客户端网络方面的问题，而不是本 mod 引起的。

对受影响玩家的有用排查项：

- 重启游戏和 Steam。
- 暂时禁用 VPN/代理。
- 在 Windows 防火墙中允许该游戏通过。
- 检查 Windows 的麦克风隐私设置/设备选择。
- 尝试一个仅 2 名玩家的小型大厅。如果语音在那里也失败，那么这与 7 名及以上的玩家数量无关。
- 如果要收集日志，请在 `%LOCALAPPDATA%\BET\Saved\Logs\BET.log` 中查找 `LogEOSVoiceChat`、
  `LogEOSRTC`、`RTCRoom JoinRoom`、`OnJoinRoom`、`OnLobbyChannelConnectionChanged`、
  `SetChannelLocalReceiveEnabled`、`AudioDisabled` 以及 `InitializeLocalVoiceCapture`。
