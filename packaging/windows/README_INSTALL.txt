BETPlayerCap v2.16.3 FULL WINDOWS PACKAGE
=======================================
[ English (this file) | 中文: README_INSTALL.zh-CN.txt ]

Download this package only from the project GitHub release page.

WHAT THIS INSTALLS
------------------
- UE4SS runtime/proxy files under the game's BET\Binaries\Win64 folder
- BETPlayerCap v2.16.3 Lua mod
- UE4SS Keybinds + shared UEHelpers support files
- Anti-lag Engine.ini in your user config folder
- Backup data under BET\Binaries\Win64\.BETPlayerCapBackup

INSTALL
-------
1. Close the game.
2. RECOMMENDED: extract this whole zip into your game folder
   (...\steamapps\common\Backrooms_Escape_Together), then double-click install.bat.
   The installer finds the game folder automatically from where it was extracted.
3. If you extracted somewhere else, install.bat opens a folder picker. Select your
   Backrooms_Escape_Together folder. You can also run:
     install.bat "D:\SteamLibrary\steamapps\common\Backrooms_Escape_Together"
4. Launch the game through Steam.
5. Only the HOST needs the package. Friends/clients can join normally.

To find the game folder in Steam:
  Steam > Library > Backrooms: Escape Together > Manage > Browse local files

UNINSTALL / RESTORE
-------------------
Run uninstall.bat from the same folder. It auto-detects the install (or opens a folder
picker) and uses the backup manifest created during install to restore files that already
existed and remove files that were created by the package.

HOST KEYBINDS
-------------
Ctrl+G              Gather all players to host
Ctrl+J              Reload current level (helps stuck loading)
Ctrl+K / Ctrl+L     Previous / next level
Ctrl+O              Probe elevator (read-only diagnostics)
Ctrl+P              Teleport all players into elevator
Ctrl+Arrow keys     Noclip-nudge host (camera-relative forward/back/strafe)
Ctrl+PageUp/Down    Noclip-nudge host on Z axis

NOTES / SAFETY
--------------
- Private lobbies with consenting players only.
- This is unofficial and may break after game updates.
- Noclip nudge ignores walls. Tap carefully near ledges or voids.
- Ctrl+K/L can skip normal level/objective setup.
- Voice problems with individual players not joining voice are a base-game/EOS RTC issue;
  this mod only suppresses the worst voice log flood, it does not fix EOS voice itself.
- Windows SmartScreen may warn about unsigned local scripts. Run them only if you trust
  the package source.

LOGS FOR TROUBLESHOOTING
------------------------
Game log:
  %LOCALAPPDATA%\BET\Saved\Logs\BET.log
UE4SS log:
  <GameRoot>\BET\Binaries\Win64\ue4ss\UE4SS.log

PACKAGE CONTENTS INTENTIONALLY EXCLUDE
--------------------------------------
- UE4SS.log
- UE4SS_ObjectDump.txt
- CXXHeaderDump/
- crash dumps, local logs, generated SDK/header dumps, and research files
