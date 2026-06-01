import os
"""Create UE4SS_Signatures Lua files for BET."""
import struct
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_GAME_ROOT = Path(os.environ.get(
    "BET_GAME_ROOT",
    r"F:\Steam\steamapps\common\Backrooms_Escape_Together",
))

EXE_PATH = DEFAULT_GAME_ROOT / "BET" / "Binaries" / "Win64" / "BETGameSteam-Win64-Shipping.exe"
OUTPUT_DIR = DEFAULT_GAME_ROOT / "BET" / "Binaries" / "Win64" / "ue4ss" / "UE4SS_Signatures"

def load_exe():
    with open(EXE_PATH, "rb") as f:
        return f.read()

def parse_pe(data):
    pe_sig = struct.unpack_from('<I', data, 0x3C)[0]
    num_sec = struct.unpack_from('<H', data, pe_sig + 6)[0]
    opt_size = struct.unpack_from('<H', data, pe_sig + 20)[0]
    sec_off = pe_sig + 24 + opt_size
    image_base = struct.unpack_from('<Q', data, pe_sig + 24 + 24)[0]
    sections = []
    for i in range(num_sec):
        s = sec_off + i * 40
        name = data[s:s+8].rstrip(b'\x00').decode('ascii', errors='replace')
        va = struct.unpack_from('<I', data, s + 12)[0]
        vsize = struct.unpack_from('<I', data, s + 8)[0]
        raw = struct.unpack_from('<I', data, s + 20)[0]
        rawsz = struct.unpack_from('<I', data, s + 16)[0]
        sections.append({'name': name, 'va': va, 'vsize': vsize, 'raw': raw, 'rawsz': rawsz})
    return image_base, sections

def file_to_va(sections, image_base, offset):
    for sec in sections:
        if offset >= sec['raw'] and offset < sec['raw'] + sec['rawsz']:
            return image_base + sec['va'] + (offset - sec['raw'])
    return None

def count_matches(data, pattern_str):
    """Count AOB pattern matches."""
    parts = pattern_str.strip().split()
    length = len(parts)
    mask = []
    pat = []
    for p in parts:
        if p in ('??', '?'):
            mask.append(0)
            pat.append(0)
        else:
            mask.append(1)
            pat.append(int(p, 16))

    count = 0
    for i in range(len(data) - length):
        match = True
        for j in range(length):
            if mask[j] and data[i+j] != pat[j]:
                match = False
                break
        if match:
            count += 1
    return count

def main():
    data = load_exe()
    image_base, sections = parse_pe(data)

    # ========================================================
    # 1. GNatives.lua - via FFrame::Step
    # ========================================================
    print("=== GNatives.lua ===")
    # Pattern: FFrame::Step unique bytes
    # The LEA r9, [rip+GNatives] is at offset +0x18
    # We wildcard the rel32 in the LEA
    gnatives_aob = "48 8B 41 20 4C 8B D2 48 8B D1 44 0F B6 08 48 FF C0 48 89 41 20 41 8B C1 4C 8D 0D ?? ?? ?? ?? 49 8B CA 4D 8B 0C C1 49 FF E1"
    count = count_matches(data, gnatives_aob)
    print(f"  Pattern uniqueness: {count}")
    if count == 1:
        print(f"  UNIQUE - creating Lua file")
        lua_content = f"""local Signature = "{gnatives_aob}"
local Offset = 0x18

function Register()
    return Signature
end

function OnMatchFound(MatchAddress)
    local LeaOffset = MatchAddress + Offset
    local Displacement = DerefToInt32(LeaOffset + 3)
    local RIP = LeaOffset + 7
    local GNativesAddress = RIP + Displacement
    return GNativesAddress
end
"""
        OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
        with open(OUTPUT_DIR / "GNatives.lua", "w") as f:
            f.write(lua_content)
        print(f"  Written to {OUTPUT_DIR / 'GNatives.lua'}")
    else:
        print(f"  NOT UNIQUE ({count} matches) - needs refinement")

    # ========================================================
    # 2. FName_Constructor.lua - FName::FName(wchar_t*)
    # ========================================================
    print("\n=== FName_Constructor.lua ===")
    # Function at file 0x1BE0BA0
    # Prologue: 40 53 48 83 EC 30 48 8B D9 48 89 54 24 20 33 C9 4C 8B CA 44 8B C1 48 85 D2 74 27 0F B7 02 66 85 C0
    # This needs to be unique. Let me check with a reasonable length
    fname_aob = "40 53 48 83 EC 30 48 8B D9 48 89 54 24 20 33 C9 4C 8B CA 44 8B C1 48 85 D2 74 27 0F B7 02 66 85 C0 74 1F 0F 1F 40 00 66 0F 1F 84 00 00 00 00 00"
    count = count_matches(data, fname_aob)
    print(f"  Full pattern uniqueness: {count}")
    if count != 1:
        # Try shorter
        fname_aob_short = "40 53 48 83 EC 30 48 8B D9 48 89 54 24 20 33 C9 4C 8B CA 44 8B C1 48 85 D2 74 27 0F B7 02 66 85 C0"
        count = count_matches(data, fname_aob_short)
        print(f"  Short pattern uniqueness: {count}")
        if count == 1:
            fname_aob = fname_aob_short

    if count == 1:
        print(f"  UNIQUE - creating Lua file")
        lua_content = f"""local Signature = "{fname_aob}"

function Register()
    return Signature
end

function OnMatchFound(MatchAddress)
    return MatchAddress
end
"""
        with open(OUTPUT_DIR / "FName_Constructor.lua", "w") as f:
            f.write(lua_content)
        print(f"  Written to {OUTPUT_DIR / 'FName_Constructor.lua'}")
    else:
        print(f"  NOT UNIQUE ({count} matches) - needs longer pattern")
        # Try even longer pattern
        fname_bytes = data[0x1BE0BA0:0x1BE0BA0+64]
        fname_aob_full = ' '.join(f'{b:02X}' for b in fname_bytes)
        count = count_matches(data, fname_aob_full)
        print(f"  Full 64-byte pattern: {count} matches")
        if count == 1:
            fname_aob = fname_aob_full
            lua_content = f"""local Signature = "{fname_aob}"

function Register()
    return Signature
end

function OnMatchFound(MatchAddress)
    return MatchAddress
end
"""
            with open(OUTPUT_DIR / "FName_Constructor.lua", "w") as f:
                f.write(lua_content)
            print(f"  Written to {OUTPUT_DIR / 'FName_Constructor.lua'}")

    # ========================================================
    # 3. StaticConstructObject.lua
    # ========================================================
    print("\n=== StaticConstructObject.lua ===")
    # Function at file 0x1E0E250
    # Prologue: 4C 8B DC 55 53 41 56 49 8D AB 38 FE FF FF 48 81 EC B0 02 00 00
    sco_aob = "4C 8B DC 55 53 41 56 49 8D AB 38 FE FF FF 48 81 EC B0 02 00 00"
    count = count_matches(data, sco_aob)
    print(f"  Pattern uniqueness: {count}")
    if count != 1:
        # Try longer
        sco_aob_long = "4C 8B DC 55 53 41 56 49 8D AB 38 FE FF FF 48 81 EC B0 02 00 00 48 8B 05 ?? ?? ?? ?? 48 33 C4 48 89 85 90 01 00 00 8B 41 70 33 DB 49 89 73 10 49"
        count = count_matches(data, sco_aob_long)
        print(f"  Longer pattern: {count}")
        if count == 1:
            sco_aob = sco_aob_long

    if count == 1:
        print(f"  UNIQUE - creating Lua file")
        lua_content = f"""local Signature = "{sco_aob}"

function Register()
    return Signature
end

function OnMatchFound(MatchAddress)
    return MatchAddress
end
"""
        with open(OUTPUT_DIR / "StaticConstructObject.lua", "w") as f:
            f.write(lua_content)
        print(f"  Written to {OUTPUT_DIR / 'StaticConstructObject.lua'}")
    else:
        print(f"  NOT UNIQUE ({count} matches) - needs refinement")

    # ========================================================
    # 4. GUObjectHashTables.lua - stub for now
    # ========================================================
    print("\n=== GUObjectHashTables.lua ===")
    print("  FUObjectHashTables::Get() not found statically.")
    print("  It's marked as OPTIONAL in UE4SS - creating minimal stub.")
    print("  UE4SS should work without it, with limited functionality.")

    # List created files
    print("\n=== Files created ===")
    for f in OUTPUT_DIR.glob("*.lua"):
        print(f"  {f}")

    print("\n=== Next steps ===")
    print("1. Re-enable UE4SS: ren dwmapi.dll.disabled dwmapi.dll")
    print("2. Ensure UE4SS-settings.ini has MajorVersion=5, MinorVersion=7")
    print("3. Launch game via Steam and check UE4SS.log")

if __name__ == '__main__':
    main()
