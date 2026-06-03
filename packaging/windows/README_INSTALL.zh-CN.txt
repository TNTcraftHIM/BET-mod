BETPlayerCap v2.16.4 完整 WINDOWS 安装包
======================================
[ 中文（本文件） | English: README_INSTALL.txt ]

请只从项目的 GitHub release 页面下载本安装包。

安装内容
--------
- 游戏 BET\Binaries\Win64 目录下的 UE4SS 运行时 / 代理文件
- BETPlayerCap v2.16.4 Lua mod
- UE4SS Keybinds 与 shared UEHelpers 支持文件
- 写入用户配置目录的防卡顿 Engine.ini
- BET\Binaries\Win64\.BETPlayerCapBackup 下的备份数据

安装
----
1. 关闭游戏。
2. 推荐做法：把整个 zip 直接解压到你的游戏目录
   （...\steamapps\common\Backrooms_Escape_Together），然后双击 install.bat。
   安装器会根据解压所在位置自动找到游戏目录。
3. 如果你解压到了别处，install.bat 会弹出一个文件夹选择窗口。选择你的
   Backrooms_Escape_Together 文件夹。也可以直接运行：
     install.bat "D:\SteamLibrary\steamapps\common\Backrooms_Escape_Together"
4. 通过 Steam 启动游戏。
5. 只有房主需要安装本包。朋友 / 客户端正常加入即可。

在 Steam 里找到游戏目录：
  Steam > 库 > Backrooms: Escape Together > 管理 > 浏览本地文件

该双击哪个文件
--------------
只需双击 install.bat（或 uninstall.bat），这是唯一需要你运行的文件。
“betcap-installer.core.ps1” / “betcap-uninstaller.core.ps1” 是 .bat 自动调用的
内部脚本，不要直接运行它们。

修改人数上限（可选）
--------------------
默认房间上限为 12。要修改，请编辑下面文件顶部的 “USER CONFIG” 配置区：
  <游戏根目录>\BET\Binaries\Win64\ue4ss\Mods\BETPlayerCap\Scripts\main.lua
把  local TARGET_CAP = 12  改成你想要的数字，保存后重启游戏。
目前只测试过 12。更高的值可能触及游戏自身的会话上限，或加重加载/语音卡顿，
请小幅逐步提高并测试。

卸载 / 还原
-----------
从同一文件夹运行 uninstall.bat。它会自动检测安装位置（或弹出文件夹选择窗口），
并根据安装时生成的备份清单：还原原本已存在的文件，删除本包新建的文件。

房主快捷键
----------
Ctrl+G              把所有玩家集合到房主身边
Ctrl+J              重载当前关卡（缓解卡加载）
Ctrl+K / Ctrl+L     上一关 / 下一关
Ctrl+O              探测电梯（只读诊断）
Ctrl+P              把所有玩家传送进电梯
Ctrl+方向键         房主穿墙微移（相对镜头方向 前/后/左右平移）
Ctrl+PageUp/Down    房主在 Z 轴上穿墙微移

注意 / 安全
-----------
- 仅限知情同意的私人房间使用。
- 这是非官方 mod，游戏更新后可能失效。
- 穿墙微移会忽略墙体。在悬崖或虚空边缘请小心点按。
- Ctrl+K/L 可能跳过正常的关卡 / 目标初始化。
- 个别玩家进不了语音、互相听不到，是游戏本体 / EOS RTC 的问题；
  本 mod 只抑制了最严重的语音日志刷屏，并不能修复 EOS 语音本身。
- Windows SmartScreen 可能会对未签名的本地脚本发出警告。只有在你信任来源时才运行。

排查问题用的日志
----------------
游戏日志：
  %LOCALAPPDATA%\BET\Saved\Logs\BET.log
UE4SS 日志：
  <游戏根目录>\BET\Binaries\Win64\ue4ss\UE4SS.log

本安装包刻意不包含
------------------
- UE4SS.log
- UE4SS_ObjectDump.txt
- CXXHeaderDump/
- 崩溃转储、本地日志、生成的 SDK/头文件转储，以及研究文件
