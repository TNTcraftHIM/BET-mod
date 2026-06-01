"""One-command installer for the BETPlayerCap UE4SS mod.

What it does (install):
  1. Verifies the game install and that base UE4SS is present (does NOT install
     UE4SS itself — that's a third-party dependency; see README for the link).
  2. Copies the BETPlayerCap mod folder into the UE4SS Mods directory.
  3. Enables the mod in ue4ss/Mods/mods.txt (adds/sets "BETPlayerCap : 1").
  4. Installs the anti-lag Engine.ini into the user's Saved/Config/Windows dir
     (backing up any existing one first).
  5. Writes a manifest so uninstall is clean and reversible.

Everything is reversible: `uninstall` removes the mod folder, restores the
mods.txt line, and restores/removes Engine.ini from the backup.

Usage:
    python tools/install_ue4ss_mod.py install
    python tools/install_ue4ss_mod.py uninstall
    python tools/install_ue4ss_mod.py install --game-root "D:/Games/BET"
"""
from __future__ import annotations

import argparse
import json
import os
import shutil
from datetime import datetime
from pathlib import Path

MOD_NAME = "BETPlayerCap"
REPO_ROOT = Path(__file__).resolve().parents[1]
SOURCE_MOD_DIR = REPO_ROOT / "ue4ss_mods" / MOD_NAME
SOURCE_ENGINE_INI = REPO_ROOT / "config" / "Engine.ini"

DEFAULT_GAME_ROOT = Path(r"F:\Steam\steamapps\common\Backrooms_Escape_Together")
MANIFEST_NAME = ".bet_player_cap_install.json"


def game_paths(game_root: Path) -> dict[str, Path]:
    win64 = game_root / "BET" / "Binaries" / "Win64"
    ue4ss = win64 / "ue4ss"
    return {
        "win64": win64,
        "ue4ss": ue4ss,
        "proxy_dll": win64 / "dwmapi.dll",
        "ue4ss_dll": ue4ss / "UE4SS.dll",
        "mods_dir": ue4ss / "Mods",
        "mods_txt": ue4ss / "Mods" / "mods.txt",
        "target_mod": ue4ss / "Mods" / MOD_NAME,
    }


def engine_ini_target() -> Path:
    """User config dir: %LOCALAPPDATA%/BET/Saved/Config/Windows/Engine.ini."""
    local = os.environ.get("LOCALAPPDATA")
    base = Path(local) if local else (Path.home() / "AppData" / "Local")
    return base / "BET" / "Saved" / "Config" / "Windows" / "Engine.ini"


def verify_ue4ss(p: dict[str, Path]) -> list[str]:
    """Return a list of problems; empty list means OK."""
    problems: list[str] = []
    if not p["win64"].is_dir():
        problems.append(f"Game Win64 dir not found: {p['win64']}")
        return problems
    if not p["ue4ss"].is_dir() or not p["ue4ss_dll"].is_file():
        problems.append(
            "Base UE4SS not found. Install UE4SS for this game first "
            "(expected ue4ss/UE4SS.dll under Win64). See README for the link."
        )
    if not p["proxy_dll"].is_file():
        problems.append(
            "UE4SS proxy loader (dwmapi.dll) not found in Win64 — UE4SS will not "
            "inject. Reinstall base UE4SS."
        )
    if not p["mods_dir"].is_dir():
        problems.append(f"UE4SS Mods dir not found: {p['mods_dir']}")
    return problems


MOD_FILES = [
    Path("enabled.txt"),
    Path("README.md"),
    Path("Scripts") / "main.lua",
]


def copy_mod_files(source: Path, target: Path) -> list[str]:
    """Copy only the known release files; never ship logs/caches/backups by accident."""
    copied: list[str] = []
    for relative in MOD_FILES:
        src = source / relative
        if not src.is_file():
            raise SystemExit(f"Missing required mod file: {src}")
        dst = target / relative
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src, dst)
        copied.append(str(relative).replace("\\", "/"))
    return copied


def read_mods_txt(mods_txt: Path) -> list[str]:
    if not mods_txt.is_file():
        return []
    return mods_txt.read_text(encoding="utf-8").splitlines()


def write_mods_txt(mods_txt: Path, lines: list[str]) -> None:
    mods_txt.parent.mkdir(parents=True, exist_ok=True)
    mods_txt.write_text("\n".join(lines) + "\n", encoding="utf-8")


def find_mod_line(lines: list[str]) -> int | None:
    for i, line in enumerate(lines):
        stripped = line.strip()
        if stripped.lower().startswith(MOD_NAME.lower()) and ":" in stripped:
            key = stripped.split(":", 1)[0].strip()
            if key.lower() == MOD_NAME.lower():
                return i
    return None


def enable_in_mods_txt(mods_txt: Path) -> dict:
    """Ensure 'BETPlayerCap : 1' is present and record prior state for uninstall."""
    lines = read_mods_txt(mods_txt)
    record = {"path": str(mods_txt), "before": None, "action": "no-file" if not lines else "none"}
    idx = find_mod_line(lines)
    if idx is not None:
        record["before"] = lines[idx]
        if lines[idx].strip().endswith(": 1") or lines[idx].split(":", 1)[1].strip() == "1":
            record["action"] = "already-enabled"
        else:
            lines[idx] = f"{MOD_NAME} : 1"
            record["action"] = "flipped-to-enabled"
            write_mods_txt(mods_txt, lines)
        return record

    insert_at = len(lines)
    for i, line in enumerate(lines):
        if "Built-in keybinds" in line or line.strip().lower().startswith("keybinds"):
            insert_at = i
            break
    lines.insert(insert_at, f"{MOD_NAME} : 1")
    record["action"] = "added"
    write_mods_txt(mods_txt, lines)
    return record


def restore_mods_txt(record: dict | None) -> None:
    if not record:
        return
    mods_txt = Path(record.get("path", ""))
    if not mods_txt.name or not mods_txt.exists():
        return
    lines = read_mods_txt(mods_txt)
    idx = find_mod_line(lines)
    before = record.get("before")
    action = record.get("action")
    if before:
        if idx is not None:
            lines[idx] = before
        else:
            lines.append(before)
    elif action == "added" and idx is not None:
        lines.pop(idx)
    elif idx is not None:
        # If we did not add or change the line (already-enabled), leave it alone.
        pass
    write_mods_txt(mods_txt, lines)


def install_engine_ini() -> dict:
    """Install the anti-lag Engine.ini, backing up any existing file.
    Returns a record for the manifest."""
    target = engine_ini_target()
    record = {"path": str(target), "action": "none", "backup": None}
    if not SOURCE_ENGINE_INI.is_file():
        record["action"] = "source-missing"
        return record
    target.parent.mkdir(parents=True, exist_ok=True)
    source_text = SOURCE_ENGINE_INI.read_text(encoding="utf-8", errors="replace")
    if target.exists():
        target_text = target.read_text(encoding="utf-8", errors="replace")
        if target_text == source_text:
            record["action"] = "already-current"
            return record
        backup = target.with_suffix(".ini.bak_betcap")
        if not backup.exists():
            shutil.copy2(target, backup)
        record["backup"] = str(backup)
        record["action"] = "replaced"
    else:
        record["action"] = "created"
    shutil.copy2(SOURCE_ENGINE_INI, target)
    return record


def restore_engine_ini(record: dict | None) -> None:
    if not record:
        return
    target = Path(record.get("path", ""))
    if not target.name:
        return
    backup = record.get("backup")
    if backup and Path(backup).exists():
        shutil.copy2(backup, target)
        Path(backup).unlink(missing_ok=True)
        print(f"Restored original Engine.ini from backup -> {target}")
    elif record.get("action") == "created" and target.exists():
        target.unlink()
        print(f"Removed installed Engine.ini -> {target}")


def install(game_root: Path) -> None:
    if not SOURCE_MOD_DIR.exists():
        raise SystemExit(f"Missing source mod directory: {SOURCE_MOD_DIR}")

    p = game_paths(game_root)
    problems = verify_ue4ss(p)
    if problems:
        print("Cannot install — fix these first:")
        for prob in problems:
            print(f"  - {prob}")
        raise SystemExit(1)

    target = p["target_mod"]
    if target.exists():
        shutil.rmtree(target)
    target.mkdir(parents=True, exist_ok=True)
    copied = copy_mod_files(SOURCE_MOD_DIR, target)
    mods_txt_record = enable_in_mods_txt(p["mods_txt"])
    engine_record = install_engine_ini()

    manifest = {
        "mod": MOD_NAME,
        "source": str(SOURCE_MOD_DIR),
        "target": str(target),
        "installed_at": datetime.now().isoformat(timespec="seconds"),
        "files": copied,
        "mods_txt": mods_txt_record,
        "engine_ini": engine_record,
    }
    (target / MANIFEST_NAME).write_text(json.dumps(manifest, indent=2), encoding="utf-8")

    print(f"Installed {MOD_NAME} -> {target}  ({len(copied)} files)")
    print(f"mods.txt: {mods_txt_record['action']}  ({p['mods_txt']})")
    print(f"Engine.ini (anti-lag): {engine_record['action']}  ({engine_record['path']})")
    print()
    print("Done. Launch the game through Steam. The mod runs on the HOST only.")
    print("Host keybinds: Ctrl+G gather | Ctrl+J reload | Ctrl+O elevator probe "
          "| Ctrl+P board elevator")
    print("Release build disables Ctrl+K/L level-test keys by default; see main.lua toggles.")


def uninstall(game_root: Path) -> None:
    p = game_paths(game_root)
    target = p["target_mod"]
    manifest_path = target / MANIFEST_NAME
    manifest = None
    if manifest_path.exists():
        try:
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        except Exception:
            manifest = None

    # Restore Engine.ini from the manifest record if we have one.
    if manifest:
        restore_engine_ini(manifest.get("engine_ini"))
        restore_mods_txt(manifest.get("mods_txt"))
        print(f"Restored {MOD_NAME} mods.txt state")
    else:
        print("No install manifest found; leaving mods.txt/Engine.ini untouched")

    if target.exists():
        shutil.rmtree(target)
        print(f"Removed {target}")
    else:
        print(f"Mod folder already absent: {target}")
    print("Uninstall complete (reversible changes restored).")


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Install or remove the BETPlayerCap UE4SS mod (+ anti-lag Engine.ini).")
    parser.add_argument("action", choices=["install", "uninstall"])
    parser.add_argument(
        "--game-root", type=Path, default=DEFAULT_GAME_ROOT,
        help="Game install root (the folder containing BET/Binaries/Win64).")
    args = parser.parse_args()

    game_root = args.game_root.resolve()
    if args.action == "install":
        install(game_root)
    else:
        uninstall(game_root)


if __name__ == "__main__":
    main()
