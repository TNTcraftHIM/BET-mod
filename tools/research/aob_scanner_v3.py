import os
"""
BET-specific AOB discovery via string cross-references.
Since PatternSleuth's generic patterns all fail, we find functions
by tracing string references in the executable.
"""

import struct
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_GAME_ROOT = Path(os.environ.get(
    "BET_GAME_ROOT",
    r"F:\Steam\steamapps\common\Backrooms_Escape_Together",
))

EXE_PATH = DEFAULT_GAME_ROOT / "BET" / "Binaries" / "Win64" / "BETGameSteam-Win64-Shipping.exe"

def load_exe():
    with open(EXE_PATH, "rb") as f:
        data = f.read()
    return data

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

def va_to_file(sections, image_base, va):
    rva = va - image_base
    for sec in sections:
        if rva >= sec['va'] and rva < sec['va'] + sec['vsize']:
            return sec['raw'] + (rva - sec['va'])
    return None

def find_string(data, s, enc='utf-16-le'):
    encoded = s.encode(enc)
    results = []
    start = 0
    while True:
        idx = data.find(encoded, start)
        if idx == -1:
            break
        results.append(idx)
        start = idx + 1
    return results

def find_lea_xrefs_to_va(data, sections, image_base, target_va, search_range=None):
    """Find all LEA instructions that reference target_va via RIP-relative addressing."""
    # Search .text section
    text_sec = None
    for sec in sections:
        if sec['name'] == '.text':
            text_sec = sec
            break

    if not text_sec:
        return []

    results = []
    start = text_sec['raw']
    end = start + text_sec['rawsz']
    if search_range:
        start = max(start, search_range[0])
        end = min(end, search_range[1])

    for i in range(start, min(end, len(data)) - 7):
        # LEA r64, [rip + rel32]
        # REX.W LEA: 48 8D xx, or 4C 8D xx
        b0 = data[i]
        b1 = data[i+1]
        b2 = data[i+2]

        is_lea = False
        if (b0 == 0x48 or b0 == 0x4C) and b1 == 0x8D:
            modrm_mod = (b2 >> 6) & 3
            modrm_rm = b2 & 7
            if modrm_mod == 0 and modrm_rm == 5:  # [rip + disp32]
                is_lea = True

        if not is_lea:
            # Also check MOV r64, [rip + disp32]
            if (b0 == 0x48 or b0 == 0x4C) and b1 == 0x8B:
                modrm_mod = (b2 >> 6) & 3
                modrm_rm = b2 & 7
                if modrm_mod == 0 and modrm_rm == 5:
                    is_lea = True

        if is_lea:
            rel32 = struct.unpack_from('<i', data, i + 3)[0]
            inst_va = file_to_va(sections, image_base, i)
            if inst_va:
                resolved = inst_va + 7 + rel32
                if resolved == target_va:
                    results.append(i)

    return results

def find_function_start(data, offset, max_search=0x1000):
    """Walk backwards looking for function prologue."""
    # Common prologue patterns
    prologues = [
        b'\x40\x53',           # push rbx
        b'\x40\x55',           # push rbp
        b'\x40\x57',           # push rdi
        b'\x40\x56',           # push rsi
        b'\x55',               # push rbp
        b'\x53',               # push rbx
        b'\x56',               # push rsi
        b'\x57',               # push rdi
        b'\x41\x54',           # push r12
        b'\x41\x55',           # push r13
        b'\x41\x56',           # push r14
        b'\x41\x57',           # push r15
    ]

    start = max(0, offset - max_search)
    for i in range(offset, start, -1):
        # Check for padding/terminator before prologue
        prev_byte = data[i-1] if i > 0 else 0xCC
        if prev_byte in (0xCC, 0xC3, 0x90, 0xEB, 0x00):
            for pat in prologues:
                if data[i:i+len(pat)] == pat:
                    return i
        # Also check for INT3 (0xCC) block
        if i > 2 and data[i-2:i] == b'\xCC\xCC':
            for pat in prologues:
                if data[i:i+len(pat)] == pat:
                    return i

    return None

def bytes_hex(data, offset, length):
    return ' '.join(f'{b:02X}' for b in data[offset:offset+length])

def main():
    data = load_exe()
    image_base, sections = parse_pe(data)
    print(f"Image base: 0x{image_base:X}")

    # ========================================================
    # 1. Find FName::FName(wchar_t*) via "TGPUSkinVertexFactoryUnlimited"
    # ========================================================
    print("\n" + "=" * 70)
    print("1. Finding FName::FName(wchar_t*)")
    print("=" * 70)

    # Find the string
    str_hits = find_string(data, "TGPUSkinVertexFactoryUnlimited\0")
    print(f"  'TGPUSkinVertexFactoryUnlimited' UTF-16 at: {[hex(h) for h in str_hits]}")

    for str_off in str_hits[:2]:
        str_va = file_to_va(sections, image_base, str_off)
        print(f"  String VA: 0x{str_va:X}")

        # Find LEA instructions pointing to this string
        xrefs = find_lea_xrefs_to_va(data, sections, image_base, str_va)
        print(f"  LEA xrefs: {[hex(x) for x in xrefs[:10]]}")

        for xref in xrefs[:5]:
            print(f"\n  Xref at file 0x{xref:X} (VA 0x{file_to_va(sections, image_base, xref):X}):")
            print(f"    Context before: {bytes_hex(data, max(0, xref-16), 48)}")
            print(f"    Context after:  {bytes_hex(data, xref, 48)}")

            # Find function start
            fn_start = find_function_start(data, xref)
            if fn_start:
                fn_va = file_to_va(sections, image_base, fn_start)
                print(f"    Possible function at file 0x{fn_start:X} (VA 0x{fn_va:X})")
                print(f"    Prologue: {bytes_hex(data, fn_start, 32)}")

    # ========================================================
    # 2. Find StaticConstructObject_Internal via "NewObject with empty name"
    # ========================================================
    print("\n" + "=" * 70)
    print("2. Finding StaticConstructObject_Internal")
    print("=" * 70)

    str_hits = find_string(data, "NewObject with empty name")
    print(f"  'NewObject with empty name' UTF-16 at: {[hex(h) for h in str_hits]}")

    for str_off in str_hits[:2]:
        str_va = file_to_va(sections, image_base, str_off)
        print(f"  String VA: 0x{str_va:X}")

        xrefs = find_lea_xrefs_to_va(data, sections, image_base, str_va)
        print(f"  LEA xrefs: {[hex(x) for x in xrefs[:10]]}")

        for xref in xrefs[:5]:
            print(f"\n  Xref at file 0x{xref:X} (VA 0x{file_to_va(sections, image_base, xref):X}):")
            print(f"    Context: {bytes_hex(data, max(0, xref-16), 64)}")

            fn_start = find_function_start(data, xref)
            if fn_start:
                fn_va = file_to_va(sections, image_base, fn_start)
                print(f"    Function at file 0x{fn_start:X} (VA 0x{fn_va:X})")
                print(f"    Prologue: {bytes_hex(data, fn_start, 32)}")

                # This function (NewObject) calls StaticConstructObject_Internal
                # Look for CALL instructions within the function
                fn_bytes = data[fn_start:fn_start+0x1000]
                calls = []
                for j in range(len(fn_bytes) - 5):
                    if fn_bytes[j] == 0xE8:  # CALL rel32
                        rel32 = struct.unpack_from('<i', fn_bytes, j+1)[0]
                        call_va = file_to_va(sections, image_base, fn_start + j)
                        if call_va:
                            target_va = call_va + 5 + rel32
                            target_file = va_to_file(sections, image_base, target_va)
                            if target_file:
                                calls.append((j, fn_start + j, target_file, target_va))

                print(f"    CALLs in function ({len(calls)} total):")
                for call_off, call_file, target_file, target_va in calls[:20]:
                    target_start = find_function_start(data, target_file)
                    print(f"      CALL at +0x{call_off:X} -> VA 0x{target_va:X} (file 0x{target_file:X})")
                    if target_start:
                        print(f"        -> function at 0x{target_start:X}: {bytes_hex(data, target_start, 24)}")

    # ========================================================
    # 3. Find FUObjectHashTables::Get() via "Hash efficiency statistics"
    # ========================================================
    print("\n" + "=" * 70)
    print("3. Finding FUObjectHashTables::Get()")
    print("=" * 70)

    # Try various strings
    for search_str in ["Hash efficiency statistics", "FUObjectHashTables", "HashObject", "HashToObject"]:
        hits = find_string(data, search_str)
        if hits:
            print(f"  '{search_str}' UTF-16 at: {[hex(h) for h in hits]}")
            for str_off in hits[:2]:
                str_va = file_to_va(sections, image_base, str_off)
                xrefs = find_lea_xrefs_to_va(data, sections, image_base, str_va)
                print(f"    LEA xrefs: {[hex(x) for x in xrefs[:5]]}")
                for xref in xrefs[:3]:
                    fn_start = find_function_start(data, xref)
                    if fn_start:
                        fn_va = file_to_va(sections, image_base, fn_start)
                        print(f"    Function at file 0x{fn_start:X} (VA 0x{fn_va:X}): {bytes_hex(data, fn_start, 24)}")

    # ========================================================
    # 4. Find GNatives via FFrame::Step
    # ========================================================
    print("\n" + "=" * 70)
    print("4. Finding GNatives")
    print("=" * 70)

    # FFrame::Step has a distinctive pattern:
    # mov rax, [rcx+0x20]   ; 48 8B 41 20
    # mov r10, rdx          ; 4C 8B D2
    # mov rdx, rcx          ; 48 8B D1
    # movzx r9d, byte [rax] ; 44 0F B6 08
    # inc rax               ; 48 FF C0
    # mov [rcx+0x20], rax   ; 48 89 41 20
    # mov r8d, r9d          ; 41 8B C1
    # lea r9, [rip+GNatives] ; 4C 8D 0D xx xx xx xx
    # mov rcx, r10          ; 49 8B CA
    # jmp [rcx + rax*8]     ; 49 FF 24 C1

    # Search for the beginning of this pattern with relaxed wildcards
    step_patterns = [
        "48 8B 41 20 4C 8B D2 48 8B D1 44 0F B6 08 48 FF C0 48 89 41 20 41 8B C1",
        "48 8B 41 ?? 4C 8B D2 48 8B D1 44 0F B6 08",
        "48 8B 41 20 4C 8B D2",
    ]

    for pat in step_patterns:
        parts = pat.split()
        length = len(parts)
        mask = bytearray(length)
        pat_bytes = bytearray(length)
        for i, p in enumerate(parts):
            if p == '??':
                mask[i] = 0
            else:
                mask[i] = 1
                pat_bytes[i] = int(p, 16)

        results = []
        for i in range(len(data) - length):
            match = True
            for j in range(length):
                if mask[j] and data[i+j] != pat_bytes[j]:
                    match = False
                    break
            if match:
                results.append(i)

        if results:
            print(f"  Pattern '{pat[:40]}...': {len(results)} matches")
            for r in results[:5]:
                print(f"    At 0x{r:X} (VA 0x{file_to_va(sections, image_base, r):X})")
                print(f"    Bytes: {bytes_hex(data, r, 60)}")
                # Look for LEA r9, [rip+...] after this point (4C 8D 0D)
                fn_bytes = data[r:r+60]
                for j in range(len(fn_bytes) - 7):
                    if fn_bytes[j] == 0x4C and fn_bytes[j+1] == 0x8D and fn_bytes[j+2] == 0x0D:
                        rel32 = struct.unpack_from('<i', fn_bytes, j+3)[0]
                        lea_va = file_to_va(sections, image_base, r + j)
                        if lea_va:
                            target_va = lea_va + 7 + rel32
                            target_file = va_to_file(sections, image_base, target_va)
                            print(f"    LEA r9, [rip+0x{rel32:X}] at +0x{j:X} -> GNatives at VA 0x{target_va:X} (file 0x{target_file or 0:X})")
                            if target_file:
                                # Check what's at the target - should be a table of pointers
                                print(f"    First 8 pointers at target:")
                                for k in range(8):
                                    ptr = struct.unpack_from('<Q', data, target_file + k*8)[0]
                                    print(f"      [{k}] = 0x{ptr:X}")
            break

    print("\nDone.")

if __name__ == '__main__':
    main()
