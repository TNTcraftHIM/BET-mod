from __future__ import annotations

import argparse
import json
import shutil
from datetime import datetime
from pathlib import Path

DEFAULT_GAME_ROOT = Path(r"F:\Steam\steamapps\common\Backrooms_Escape_Together")
MOD_NAME = "BETPlayerCap"
REPO_ROOT = Path(__file__).resolve().parents[1]
SOURCE_MOD_DIR = REPO_ROOT / "ue4ss_mods" / MOD_NAME
DEFAULT_GAME_BIN = DEFAULT_GAME_ROOT / "BET" / "Binaries" / "Win64"
DEFAULT_MODS_DIR = DEFAULT_GAME_BIN / "Mods"
MANIFEST_NAME = ".bet_player_cap_install.json"


def copy_tree(source: Path, target: Path) -> list[str]:
    copied: list[str] = []
    for path in source.rglob("*"):
        relative = path.relative_to(source)
        destination = target / relative
        if path.is_dir():
            destination.mkdir(parents=True, exist_ok=True)
            continue
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, destination)
        copied.append(str(relative).replace("\\", "/"))
    return copied


def install(mods_dir: Path) -> None:
    if not SOURCE_MOD_DIR.exists():
        raise SystemExit(f"Missing source mod directory: {SOURCE_MOD_DIR}")

    target = mods_dir / MOD_NAME
    target.mkdir(parents=True, exist_ok=True)
    copied = copy_tree(SOURCE_MOD_DIR, target)

    manifest = {
        "mod": MOD_NAME,
        "source": str(SOURCE_MOD_DIR),
        "target": str(target),
        "installed_at": datetime.now().isoformat(timespec="seconds"),
        "files": copied,
    }
    (target / MANIFEST_NAME).write_text(json.dumps(manifest, indent=2), encoding="utf-8")

    print(f"Installed {MOD_NAME} to {target}")
    print(f"Copied {len(copied)} files")
    print("Launch through Steam after UE4SS base install is verified.")


def uninstall(mods_dir: Path) -> None:
    target = mods_dir / MOD_NAME
    manifest_path = target / MANIFEST_NAME
    if not manifest_path.exists():
        raise SystemExit(f"Refusing to uninstall without manifest: {manifest_path}")

    shutil.rmtree(target)
    print(f"Removed {target}")


def main() -> None:
    parser = argparse.ArgumentParser(description="Install or remove the BETPlayerCap UE4SS Lua mod.")
    parser.add_argument("action", choices=["install", "uninstall"])
    parser.add_argument(
        "--mods-dir",
        type=Path,
        default=DEFAULT_MODS_DIR,
        help="UE4SS Mods directory. Defaults to the game's Win64/Mods directory.",
    )
    args = parser.parse_args()

    mods_dir = args.mods_dir.resolve()
    if args.action == "install":
        install(mods_dir)
    else:
        uninstall(mods_dir)


if __name__ == "__main__":
    main()
