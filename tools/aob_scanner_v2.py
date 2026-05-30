"""
Targeted AOB scanner for BET based on PatternSleuth's exact resolver patterns.
Scans for the patterns that PatternSleuth uses, plus alternative approaches.
"""

import struct
from pathlib import Path

EXE_PATH = Path(r"F:\Steam\steamapps\common\Backrooms_Escape_Together\BET\Binaries\Win64\BETGameSteam-Win64-Shipping.exe")

def load_exe():
    print(f"Loading {EXE_PATH.name}...")
    with open(EXE_PATH, "rb") as f:
        data = f.read()
    print(f"Loaded {len(data)} bytes.")
    return data

def find_pattern(data, pattern_str):
    """Match AOB pattern. | marks the capture point. ?? is wildcard."""
    # Parse the pattern, handling | marker
    capture_offset = None
    clean_parts = []
    raw_parts = pattern_str.strip().split()

    for i, part in enumerate(raw_parts):
        if part == '|':
            capture_offset = len(clean_parts)
            continue
        clean_parts.append(part)

    length = len(clean_parts)
    mask = bytearray(length)
    pattern = bytearray(length)
    for i, part in enumerate(clean_parts):
        if part in ('??', '?'):
            mask[i] = 0
            pattern[i] = 0
        else:
            mask[i] = 1
            pattern[i] = int(part, 16)

    results = []
    data_len = len(data)
    for i in range(data_len - length + 1):
        match = True
        for j in range(length):
            if mask[j] and data[i + j] != pattern[j]:
                match = False
                break
        if match:
            if capture_offset is not None:
                # Resolve RIP-relative address at capture point
                rel32 = struct.unpack_from('<i', data, i + capture_offset)[0]
                abs_addr = (i + capture_offset + 4) + rel32
                results.append((i, abs_addr, capture_offset))
            else:
                results.append((i, None, None))
    return results

def find_string(data, s, encoding='utf-16-le'):
    encoded = s.encode(encoding)
    results = []
    start = 0
    while True:
        idx = data.find(encoded, start)
        if idx == -1:
            break
        results.append(idx)
        start = idx + 1
    return results

def bytes_hex(data, offset, length=32):
    return ' '.join(f'{b:02X}' for b in data[offset:offset+length])

def main():
    data = load_exe()

    # PE sections for address calculation
    pe_sig_offset = struct.unpack_from('<I', data, 0x3C)[0]
    num_sections = struct.unpack_from('<H', data, pe_sig_offset + 6)[0]
    opt_header_size = struct.unpack_from('<H', data, pe_sig_offset + 20)[0]
    section_offset = pe_sig_offset + 24 + opt_header_size
    image_base = struct.unpack_from('<Q', data, pe_sig_offset + 24 + 24)[0]

    sections = []
    for i in range(num_sections):
        sec_start = section_offset + i * 40
        name = data[sec_start:sec_start+8].rstrip(b'\x00').decode('ascii', errors='replace')
        virtual_addr = struct.unpack_from('<I', data, sec_start + 12)[0]
        raw_offset = struct.unpack_from('<I', data, sec_start + 20)[0]
        raw_size = struct.unpack_from('<I', data, sec_start + 16)[0]
        sections.append({'name': name, 'va': virtual_addr, 'raw': raw_offset, 'size': raw_size})

    def file_to_rva(offset):
        for sec in sections:
            if offset >= sec['raw'] and offset < sec['raw'] + sec['size']:
                return sec['va'] + (offset - sec['raw'])
        return None

    def file_to_va(offset):
        rva = file_to_rva(offset)
        if rva is not None:
            return image_base + rva
        return None

    print(f"\nImage base: 0x{image_base:X}")
    print()

    # ========================================================
    # 1. FName::FName(wchar_t*)
    # ========================================================
    print("=" * 70)
    print("1. FName::FName(wchar_t*) - PatternSleuth patterns")
    print("=" * 70)

    # Pattern 1: EB 07 48 8D 15 ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? 41 B8 01 00 00 00 E8 | ?? ?? ?? ??
    fname_pat1 = "EB 07 48 8D 15 ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? 41 B8 01 00 00 00 E8 | ?? ?? ?? ??"
    matches = find_pattern(data, fname_pat1)
    print(f"\n  Pattern: {fname_pat1}")
    if matches:
        for off, target, cap in matches[:5]:
            print(f"  MATCH at file 0x{off:X} (VA 0x{file_to_va(off):X}) -> FName at VA 0x{target:X}")
            print(f"    Bytes: {bytes_hex(data, off, 40)}")
    else:
        print(f"  No matches")

    # String-based approach
    print("\n  String-based approach:")
    for s in ["TGPUSkinVertexFactoryUnlimited", "MovementComponent0"]:
        hits = find_string(data, s)
        if hits:
            print(f"  '{s}' at {[hex(h) for h in hits[:3]]}")
        else:
            print(f"  '{s}' NOT FOUND")

    # Alternative: Try broader FName patterns
    alt_patterns = [
        # Common FName call pattern: 41 B8 01 00 00 00 (mov r8d, 1) then call
        "41 B8 01 00 00 00 E8 | ?? ?? ?? ??",
        # FName(wchar_t*, EFindName) pattern
        "BA 01 00 00 00 E8 | ?? ?? ?? ??",
    ]
    for pat in alt_patterns:
        matches = find_pattern(data, pat)
        if matches and len(matches) < 50:
            print(f"\n  Alt pattern '{pat[:40]}...': {len(matches)} matches")
            for off, target, cap in matches[:3]:
                print(f"    0x{off:X} -> 0x{target:X}")

    # ========================================================
    # 2. StaticConstructObject_Internal
    # ========================================================
    print("\n" + "=" * 70)
    print("2. StaticConstructObject_Internal - PatternSleuth patterns")
    print("=" * 70)

    sco_patterns = [
        ("SCO_P1", "48 89 44 24 28 C7 44 24 20 00 00 00 00 E8 | ?? ?? ?? ?? 48 8B 5C 24 ?? 48 8B ?? 24"),
        ("SCO_P2", "E8 | ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? C0 E9 ?? 32 88 ?? ?? ?? ?? 80 E1 01 30 88 ?? ?? ?? ?? 48"),
        ("SCO_P3", "E8 | ?? ?? ?? ?? 48 8B D8 48 39 75 30 74 15"),
        ("SCO_P4", "c6 44 24 30 00 0f 57 c0 0f 11 44 24 38 4c 89 ff e8 | ?? ?? ?? ?? 48 89"),
    ]

    for name, pat in sco_patterns:
        matches = find_pattern(data, pat)
        print(f"\n  {name}: {pat[:60]}...")
        if matches:
            for off, target, cap in matches[:5]:
                print(f"  MATCH at 0x{off:X} -> 0x{target:X}")
                print(f"    Bytes: {bytes_hex(data, off, 40)}")
        else:
            print(f"  No matches")

    # String-based approach for SCO
    print("\n  String-based approach:")
    for s in ["UBehaviorTreeManager", "ULeaderboardFlushCallbackProxy", "UPlayMontageCallbackProxy"]:
        hits = find_string(data, s)
        if hits:
            print(f"  '{s}' found at {[hex(h) for h in hits[:3]]}")
        else:
            print(f"  '{s}' NOT FOUND")

    # Alternative: search for "NewObject with empty name"
    for s in ["NewObject with empty name", "StaticConstructObject"]:
        hits = find_string(data, s)
        if hits:
            print(f"  '{s}' at {[hex(h) for h in hits[:3]]}")

    # ========================================================
    # 3. FUObjectHashTables::Get()
    # ========================================================
    print("\n" + "=" * 70)
    print("3. FUObjectHashTables::Get() - PatternSleuth patterns")
    print("=" * 70)

    hash_patterns = [
        ("HASH_P1", "48 89 5C 24 08 48 89 6C 24 10 48 89 74 24 18 57 48 83 EC 40 41 0F B6 F9 49 8B D8 48 8B F2 48 8B E9 E8 | ?? ?? ?? ?? 44 8B 84 24 80 00 00 00 4C 8B CB 44 ?? ?? 24 ?? 48 8B D5 44 ?? 44 24 ?? ?? ?? ?? ?? ?? 44 ?? ?? 44 ?? ?? ?? ?? ?? 44 ?? ?? 24 ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? 48"),
        ("HASH_P2", "48 89 5C 24 08 48 89 74 24 10 4C 89 44 24 18 57 48 83 EC 40 41 0F B6 D9 48 8B FA 48 8B F1 E8 | ?? ?? ?? ?? 44 8B 84 24 80 00 00 00 48 8B D6 ?? 8B ?? 24 ?? 48 8B C8 ?? ?? ?? 24 ?? ?? ?? ?? ?? ?? 44 89 44 24 ?? 44 0F B6 44 24 70 44 ?? ?? 24 ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? 48 8B"),
        ("HASH_P3", "48 89 5C 24 08 48 89 6C 24 10 48 89 74 24 18 57 48 83 EC 40 41 0F B6 F9 49 8B D8 48 8B F2 48 8B E9 E8 | ?? ?? ?? ?? 44 8B 44 24 78 4C 8B CB 44 89 44 24 38 48 8B D5 44 8B 44 24 70 48 8B C8 44 89 44 24 30 4C 8B C6 C6 44 24 28 00 40 88 7C 24 20 E8 ?? ?? ?? ?? 48 8B 5C 24 50 48 8B 6C 24 58 48 8B 74 24 60"),
        ("HASH_P4", "e8 | ?? ?? ?? ?? 45 33 ff 48 8b f0 33 c0 f0 44 0f b1 3d"),
    ]

    for name, pat in hash_patterns:
        matches = find_pattern(data, pat)
        print(f"\n  {name}: {pat[:60]}...")
        if matches:
            for off, target, cap in matches[:5]:
                print(f"  MATCH at 0x{off:X} -> 0x{target:X}")
                print(f"    Bytes: {bytes_hex(data, off, 40)}")
        else:
            print(f"  No matches")

    # ========================================================
    # 4. GNatives
    # ========================================================
    print("\n" + "=" * 70)
    print("4. GNatives - PatternSleuth patterns")
    print("=" * 70)

    gnatives_pat = "80 3D ?? ?? ?? ?? 00 48 8D 15 ?? ?? ?? ?? 75 ?? C6 05 ?? ?? ?? ?? 01 48 8D 05 | ?? ?? ?? ?? B9"
    matches = find_pattern(data, gnatives_pat)
    print(f"\n  Pattern: {gnatives_pat}")
    if matches:
        for off, target, cap in matches[:5]:
            print(f"  MATCH at 0x{off:X} -> GNatives VA 0x{target:X}")
            print(f"    Bytes: {bytes_hex(data, off, 50)}")
    else:
        print(f"  No matches")

    # SkipFunction pattern
    print("\n  UObject::SkipFunction pattern:")
    skip_pat = "40 55 41 54 41 55 41 56 41 57 48 83 EC 30 48 8D 6C 24 20 48 89 5D 40 48 89 75 48 48 89 7D 50 48 8B 05 ?? ?? ?? ?? 48 33 C5 48 89 45 00 ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? 4D 8B ?? ?? 8B ?? 85 ?? 75 05 41 8B FC EB ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? 48 ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? 48 ?? E0"
    matches = find_pattern(data, skip_pat)
    if matches:
        print(f"  SkipFunction found at {[hex(off) for off, _, _ in matches[:5]]}")
        # Look for LEA r64, [rip+...] in the first 500 bytes
        for off, _, _ in matches[:1]:
            fn_bytes = data[off:off+500]
            print(f"  Scanning function for LEA [rip+...] instructions:")
            for i in range(len(fn_bytes) - 7):
                if fn_bytes[i] == 0x48 and fn_bytes[i+1] == 0x8D and fn_bytes[i+2] in (0x05, 0x0D, 0x15, 0x1D, 0x25, 0x2D, 0x35, 0x3D):
                    rel32 = struct.unpack_from('<i', fn_bytes, i+3)[0]
                    target = off + i + 7 + rel32
                    regs = ['rax', 'rcx', 'rdx', 'rbx', 'rsp', 'rbp', 'rsi', 'rdi']
                    reg = regs[(fn_bytes[i+2] >> 3) & 7]
                    print(f"    LEA {reg}, [rip+0x{rel32:X}] at 0x{off+i:X} -> VA 0x{target:X} (RVA 0x{file_to_rva(target) or 0:X})")
    else:
        print(f"  No matches")

    # ========================================================
    # 5. Summary & custom pattern suggestions
    # ========================================================
    print("\n" + "=" * 70)
    print("5. Alternative pattern search for BET-specific signatures")
    print("=" * 70)

    # For FName: search for specific FNamePool-related strings
    # and find cross-references
    print("\n  FNamePool approach:")
    for s in ["\0Engine\0", "\0Renderer\0", "\0AnimGraphRuntime\0", "\0Landscape\0", "\0RenderCore\0"]:
        hits = find_string(data, s)
        if hits:
            print(f"    UTF8 '{s.strip(chr(0))}': {[hex(h) for h in hits[:3]]}")

    # Search for "ByteProperty", "IntProperty" etc (used in FNamePool constructor)
    print("\n  FNamePool EName strings:")
    for s in ["ByteProperty", "IntProperty", "BoolProperty", "FloatProperty"]:
        hits = find_string(data, s, 'utf-8')
        if hits:
            print(f"    '{s}': {[hex(h) for h in hits[:3]]}")

    # For GNatives: look for UObject::SkipFunction via alternative patterns
    print("\n  FFrame::Step pattern:")
    step_pat = "48 8B 41 20 4C 8B D2 48 8B D1 44 0F B6 08 48 FF C0 48 89 41 20 41 8B C1 4C 8D 0D ?? ?? ?? ?? 49 8B CA 49 FF 24 C1"
    matches = find_pattern(data, step_pat)
    if matches:
        print(f"  FFrame::Step at {[hex(off) for off, _, _ in matches[:3]]}")
        # This function has a jmp [rcx + rax*8] which references GNatives
        for off, _, _ in matches[:1]:
            # The 4C 8D 0D is LEA r9, [rip+...] - this is the GNatives reference
            fn_bytes = data[off:off+60]
            for i in range(len(fn_bytes) - 7):
                if fn_bytes[i] == 0x4C and fn_bytes[i+1] == 0x8D and fn_bytes[i+2] == 0x0D:
                    rel32 = struct.unpack_from('<i', fn_bytes, i+3)[0]
                    target = off + i + 7 + rel32
                    print(f"    LEA r9, [rip+0x{rel32:X}] at 0x{off+i:X} -> GNatives at VA 0x{file_to_va(target) or 0:X}")
    else:
        print(f"  No matches")

    print("\n  Done.")

if __name__ == '__main__':
    main()
