# 用户指南

[English](USER_GUIDE.md) | **中文**

## 支持的安装包

当前公开发布的安装包：**BETPlayerCap v2.19.6 完整版 Windows 安装包**。

完整版安装包已包含 UE4SS 运行时文件，因此普通用户**无需**单独安装
UE4SS 或 Python。

## 谁来安装？

只有**房主**需要安装此 Mod 才能启用玩家上限和房主工具。其他玩家可以正常加入。
如果非房主玩家也安装此 Mod，则可以使用可选的本地 `Ctrl+N` 自身无碰撞开关。

## 如何找到游戏文件夹

在 Steam 中：

1. 右键点击 **Backrooms: Escape Together**。
2. 选择 **Manage > Browse local files**（管理 > 浏览本地文件）。
3. 打开的文件夹应该是 `Backrooms_Escape_Together`。

如果安装程序无法检测到游戏文件夹，它会弹出一个文件夹选择窗口。请选择那个
`Backrooms_Escape_Together` 文件夹，或者运行：

```bat
install.bat "D:\SteamLibrary\steamapps\common\Backrooms_Escape_Together"
```

## 安装

1. 关闭游戏。
2. 从 GitHub Releases 下载完整版发布压缩包。
3. **推荐：**将其解压到你的游戏文件夹
   （`…\steamapps\common\Backrooms_Escape_Together`），然后运行 `install.bat`。它会根据解压位置自动检测
   游戏文件夹。
4. 如果你解压到了其他位置，`install.bat` 会弹出一个文件夹选择窗口——请选择你的
   `Backrooms_Escape_Together` 文件夹（或将其作为参数传入）。
5. 通过 Steam 启动游戏。

## 卸载

从同一个解压文件夹运行 `uninstall.bat`。它会使用 `install.bat` 创建的备份/清单
来还原被覆盖的文件，并删除原本不存在的文件。

## 安装程序所修改的文件

游戏文件夹下：

- `BET/Binaries/Win64/dwmapi.dll`
- `BET/Binaries/Win64/ue4ss/`
- `BET/Binaries/Win64/ue4ss/Mods/BETPlayerCap/`
- `BET/Binaries/Win64/ue4ss/Mods/Keybinds/`
- `BET/Binaries/Win64/ue4ss/Mods/shared/UEHelpers/`

用户配置文件夹下：

- `%LOCALAPPDATA%\BET\Saved\Config\Windows\Engine.ini`

备份存储于：

- `BET/Binaries/Win64/.BETPlayerCapBackup/`

## 快捷键

请参阅根目录的 README 查看当前的快捷键表。影响全队的玩法工具均仅限房主使用。
可选的 `Ctrl+N` 自身无碰撞开关只对本地安装了 Mod 的玩家生效，并且只影响该
玩家自己的角色。

## 用于报告问题的日志

如果出现故障，请附上：

- `%LOCALAPPDATA%\BET\Saved\Logs\BET.log`
- `<GameRoot>\BET\Binaries\Win64\ue4ss\UE4SS.log`
- 你当时是房主还是客户端
- 玩家数量
- 安装包版本
- 游戏是否通过 Steam 启动
