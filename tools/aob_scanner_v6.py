"""Final verification - find FName::FName target and FUObjectHashTables."""
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

def main():
    data = load_exe()
    image_base, sections = parse_pe(data)

    # ========================================================
    # 1. FName::FName - follow the JMP from MovementComponent0 reference
    # ========================================================
    print("=== FName::FName via JMP target ===")

    # At file 0x173E5EE: E9 AD 25 4A 00
    jmp_off = 0x173E5EE
    rel32 = struct.unpack_from('<i', data, jmp_off + 1)[0]
    jmp_va = file_to_va(sections, image_base, jmp_off)
    target_va = jmp_va + 5 + rel32
    target_file = va_to_file(sections, image_base, target_va)
    print(f"JMP at file 0x{jmp_off:X} (VA 0x{jmp_va:X})")
    print(f"  target VA 0x{target_va:X} (file 0x{target_file:X})")
    print(f"  Prologue: {bhx(data, target_file, 48)}")

    # Check if this is FName::FName or a wrapper that calls the real one
    # Look for E8 CALLs in the first 100 bytes
    print(f"\n  CALLs from this function (first 200 bytes):")
    for i in range(target_file, target_file + 200):
        if data[i] == 0xE8:
            call_va = file_to_va(sections, image_base, i)
            call_rel32 = struct.unpack_from('<i', data, i + 1)[0]
            callee_va = call_va + 5 + call_rel32
            callee_file = va_to_file(sections, image_base, callee_va)
            if callee_file and callee_file < len(data):
                print(f"    CALL at +0x{i-target_file:X} -> VA 0x{callee_va:X} (file 0x{callee_file:X}): {bhx(data, callee_file, 24)}")

    # ========================================================
    # 2. FUObjectHashTables - search for the lock pattern
    # ========================================================
    print("\n=== FUObjectHashTables::Get() ===")

    # Search for the lock pattern: 45 33 FF 48 8B F0 33 C0 F0 44 0F B1 3D
    lock_sig = bytes([0x45, 0x33, 0xFF, 0x48, 0x8B, 0xF0, 0x33, 0xC0, 0xF0, 0x44, 0x0F, 0xB1, 0x3D])
    lock_matches = []
    for i in range(len(data) - len(lock_sig)):
        if data[i:i+len(lock_sig)] == lock_sig:
            lock_matches.append(i)

    print(f"Lock pattern matches: {len(lock_matches)}")
    for m in lock_matches[:10]:
        print(f"  At file 0x{m:X} (VA 0x{file_to_va(sections, image_base, m):X})")
        # Check if there's an E8 CALL before this (5 bytes before)
        if m >= 5 and data[m-5] == 0xE8:
            call_va = file_to_va(sections, image_base, m-5)
            call_rel32 = struct.unpack_from('<i', data, m-4)[0]
            callee_va = call_va + 5 + call_rel32
            callee_file = va_to_file(sections, image_base, callee_va)
            print(f"    CALL before -> VA 0x{callee_va:X} (file 0x{callee_file or 0:X})")
            if callee_file:
                print(f"    Callee prologue: {bhx(data, callee_file, 32)}")

    # Also try: search for functions that return a static FUObjectHashTables
    # The Get() function typically: lea rax, [rip+static]; test rax,rax; jnz ret; call init; ret
    # Look for: 48 8D 05 ?? ?? ?? ?? 48 85 C0 75 ?? C6 05
    # (LEA RAX, [static]; TEST RAX,RAX; JNZ +N; MOV BYTE [rip+?], 1)

    print("\n  Searching for singleton getter pattern...")
    sig = bytes([0x48, 0x8D, 0x05])  # LEA RAX, [rip+?]
    # Followed by 48 85 C0 (TEST RAX, RAX)
    for i in range(len(data) - 15):
        if data[i:i+3] == sig:
            # Check if TEST RAX, RAX follows (7 bytes later)
            if data[i+7:i+10] == bytes([0x48, 0x85, 0xC0]):
                # Check if JNZ follows
                if data[i+10] == 0x75:  # JNZ
                    # Check for MOV BYTE [rip+?], 01 after JNZ target
                    jnz_offset = data[i+11]
                    if jnz_offset < 0x20:  # reasonable short jump
                        after_jnz = i + 12 + jnz_offset
                        # Look for RET (C3) nearby
                        found_ret = False
                        for j in range(i, i + 60):
                            if data[j] == 0xC3:
                                found_ret = True
                                break
                        if found_ret and (after_jnz - i) < 50:
                            # This looks like a singleton getter
                            fn_start = find_fn(data, i)
                            if fn_start:
                                # Only report if this is a very small function (< 80 bytes)
                                fn_size = j - fn_start
                                if fn_size < 80:
                                    fn_va = file_to_va(sections, image_base, fn_start)
                                    print(f"  Singleton getter at file 0x{fn_start:X} (VA 0x{fn_va:X}), size ~{fn_size} bytes")
                                    print(f"    Bytes: {bhx(data, fn_start, min(64, fn_size+5))}")

    # ========================================================
    # 3. Summary of all findings
    # ========================================================
    print("\n=== SUMMARY ===")
    print("GNatives: FFrame::Step at file 0x1DD9310 (VA 0x141DD9D10)")
    print("  GNatives table at VA 0x14B87A750 (file 0xB878F50)")
    print()
    print("FName::FName: target at VA 0x{:X} (file 0x{:X})".format(target_va, target_file))
    print()
    print("StaticConstructObject_Internal: candidate at file 0x1E0E250 (VA 0x141E0EC50)")
    print("  Has 0x10000080 constant")
    print()

def find_fn(data, offset, max_back=0x100):
    for i in range(offset, max(0, offset - max_back), -1):
        if i > 0 and data[i-1] in (0xCC, 0xC3, 0x90):
            for pat in [b'\x40\x53', b'\x40\x55', b'\x40\x56', b'\x40\x57',
                        b'\x48\x89\x5C\x24', b'\x48\x89\x6C\x24', b'\x48\x89\x74\x24',
                        b'\x55', b'\x53', b'\x48\x83\xEC', b'\x4C\x8B\xDC']:
                if data[i:i+len(pat)] == pat:
                    return i
    return None

if __name__ == '__main__':
    main()
