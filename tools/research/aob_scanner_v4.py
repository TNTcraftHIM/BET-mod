import os
"""
Deep analysis of FName::FName and StaticConstructObject_Internal.
Uses string cross-refs to trace call chains.
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

def va_to_file(sections, image_base, va):
    rva = va - image_base
    for sec in sections:
        if rva >= sec['va'] and rva < sec['va'] + sec['vsize']:
            return sec['raw'] + (rva - sec['va'])
    return None

def bytes_hex(data, offset, length):
    return ' '.join(f'{b:02X}' for b in data[offset:offset+length])

def find_string(data, s, enc='utf-16-le'):
    return [i for i in range(0, len(data) - len(s.encode(enc)))
            if data[i:i+len(s.encode(enc))] == s.encode(enc)]

def find_lea_xrefs(data, sections, image_base, target_va):
    text_sec = [s for s in sections if s['name'] == '.text'][0]
    results = []
    start = text_sec['raw']
    end = start + text_sec['rawsz']
    for i in range(start, min(end, len(data)) - 7):
        b0, b1, b2 = data[i], data[i+1], data[i+2]
        if (b0 in (0x48, 0x4C)) and b1 in (0x8D, 0x8B):
            modrm_mod = (b2 >> 6) & 3
            modrm_rm = b2 & 7
            if modrm_mod == 0 and modrm_rm == 5:
                rel32 = struct.unpack_from('<i', data, i + 3)[0]
                inst_va = file_to_va(sections, image_base, i)
                if inst_va:
                    resolved = inst_va + 7 + rel32
                    if resolved == target_va:
                        results.append(i)
    return results

def resolve_rip(data, sections, image_base, offset):
    """Resolve a LEA or MOV with RIP-relative addressing."""
    inst_va = file_to_va(sections, image_base, offset)
    if inst_va is None:
        return None
    rel32 = struct.unpack_from('<i', data, offset + 3)[0]
    return inst_va + 7 + rel32

def find_calls_in_range(data, sections, image_base, start, length):
    """Find all CALL rel32 instructions in a range."""
    calls = []
    for i in range(start, start + length - 5):
        if data[i] == 0xE8:
            rel32 = struct.unpack_from('<i', data, i + 1)[0]
            call_va = file_to_va(sections, image_base, i)
            if call_va:
                target = call_va + 5 + rel32
                target_file = va_to_file(sections, image_base, target)
                calls.append((i, call_va, target, target_file))
    return calls

def main():
    data = load_exe()
    image_base, sections = parse_pe(data)

    # ========================================================
    # 1. FName::FName - deeper analysis around the string xref
    # ========================================================
    print("=" * 70)
    print("1. FName::FName(wchar_t*) - call chain analysis")
    print("=" * 70)

    # The xref was at file 0x17459A9 in function at 0x1745850
    # Let me dump more context around this area
    fn_start = 0x1745850
    print(f"\n  Function at 0x{fn_start:X}:")
    print(f"  Prologue: {bytes_hex(data, fn_start, 48)}")

    # Find all CALLs in the first 256 bytes of this function
    calls = find_calls_in_range(data, sections, image_base, fn_start, 256)
    print(f"\n  CALLs in first 256 bytes:")
    for call_off, call_va, target_va, target_file in calls:
        if target_file and target_file < len(data):
            prologue = bytes_hex(data, target_file, 24)
            print(f"    0x{call_off:X} (VA 0x{call_va:X}) -> VA 0x{target_va:X} (file 0x{target_file:X}): {prologue}")

    # Now look more specifically at the area around the string xref at 0x17459A9
    xref_off = 0x17459A9
    print(f"\n  Context around xref at 0x{xref_off:X} (256 bytes):")
    for i in range(max(fn_start, xref_off - 64), xref_off + 128):
        if data[i] == 0xE8:
            rel32 = struct.unpack_from('<i', data, i + 1)[0]
            call_va = file_to_va(sections, image_base, i)
            if call_va:
                target = call_va + 5 + rel32
                target_file = va_to_file(sections, image_base, target)
                if target_file:
                    print(f"    CALL at 0x{i:X} -> VA 0x{target:X} (file 0x{target_file:X})")

    # ========================================================
    # 2. StaticConstructObject - trace from NewObject
    # ========================================================
    print("\n" + "=" * 70)
    print("2. StaticConstructObject_Internal")
    print("=" * 70)

    # The first NewObject function was at 0x1C69B90
    # It called 0x1A467B0 (StaticConstructObject candidate)
    # Let me check 0x1A467B0 more carefully

    # PatternSleuth looks for 0x10000080 (RF_DefaultSubObject | RF_ArchetypeObject)
    # in StaticConstructObject_Internal
    # Let me search for this constant in the code

    # Search for "mov dword, 0x10000080" patterns: C7 ?? ?? 80 00 00 10
    # Or as an immediate in CMP: 3D 80 00 00 10 or 81 ?? 80 00 00 10
    print("\n  Searching for 0x10000080 constant in code...")

    text_sec = [s for s in sections if s['name'] == '.text'][0]
    count = 0
    candidates = []
    for i in range(text_sec['raw'], text_sec['raw'] + text_sec['rawsz'] - 4):
        # Check for 80 00 00 10 (little-endian of 0x10000080) as an immediate
        if data[i:i+4] == b'\x80\x00\x00\x10':
            # Verify this looks like an instruction operand, not data
            prev_byte = data[i-1] if i > 0 else 0
            # CMP imm32: 3D or 81 /7 or 80 /7
            # MOV [mem], imm32: C7 /0
            # OR: 81 /1
            if prev_byte in (0x3D, 0xC7, 0x81, 0x80, 0x83):
                fn = find_function_start_simple(data, i)
                if fn:
                    candidates.append((i, fn))
                    if len(candidates) <= 20:
                        print(f"    0x{i:X}: near fn 0x{fn:X}: {bytes_hex(data, fn, 24)}")

    # Also check for the constant in the candidate functions
    sco_candidate = 0x1A457B0
    print(f"\n  Checking SCO candidate at 0x{sco_candidate:X}:")
    print(f"  Prologue: {bytes_hex(data, sco_candidate, 32)}")

    # Search for 0x10000080 in this function (first 0x2000 bytes)
    for i in range(sco_candidate, sco_candidate + 0x2000):
        if data[i:i+4] == b'\x80\x00\x00\x10':
            print(f"    0x10000080 at offset +0x{i - sco_candidate:X} (file 0x{i:X})")

    # Let me also check which of the NewObject callees has 0x10000080
    print("\n  Checking NewObject callees for 0x10000080:")
    no_fn = 0x1C69B90
    calls = find_calls_in_range(data, sections, image_base, no_fn, 0x500)
    for call_off, call_va, target_va, target_file in calls:
        if target_file:
            found = False
            for i in range(target_file, target_file + 0x3000):
                if i < len(data) - 4 and data[i:i+4] == b'\x80\x00\x00\x10':
                    found = True
                    break
            if found:
                print(f"    0x{target_file:X}: HAS 0x10000080")
                print(f"      Prologue: {bytes_hex(data, target_file, 24)}")

    # ========================================================
    # 3. FUObjectHashTables - alternative approach
    # ========================================================
    print("\n" + "=" * 70)
    print("3. FUObjectHashTables::Get() - alternative approaches")
    print("=" * 70)

    # FUObjectHashTables::Get() is a singleton getter.
    # It typically returns a static local.
    # Pattern: lea rax, [rip+static_var]; test rax,rax; jnz skip; call init; skip: ret

    # Let me search for functions that reference GUObjectArray
    # We know GUObjectArray was found at 0x7ff795e295d0 (runtime address)
    # From the UE4SS log. But we need the file offset.
    # The log shows GUObjectArray at 0x7ff795e295d0 - this is a runtime VA
    # File offset would be different. Let me find GUObjectArray from the scan.

    # Actually, let me search for a different approach:
    # FUObjectHashTables::Get() is called from many places
    # It's a small function. Let me search for its pattern.

    # From the UE4SS log, the PatternSleuth pattern for FUObjectHashTables
    # looks for functions that call LogHashOuterStatistics.
    # The string "Hash efficiency statistics for the Outer Object Hash" was found.

    hash_str = "Hash efficiency statistics"
    hits = find_string(data, hash_str)
    if hits:
        print(f"  '{hash_str}' at {[hex(h) for h in hits]}")
        for h in hits[:2]:
            str_va = file_to_va(sections, image_base, h)
            xrefs = find_lea_xrefs(data, sections, image_base, str_va)
            print(f"  Xrefs: {[hex(x) for x in xrefs[:5]]}")
            for x in xrefs[:3]:
                fn = find_function_start_simple(data, x)
                if fn:
                    print(f"    Function at 0x{fn:X}: {bytes_hex(data, fn, 24)}")
                    # This is LogHashOuterStatistics
                    # FUObjectHashTables::Get() is called from this function
                    # Find CALLs in this function
                    calls = find_calls_in_range(data, sections, image_base, fn, 0x200)
                    for c_off, c_va, t_va, t_file in calls:
                        if t_file:
                            print(f"      CALL 0x{t_file:X}: {bytes_hex(data, t_file, 16)}")

    # Alternative: Search for the HASH_P4 pattern with wildcards
    # "e8 ?? ?? ?? ?? 45 33 ff 48 8b f0 33 c0 f0 44 0f b1 3d"
    # This was the most specific pattern. Let me try a more relaxed version
    print("\n  Trying relaxed HASH pattern:")
    # The pattern looks for: call; xor r15d,r15d; mov rsi,rax; xor eax,eax; lock cmpxchg [rip+?], r15d
    # Key signature: 45 33 FF 48 8B F0 33 C0 F0 44 0F B1 3D
    hash_sig = bytes([0x45, 0x33, 0xFF, 0x48, 0x8B, 0xF0, 0x33, 0xC0, 0xF0, 0x44, 0x0F, 0xB1, 0x3D])
    for i in range(len(data) - len(hash_sig)):
        if data[i:i+len(hash_sig)] == hash_sig:
            print(f"    Found at 0x{i:X} (VA 0x{file_to_va(sections, image_base, i):X})")
            # The E8 call is 5 bytes before
            if data[i-5] == 0xE8:
                call_target = resolve_rip(data, sections, image_base, i-5)
                if call_target is None:
                    # Manual resolution for CALL
                    call_va = file_to_va(sections, image_base, i-5)
                    rel32 = struct.unpack_from('<i', data, i-4)[0]
                    call_target = call_va + 5 + rel32
                call_file = va_to_file(sections, image_base, call_target)
                if call_file:
                    print(f"    CALL target at VA 0x{call_target:X} (file 0x{call_file:X})")
                    print(f"    Prologue: {bytes_hex(data, call_file, 24)}")

    print("\nDone.")

def find_function_start_simple(data, offset, max_search=0x2000):
    """Simple function start finder."""
    for i in range(offset, max(0, offset - max_search), -1):
        if i > 0 and data[i-1] in (0xCC, 0xC3, 0x90, 0xEB):
            for pat in [b'\x40\x53', b'\x40\x55', b'\x40\x56', b'\x40\x57',
                        b'\x48\x89\x5C\x24', b'\x48\x89\x6C\x24', b'\x48\x89\x74\x24',
                        b'\x55', b'\x53', b'\x56', b'\x57',
                        b'\x41\x54', b'\x41\x55', b'\x41\x56', b'\x41\x57']:
                if data[i:i+len(pat)] == pat:
                    return i
        if i > 1 and data[i-2:i] == b'\xCC\xCC':
            for pat in [b'\x40\x53', b'\x40\x55', b'\x48\x89\x5C\x24', b'\x48\x89\x6C\x24',
                        b'\x55', b'\x53']:
                if data[i:i+len(pat)] == pat:
                    return i
    return None

if __name__ == '__main__':
    main()
