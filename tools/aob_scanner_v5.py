"""Final verification of candidate functions and AOB extraction."""
import struct
from pathlib import Path

EXE_PATH = Path(r"F:\Steam\steamapps\common\Backrooms_Escape_Together\BET\Binaries\Win64\BETGameSteam-Win64-Shipping.exe")

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

def bhx(data, offset, length):
    return ' '.join(f'{b:02X}' for b in data[offset:offset+length])

def count_pattern(data, pattern_bytes, mask=None):
    """Count matches of a byte pattern."""
    length = len(pattern_bytes)
    count = 0
    for i in range(len(data) - length):
        match = True
        for j in range(length):
            if mask and not mask[j]:
                continue
            if data[i+j] != pattern_bytes[j]:
                match = False
                break
        if match:
            count += 1
    return count

def main():
    data = load_exe()
    image_base, sections = parse_pe(data)
    print(f"Image base: 0x{image_base:X}")

    # ========================================================
    # 1. GNatives - verify via FFrame::Step
    # ========================================================
    print("\n=== GNatives via FFrame::Step ===")
    step_off = 0x1DD9310
    print(f"FFrame::Step at file 0x{step_off:X} (VA 0x{file_to_va(sections, image_base, step_off):X})")
    print(f"Bytes: {bhx(data, step_off, 40)}")

    # Verify the LEA at +0x18
    lea_off = step_off + 0x18
    assert data[lea_off:lea_off+3] == bytes([0x4C, 0x8D, 0x0D]), "LEA r9 not found at expected offset"
    rel32 = struct.unpack_from('<i', data, lea_off + 3)[0]
    lea_va = file_to_va(sections, image_base, lea_off)
    gnatives_va = lea_va + 7 + rel32
    gnatives_file = va_to_file(sections, image_base, gnatives_va)
    print(f"LEA r9, [rip+0x{rel32:X}] -> GNatives at VA 0x{gnatives_va:X} (file 0x{gnatives_file:X})")

    # Check GNatives table entries
    print("GNatives table entries (first 32):")
    for i in range(32):
        ptr = struct.unpack_from('<Q', data, gnatives_file + i*8)[0]
        ptr_file = va_to_file(sections, image_base, ptr)
        print(f"  [{i:3d}] = 0x{ptr:X}" + (f" (file 0x{ptr_file:X})" if ptr_file else ""))

    # Verify pattern uniqueness
    pat = data[step_off:step_off+28]  # Full unique pattern
    count = count_pattern(data, pat)
    print(f"\nPattern uniqueness: {count} matches")

    # Create AOB with wildcards for the rel32 in LEA
    aob = "48 8B 41 20 4C 8B D2 48 8B D1 44 0F B6 08 48 FF C0 48 89 41 20 41 8B C1 4C 8D 0D ?? ?? ?? ?? 49 8B CA 4D 8B 0C C1 49 FF E1"
    print(f"Suggested AOB: {aob}")

    # ========================================================
    # 2. FName::FName - check candidates
    # ========================================================
    print("\n=== FName::FName(wchar_t*) candidates ===")

    # Check function at 0x1A0F3B0 (called from FName-creating code)
    fn_off = 0x1A0F3B0
    print(f"\nCandidate at 0x{fn_off:X} (VA 0x{file_to_va(sections, image_base, fn_off):X}):")
    print(f"  Prologue: {bhx(data, fn_off, 48)}")

    # Check function at 0x3906E40 (called from FName-creating code)
    fn_off = 0x3906E40
    print(f"\nCandidate at 0x{fn_off:X} (VA 0x{file_to_va(sections, image_base, fn_off):X}):")
    print(f"  Prologue: {bhx(data, fn_off, 48)}")

    # PatternSleuth uses "EB 07 48 8D 15 ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? 41 B8 01 00 00 00 E8" pattern
    # This means: JMP SHORT +7; LEA RDX, [rip+?]; ...; MOV R8D, 1; CALL
    # Let me search for the "41 B8 01 00 00 00 E8" pattern (MOV R8D, 1; CALL) near FName strings

    # Search for "41 B8 01 00 00 00" (mov r8d, 1 = EFindName::FName_Add)
    # near LEA instructions that reference our FName strings
    from_scanner3 = {
        "TGPUSkinVertexFactoryUnlimited": 0x9a297d8,
        "MovementComponent0": 0x99ac210,
    }

    for name, str_off in from_scanner3.items():
        str_va = file_to_va(sections, image_base, str_off)
        print(f"\n  String '{name}' at VA 0x{str_va:X}:")
        # Find LEA RDX pointing to this string, then check if MOV R8D,1 follows
        text_sec = [s for s in sections if s['name'] == '.text'][0]
        for i in range(text_sec['raw'], text_sec['raw'] + text_sec['rawsz'] - 30):
            if data[i] == 0x48 and data[i+1] == 0x8D and data[i+2] == 0x15:  # LEA RDX, [rip+?]
                rel32 = struct.unpack_from('<i', data, i + 3)[0]
                inst_va = file_to_va(sections, image_base, i)
                if inst_va:
                    resolved = inst_va + 7 + rel32
                    if resolved == str_va:
                        # Found LEA RDX to string. Check what follows
                        after = data[i+7:i+30]
                        print(f"    LEA at 0x{i:X}, followed by: {bhx(data, i+7, 24)}")
                        # Check for MOV R8D, 1 after some instructions
                        for j in range(7, 30):
                            if data[i+j:i+j+6] == bytes([0x41, 0xB8, 0x01, 0x00, 0x00, 0x00]):
                                print(f"    MOV R8D, 1 at +0x{j:X}")
                                # Check for CALL after MOV
                                for k in range(j+6, j+15):
                                    if data[i+k] == 0xE8:
                                        call_rel32 = struct.unpack_from('<i', data, i+k+1)[0]
                                        call_va = file_to_va(sections, image_base, i+k)
                                        target_va = call_va + 5 + call_rel32
                                        target_file = va_to_file(sections, image_base, target_va)
                                        print(f"    CALL at +0x{k:X} -> VA 0x{target_va:X} (file 0x{target_file or 0:X})")
                                        if target_file:
                                            print(f"      Prologue: {bhx(data, target_file, 24)}")
                                        break
                                break
                            # Also check BA 01 00 00 00 (MOV EDX, 1) - EFindName as second param
                            if data[i+j:i+j+5] == bytes([0xBA, 0x01, 0x00, 0x00, 0x00]):
                                print(f"    MOV EDX, 1 at +0x{j:X}")
                                # Check for CALL
                                for k in range(j+5, j+15):
                                    if data[i+k] == 0xE8:
                                        call_rel32 = struct.unpack_from('<i', data, i+k+1)[0]
                                        call_va = file_to_va(sections, image_base, i+k)
                                        target_va = call_va + 5 + call_rel32
                                        target_file = va_to_file(sections, image_base, target_va)
                                        print(f"    CALL at +0x{k:X} -> VA 0x{target_va:X} (file 0x{target_file or 0:X})")
                                        if target_file:
                                            print(f"      Prologue: {bhx(data, target_file, 24)}")
                                        break
                                break

    # ========================================================
    # 3. StaticConstructObject_Internal - verify candidate
    # ========================================================
    print("\n=== StaticConstructObject_Internal candidate ===")
    sco_off = 0x1E0E250
    print(f"Candidate at 0x{sco_off:X} (VA 0x{file_to_va(sections, image_base, sco_off):X}):")
    print(f"  Prologue: {bhx(data, sco_off, 48)}")

    # Verify it has 0x10000080 constant
    found_offset = None
    for i in range(sco_off, sco_off + 0x3000):
        if data[i:i+4] == b'\x80\x00\x00\x10':
            found_offset = i
            print(f"  0x10000080 found at +0x{i - sco_off:X} (file 0x{i:X})")
            print(f"    Context: {bhx(data, i-8, 24)}")
            break

    if found_offset:
        # Check pattern uniqueness of first ~24 bytes
        pat = data[sco_off:sco_off+24]
        count = count_pattern(data, pat)
        print(f"  First 24 bytes uniqueness: {count} matches")

    # Also check: does this function call AllocateObject?
    # StaticConstructObject typically calls: AllocateObject, then constructs the object
    # It should also reference strings like "StaticConstructObject" or "ConstructObject"
    # Let me check for LEA instructions in this function that reference error strings
    print(f"\n  LEA instructions in SCO candidate (first 0x1000 bytes):")
    for i in range(sco_off, sco_off + 0x1000):
        if (data[i] == 0x48 or data[i] == 0x4C) and data[i+1] == 0x8D:
            modrm_mod = (data[i+2] >> 6) & 3
            modrm_rm = data[i+2] & 7
            if modrm_mod == 0 and modrm_rm == 5:
                rel32 = struct.unpack_from('<i', data, i + 3)[0]
                inst_va = file_to_va(sections, image_base, i)
                if inst_va:
                    target = inst_va + 7 + rel32
                    target_file = va_to_file(sections, image_base, target)
                    if target_file and target_file < len(data):
                        # Check if target is a string
                        snippet = data[target_file:target_file+60]
                        # Try to decode as UTF-16
                        try:
                            decoded = snippet.decode('utf-16-le', errors='replace')
                            # Check if it looks like a readable string
                            printable = sum(1 for c in decoded if c.isprintable() or c in '\n\r\t')
                            if printable > 10:
                                print(f"    0x{i:X} -> 0x{target_file:X}: \"{decoded[:40]}\"")
                        except:
                            pass

    print("\nDone.")

if __name__ == '__main__':
    main()
