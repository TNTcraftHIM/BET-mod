#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
from pathlib import Path

DEFAULT_GAME_ROOT = Path(r"F:\Steam\steamapps\common\Backrooms_Escape_Together")
EXPECTED_FILES = [
    Path("BetGame.exe"),
    Path("BET/Binaries/Win64/BETGameSteam-Win64-Shipping.exe"),
    Path("BET/Content/Paks/BET-Windows.pak"),
    Path("BET/Content/Paks/BET-Windows.ucas"),
    Path("BET/Content/Paks/BET-Windows.utoc"),
    Path("BET/Content/Paks/BET-Windows.sig"),
    Path("Engine/Binaries/Win64/EOSSDK-Win64-Shipping.dll"),
    Path("Engine/Binaries/ThirdParty/Steamworks/Steamv161/Win64/steam_api64.dll"),
]
ANTI_CHEAT_MARKERS = [
    "EasyAntiCheat",
    "EasyAntiCheat_EOS",
    "EAC",
    "BattlEye",
    "BEClient",
    "BEService",
    "FACEIT",
    "Vanguard",
]
VERSION_TERMS = [
    b"++UE5+Release-5.3",
    b"++UE5+Release-5.4",
    b"++UE5+Release-5.5",
    b"UnrealEngine/Engine",
    b"BuildAgent",
    b"UE5",
]


def sha256_prefix(path: Path, length: int = 16) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()[:length]


def find_term_offsets(data: bytes, term: bytes, limit: int = 5) -> list[int]:
    offsets: list[int] = []
    start = 0
    while len(offsets) < limit:
        idx = data.find(term, start)
        if idx < 0:
            break
        offsets.append(idx)
        start = idx + max(1, len(term))
    return offsets


def main() -> int:
    parser = argparse.ArgumentParser(description="Verify Backrooms Escape Together install for BET player-cap modding.")
    parser.add_argument("--game-root", type=Path, default=DEFAULT_GAME_ROOT)
    args = parser.parse_args()

    root = args.game_root
    print(f"Game root: {root}")
    print(f"Exists: {root.exists()}")
    if not root.exists():
        return 2

    print("\nExpected files:")
    for rel in EXPECTED_FILES:
        path = root / rel
        if path.exists():
            print(f"[OK] {rel} size={path.stat().st_size} sha256={sha256_prefix(path)}")
        else:
            print(f"[MISSING] {rel}")

    exe = root / "BET/Binaries/Win64/BETGameSteam-Win64-Shipping.exe"
    if exe.exists():
        data = exe.read_bytes()
        print("\nExecutable version/build clues:")
        for term in VERSION_TERMS:
            ascii_hits = find_term_offsets(data, term, 3)
            utf16_hits = find_term_offsets(data, term.decode("ascii", "ignore").encode("utf-16le"), 3)
            if ascii_hits or utf16_hits:
                print(f"{term.decode('ascii', 'ignore')}: ascii={ascii_hits} utf16={utf16_hits}")

    print("\nAnti-cheat marker filename scan:")
    marker_hits = []
    lower_markers = [m.lower() for m in ANTI_CHEAT_MARKERS]
    for path in root.rglob("*"):
        rel = path.relative_to(root)
        name = str(rel).lower()
        if any(marker.lower() in name for marker in lower_markers):
            marker_hits.append(rel)
    if marker_hits:
        for hit in marker_hits:
            print(f"[FOUND] {hit}")
    else:
        print("No obvious EasyAntiCheat/BattlEye-style filenames found.")

    print("\nImportant plugin/package hints:")
    for rel in [Path("Manifest_UFSFiles_Win64.txt"), Path("Manifest_NonUFSFiles_Win64.txt")]:
        path = root / rel
        if not path.exists():
            continue
        text = path.read_text("utf-8", "replace")
        for needle in ["EOS", "Online", "Session", "Lobby", "Steam", "VoiceChat"]:
            count = text.lower().count(needle.lower())
            if count:
                print(f"{rel}: {needle} x{count}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
