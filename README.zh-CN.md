# BET Player Cap Mod

[English](README.md) | **中文**

一个面向 **Backrooms: Escape Together** 的 Windows UE4SS 模组包，让私人
房间的房主可以与超过默认 6 名玩家（目标上限：**16**）一起游玩，并为
7 人以上游玩时的主要痛点提供房主工具：聚拢走散的玩家、重载卡住的关卡、
登上电梯、在游戏暴露曲线时将随人数增长的过关要求封顶到 6 人基准、按人数比例增加已确认的补给刷新、禁止"全员到场"门禁超过 6 人时生效，以及
在关卡并非为这么多人设计时帮你挤过地形。

> **团队功能只需要房主安装。** 玩家上限和房主工具只要求房间房主/监听服务器安装。
> 朋友们可以用未修改的游戏正常加入。如果非房主玩家也安装了该模组，
> 则可以使用下面的可选本地“自身无碰撞”开关。
>
> **仅限私人/双方同意的房间。** 请勿将其用于公开匹配，或用于
> 干扰其他玩家。

## 下载 / 安装

请使用 GitHub Releases 页面提供的完整 Windows 安装包：

```text
BETPlayerCap-v2.19.3-full.zip
```

本地构建也可能在 `dist/` 下生成同名文件，供维护者使用。

请用追踪的校验和来验证你的下载
（[`dist/BETPlayerCap-v2.19.3-full.zip.sha256`](dist/BETPlayerCap-v2.19.3-full.zip.sha256)）；
参见 [`RELEASES.md`](RELEASES.md)。

其中包含经过测试的 UE4SS 运行时/代理 DLL、BETPlayerCap、所需的 Keybinds 和
UEHelpers 支持文件、一份反卡顿的 `Engine.ini`，以及无需 Python 的安装/卸载
脚本。

1. 关闭游戏。
2. **推荐做法：** 直接将 zip 解压**到你的游戏文件夹中**
   （`…\steamapps\common\Backrooms_Escape_Together`），然后双击 `install.bat`。
   它会自动从解压所在位置检测游戏文件夹。
3. 如果你解压到了其他地方，`install.bat` 会打开一个文件夹选择器——选择你的
   `Backrooms_Escape_Together` 文件夹。你也可以显式传入该路径：
   ```bat
   install.bat "D:\SteamLibrary\steamapps\common\Backrooms_Escape_Together"
   ```
4. 通过 Steam 启动并主持一个私人房间。

在 Steam 中查找游戏文件夹：右键点击游戏 → **管理 → 浏览本地文件**。

从同一文件夹中用 `uninstall.bat` 卸载。安装程序会记录它所做的改动，
并在可能的情况下恢复备份。

## 房主快捷键

| 按键 | 作用 |
|-----|--------|
| **Ctrl+G** | 将所有玩家聚拢到房主身边 |
| **Ctrl+J** | 重载当前关卡（帮助卡在加载中的玩家） |
| **Ctrl+K** | 上一关 |
| **Ctrl+L** | 下一关 |
| **Ctrl+O** | 探测电梯状态（只读诊断） |
| **Ctrl+P** | 将所有玩家传送进电梯 |
| **Ctrl+方向键** | 房主穿墙微移：相对房主视角方向前/后/横移 |
| **Ctrl+PageUp/PageDown** | 房主在 Z 轴上向上/向下穿墙微移 |
| **Ctrl+N** | 可选本地开关：切换已安装玩家自己的角色碰撞 |

注意：

- 该模组还针对已知的“某个玩家出生在错误楼层”的情况提供了出生时自动修复。
  它带有稳定判定门控，且仅作用于离群异常情况。
- 穿墙微移会忽略碰撞，每次按键移动约 100 个单位。在边缘或虚空附近请谨慎
  轻点。
- Ctrl+N 只对安装了模组的本地玩家生效：它只切换该玩家自己的角色碰撞，
  不会修改怪物或其他玩家。
- Ctrl+K/L 直接进行跳转映射，可能绕过正常的目标/结局路径设置。它们是
  便利工具，而非忠实的流程推进系统。

## 已知限制

- **偶发的加载卡死**是游戏原生的 Iris 复制竞态，尤其是在
  快速切换关卡之后。用 **Ctrl+J** 重载当前关卡并重试。
- **个别玩家的语音聊天失败**在没有这个模组时也会出现。它们似乎
  是游戏本体/EOS RTC/客户端网络的问题，而非 BETPlayerCap。所附带的反卡顿
  配置只抑制了最严重的语音日志刷屏；它本身并不修复 EOS 语音。
- 有些关卡并非为 7 人以上设计。过关要求封顶会尽量使用游戏暴露的 6 人基准来处理随人数增长的各类目标（电梯、发电机、谜题等），并按人数比例增加已确认的补给刷新；同时在人数超过 6 时禁止"全员到场"门禁。但地形/加载问题仍可能需要变通。电梯和穿墙工具并不是官方关卡支持。

## 安装包会装入什么

- 位于 `BET/Binaries/Win64/` 下的 UE4SS 代理/运行时文件（`dwmapi.dll`、`ue4ss/UE4SS.dll`、
  签名、设置以及运行时 DLL 依赖）。
- `ue4ss/Mods/BETPlayerCap/`。
- 所需的 UE4SS 支持模组：`Keybinds` 和 `shared/UEHelpers`。
- 用户配置反卡顿文件：
  `%LOCALAPPDATA%\BET\Saved\Config\Windows\Engine.ini`。

发布包有意排除本地日志/转储/开发产物，例如
`UE4SS.log`、`UE4SS_ObjectDump.txt`、`CXXHeaderDump/`、崩溃转储以及调试用示例模组。

## 从源码构建 / 安装

源代码树保留用于开发和可审计性。大多数用户应使用上面的完整
zip。

如果你已经安装了 UE4SS，只想从源代码复制 Lua 模组：

```bat
python tools\install_ue4ss_mod.py install
```

对于非默认的游戏路径：

```bat
python tools\install_ue4ss_mod.py install --game-root "D:\SteamLibrary\steamapps\common\Backrooms_Escape_Together"
```

## 仓库结构

- `dist/` — 构建出的发布 zip（已被 gitignore）及其受跟踪的 `.sha256` 校验和。
- `ue4ss_mods/BETPlayerCap/` — Lua 模组源代码。
- `config/Engine.ini` — 安装程序使用的反卡顿日志抑制配置。
- `tools/` — 源代码/开发者安装、发布构建和检查辅助工具。
- `tools/research/` — 历史扫描器/签名工具；正常使用不需要。
- `docs/troubleshooting/` — 面向用户的诊断和故障排查说明。
- `docs/research/` — 为可追溯性保留的历史调查笔记。
- `CHANGELOG.md` — 详细的版本历史。
- `THIRD_PARTY_NOTICES.md` — 关于捆绑的 UE4SS 运行时文件的说明。

## 安全 / 适用范围

- 这是一个合作向的私人房间模组，而非公开匹配工具。
- 它不绕过反作弊，也不实现检测规避。
- 它附带可逆的安装程序，并避免破坏性的游戏文件打补丁。
- 它是非官方的，在游戏更新后可能失效。
