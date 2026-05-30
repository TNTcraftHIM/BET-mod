#!/usr/bin/env python3
from __future__ import annotations

import argparse
from dataclasses import dataclass
from pathlib import Path

DEFAULT_GAME_ROOT = Path(r"F:\Steam\steamapps\common\Backrooms_Escape_Together")
TARGET_FILES = [
    Path("BET/Binaries/Win64/BETGameSteam-Win64-Shipping.exe"),
    Path("BetGame.exe"),
    Path("BET/Content/Paks/BET-Windows.pak"),
    Path("BET/Content/Paks/BET-Windows.ucas"),
    Path("BET/Content/Paks/BET-Windows.utoc"),
    Path("BET/Content/Paks/global.utoc"),
]
TERMS = [
    "DefaultMaxPlayers",
    "MinSelectablePlayers",
    "MaxSelectablePlayers",
    "SelectedMaxPlayers",
    "ClampMaxPlayers",
    "IncreaseMaxPlayers",
    "DecreaseMaxPlayers",
    "GetMaxPlayersText",
    "MaxPlayersValueText",
    "UBETMultiplayerSettingsWidget",
    "CreateGameBaseWidget.cpp",
    "Session.MaxPlayers",
    "EOS_SessionModification_SetMaxPlayers",
    "NumPublicConnections",
    "PublicConnections",
    "MaxPublicConnections",
    "CreateSession",
    "TryGetActiveSessionPopulation",
    "TryGetSessionIntSetting",
    "net.MaxPlayersOverride",
    "Server full",
    "BP_LobbyGameMode",
    "BP_LobbyPlayerController",
    "WBP_MultiplayerSettings",
    "WBP_MultiplayerLobbyView",
]


@dataclass
class Hit:
    rel_path: Path
    term: str
    encoding: str
    offset: int
    snippet: str


def printable(data: bytes) -> str:
    return "".join(chr(b) if 32 <= b < 127 else "." for b in data)


def scan_file(root: Path, rel: Path, max_hits_per_term: int, context: int) -> list[Hit]:
    path = root / rel
    if not path.exists():
        return []
    data = path.read_bytes()
    hits: list[Hit] = []
    for term in TERMS:
        for encoding, needle in [("ascii", term.encode("utf-8")), ("utf16le", term.encode("utf-16le"))]:
            start = 0
            count = 0
            while count < max_hits_per_term:
                idx = data.find(needle, start)
                if idx < 0:
                    break
                s = max(0, idx - context)
                e = min(len(data), idx + len(needle) + context)
                hits.append(Hit(rel, term, encoding, idx, printable(data[s:e])))
                start = idx + max(1, len(needle))
                count += 1
    return hits


def write_doc(path: Path, root: Path, hits: list[Hit]) -> None:
    by_file: dict[Path, list[Hit]] = {}
    for hit in hits:
        by_file.setdefault(hit.rel_path, []).append(hit)

    lines = [
        "# BET player-cap findings",
        "",
        f"Generated from game root: `{root}`",
        "",
        "## Interpretation",
        "",
        "The strongest evidence points to a cap implemented across the multiplayer settings UI and online session creation path, not a plain exposed config value.",
        "The built-in Unreal cvar `net.MaxPlayersOverride` exists and should be tested first because it is reversible, but it may not update the UI or EOS/Steam lobby advertised slots.",
        "",
        "## Hits",
        "",
    ]
    for rel, rel_hits in by_file.items():
        lines.append(f"### `{rel}`")
        lines.append("")
        for hit in rel_hits:
            lines.append(f"- `{hit.term}` `{hit.encoding}` offset `{hit.offset}`")
            lines.append(f"  - `{hit.snippet[:500]}`")
        lines.append("")

    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines), "utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description="Scan BET files for player-cap and session strings.")
    parser.add_argument("--game-root", type=Path, default=DEFAULT_GAME_ROOT)
    parser.add_argument("--max-hits-per-term", type=int, default=6)
    parser.add_argument("--context", type=int, default=180)
    parser.add_argument("--write-doc", type=Path)
    args = parser.parse_args()

    hits: list[Hit] = []
    for rel in TARGET_FILES:
        file_hits = scan_file(args.game_root, rel, args.max_hits_per_term, args.context)
        hits.extend(file_hits)
        print(f"{rel}: {len(file_hits)} hits")
        for hit in file_hits[:40]:
            print(f"  {hit.offset:>12} {hit.encoding:<7} {hit.term} :: {hit.snippet[:180]}")
        if len(file_hits) > 40:
            print(f"  ... {len(file_hits) - 40} more")

    print(f"\nTotal hits: {len(hits)}")
    if args.write_doc:
        write_doc(args.write_doc, args.game_root, hits)
        print(f"Wrote {args.write_doc}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
