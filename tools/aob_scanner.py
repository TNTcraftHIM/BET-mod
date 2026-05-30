"""
AOB Scanner for BETGameSteam-Win64-Shipping.exe
Finds byte patterns for missing UE4SS signatures:
  - FName::FName(wchar_t*)
  - StaticConstructObject_Internal
  - FUObjectHashTables::Get()
  - GNatives
"""

import struct
import sys
import os
import re
from pathlib import Path

EXE_PATH = Path(r"F:\Steam\steamapps\common\Backrooms_Escape_Together\BET\Binaries\Win64\BETGameSteam-Win64-Shipping.exe")
OUTPUT_DIR = Path(r"C:\Users\TNTcraft\Documents\GitHub\BET-mod\docs")

def load_exe():
    print(f"Loading {EXE_PATH.name} ({EXE_PATH.stat().st_size / 1024 / 1024:.1f} MB)...")
    with open(EXE_PATH, "rb") as f:
        data = f.read()
    print(f"Loaded {len(data)} bytes.")
    return data

def find_string(data, pattern, encoding='utf-8'):
    """Find all offsets where a string appears in the data."""
    if isinstance(pattern, str):
        pattern = pattern.encode(encoding)
    results = []
    start = 0
    while True:
        idx = data.find(pattern, start)
        if idx == -1:
            break
        results.append(idx)
        start = idx + 1
    return results

def find_wide_string(data, pattern):
    """Find all offsets where a wide (UTF-16LE) string appears."""
    encoded = pattern.encode('utf-16-le')
    return find_string(data, encoded)

def find_pattern(data, pattern_str):
    """
    Find all offsets matching an AOB pattern string like "48 8B 05 ?? ?? ?? ??".
    ?? = wildcard byte.
    """
    parts = pattern_str.strip().split()
    length = len(parts)
    mask = bytearray(length)
    pattern = bytearray(length)
    for i, part in enumerate(parts):
        if part == '??' or part == '?':
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
            results.append(i)
    return results

def resolve_rip_relative(data, offset, instr_offset, instr_length):
    """Resolve a RIP-relative address from an instruction at offset."""
    if offset + instr_offset + 4 > len(data):
        return None
    rel32 = struct.unpack_from('<i', data, offset + instr_offset)[0]
    rip = offset + instr_offset + 4
    return rip + rel32

def bytes_at(data, offset, length, as_hex=True):
    """Get hex string of bytes at offset."""
    raw = data[offset:offset + length]
    if as_hex:
        return ' '.join(f'{b:02X}' for b in raw)
    return raw

def scan_for_fname_constructor(data):
    """
    FName::FName(wchar_t*) in UE5.
    This constructor takes a wide string and creates/looks up an FName.
    In UE5, FName uses FNamePool. The constructor typically:
    1. Takes wchar_t* parameter (rcx or rdx)
    2. Calls into FNamePool to find or store the string
    3. Returns FName (ComparisonIndex + Number)

    Strategy: Search for strings unique to FName construction path,
    then find cross-references.
    """
    print("\n=== Scanning for FName::FName(wchar_t*) ===")

    # Search for FName-related strings
    name_strings = [
        "FName::Init",
        "FName::FName",
        "Unable to find name",
        "FNamePool",
        "FNameEntry",
    ]

    string_hits = {}
    for s in name_strings:
        hits = find_string(data, s)
        wide_hits = find_wide_string(data, s)
        all_hits = hits + wide_hits
        if all_hits:
            string_hits[s] = all_hits
            for h in all_hits:
                ctx = data[h:h+80]
                printable = ''.join(chr(b) if 32 <= b < 127 else '.' for b in ctx[:60])
                print(f"  '{s}' at 0x{h:X}: {printable}")

    # Also search for the error string pattern used in FName::Init
    # "FName could not be found" or similar
    for s in ["could not be found", "Illegal name", "NAME_None"]:
        hits_w = find_wide_string(data, s)
        hits_a = find_string(data, s)
        if hits_w or hits_a:
            print(f"  '{s}' wide: {[hex(h) for h in hits_w[:5]]} ascii: {[hex(h) for h in hits_a[:5]]}")

    # Pattern approach: FName(wchar_t*) typically starts with a standard prologue
    # and then references FName::Init or FNamePool::Store
    # Known pattern from UE5.7: lea rcx, [rip+offset] followed by FNamePool operations

    # Try patterns that are common for FName constructors
    candidate_patterns = [
        # Pattern: mov rax, [rip+?] ; then FNamePool operations
        "48 8B 05 ?? ?? ?? ?? 41 8B 07 F0 0F C1 47 04",
        # Alternative: function prologue + FName init
        "48 89 5C 24 ?? 48 89 74 24 ?? 57 48 83 EC 30 49 8B D8",
        # Another variant
        "40 53 48 83 EC 20 48 8B D9 48 85 C9 75",
    ]

    for pat in candidate_patterns:
        matches = find_pattern(data, pat)
        if matches:
            print(f"  Pattern '{pat}' -> {len(matches)} matches: {[hex(m) for m in matches[:10]]}")

    return string_hits

def scan_for_static_construct(data):
    """
    StaticConstructObject_Internal - large function for UObject creation.
    Contains many error strings about object creation.
    """
    print("\n=== Scanning for StaticConstructObject_Internal ===")

    # Search for strings unique to StaticConstructObject_Internal
    target_strings = [
        "StaticConstructObject",
        "GetDefaultObject",
        "NewObject",
        "ConstructObject",
        "Cannot create object",
        "ObjectFlags",
        "EObjectFlags",
        "Outer is not",
        "is not a subclass",
        "must be specified",
        "UObject",
        "DefaultSubObject",
    ]

    string_hits = {}
    for s in target_strings:
        hits = find_wide_string(data, s)
        if hits:
            string_hits[s] = hits
            print(f"  '{s}' at {[hex(h) for h in hits[:5]]}")

    # StaticConstructObject_Internal has a distinctive call pattern:
    # It calls AllocateObject, then initializes the object
    # Look for the string "StaticConstructObject_Internal" as a log/error message

    # Also try to find via the function that calls "GetClass()->IsChildOf" etc.
    return string_hits

def scan_for_fuobject_hashtables(data):
    """
    FUObjectHashTables::Get() - singleton getter.
    Typically a very small function that returns a static local.
    Pattern: if (!instance) { initialize(); } return instance;
    """
    print("\n=== Scanning for FUObjectHashTables::Get() ===")

    # Search for HashTables-related strings
    target_strings = [
        "FUObjectHashTables",
        "HashTables",
        "HashObject",
        "GetObjectHashBucket",
        "HashToObject",
    ]

    string_hits = {}
    for s in target_strings:
        hits = find_wide_string(data, s)
        if hits:
            string_hits[s] = hits
            print(f"  '{s}' wide at {[hex(h) for h in hits[:5]]}")

    # FUObjectHashTables::Get() pattern:
    # It's a singleton getter. In UE5, it uses thread-safe static init.
    # Common pattern: lea rax, [rip+offset] ; test rax, rax ; jz init ; ret

    return string_hits

def scan_for_gnatives(data):
    """
    GNatives - global array of native function pointers for UE VM.
    This is a large table (typically 256+ entries) of function pointers.
    Referenced in the bytecode execution loop (ProcessScriptFunction).
    """
    print("\n=== Scanning for GNatives ===")

    # Search for VM-related strings
    target_strings = [
        "GNatives",
        "ProcessScript",
        "ProcessInternal",
        "EX_Local",
        "EX_InstanceVariable",
        "Bytecode",
        "ScriptExecution",
        "ProcessNative",
        "NativeFunc",
    ]

    string_hits = {}
    for s in target_strings:
        hits = find_wide_string(data, s)
        if hits:
            string_hits[s] = hits
            print(f"  '{s}' wide at {[hex(h) for h in hits[:5]]}")

    return string_hits

def scan_for_cross_references(data, string_offset, search_range=0x10000):
    """
    Given a string offset, search for LEA instructions that reference it
    in the surrounding code. This helps find the function containing the string.
    """
    refs = []
    # Search backwards from the string for LEA instructions
    start = max(0, string_offset - search_range)
    end = min(len(data), string_offset + search_range)

    for i in range(start, end - 7):
        # LEA rax/rcx/rdx, [rip + rel32]
        if data[i] == 0x48 and data[i+1] == 0x8D:
            if data[i+2] in (0x05, 0x0D, 0x15, 0x1D, 0x25, 0x2D, 0x35, 0x3D):
                modrm = data[i+2]
                target = resolve_rip_relative(data, i, 3, 7)
                if target is not None and abs(target - string_offset) < 16:
                    reg = (modrm >> 3) & 7
                    regs = ['rax', 'rcx', 'rdx', 'rbx', 'rsp', 'rbp', 'rsi', 'rdi']
                    refs.append((i, regs[reg], target))
        # LEA without REX (32-bit register)
        elif data[i] == 0x4C and data[i+1] == 0x8D:
            if data[i+2] in (0x05, 0x0D, 0x15, 0x1D, 0x25, 0x2D, 0x35, 0x3D):
                target = resolve_rip_relative(data, i, 3, 7)
                if target is not None and abs(target - string_offset) < 16:
                    refs.append((i, 'r8-r15', target))

    return refs

def find_function_prologue(data, offset, search_back=0x200):
    """
    Search backwards from offset for a function prologue.
    Common x64 prologues:
    - push rbp (0x55)
    - mov rbp, rsp (0x48 0x89 0xE5)
    - push rbx (0x53)
    - sub rsp, imm (0x48 0x83 0xEC or 0x48 0x81 0xEC)
    """
    start = max(0, offset - search_back)
    prologue_patterns = [
        (b'\x40\x53', None),           # push rbx
        (b'\x40\x55', None),           # push rbp
        (b'\x40\x57', None),           # push rdi
        (b'\x48\x89\x5C\x24', None),   # mov [rsp+?], rbx
        (b'\x48\x89\x6C\x24', None),   # mov [rsp+?], rbp
        (b'\x48\x89\x74\x24', None),   # mov [rsp+?], rsi
        (b'\x55', None),               # push rbp (old)
        (b'\x48\x83\xEC', None),       # sub rsp, imm8
        (b'\x48\x81\xEC', None),       # sub rsp, imm32
        (b'\x48\x8B\xEC', None),       # mov rbp, rsp
    ]

    candidates = []
    for i in range(offset, start, -1):
        for pat, _ in prologue_patterns:
            if data[i:i+len(pat)] == pat:
                # Check if this looks like a real function start
                # (preceded by RET or NOP or INT3)
                if i > 0 and data[i-1] in (0xC3, 0xCC, 0x90, 0xEB):
                    candidates.append(i)
                elif i > 1 and data[i-2:i] == b'\xCC\xCC':
                    candidates.append(i)
                elif i > 0 and data[i-1] == 0x00:
                    candidates.append(i)

    return candidates

def generate_aob(data, offset, length=32, wildcard_relocs=True):
    """Generate an AOB pattern from bytes at offset."""
    raw = data[offset:offset + length]
    aob_parts = []
    for b in raw:
        aob_parts.append(f'{b:02X}')
    return ' '.join(aob_parts)

def main():
    data = load_exe()

    # Phase 1: String discovery
    print("\n" + "="*60)
    print("PHASE 1: String Discovery")
    print("="*60)

    fname_hits = scan_for_fname_constructor(data)
    sco_hits = scan_for_static_construct(data)
    hash_hits = scan_for_fuobject_hashtables(data)
    gnatives_hits = scan_for_gnatives(data)

    # Phase 2: More targeted pattern search
    print("\n" + "="*60)
    print("PHASE 2: Targeted Pattern Search")
    print("="*60)

    # Search for the string "StaticConstructObject_Internal" specifically
    print("\n--- Searching for StaticConstructObject_Internal string ---")
    sco_str_hits = find_string(data, "StaticConstructObject_Internal")
    if sco_str_hits:
        print(f"  Found {len(sco_str_hits)} occurrences:")
        for h in sco_str_hits[:5]:
            print(f"  0x{h:X}: {data[h:h+40]}")
            # Find cross-references
            refs = scan_for_cross_references(data, h)
            if refs:
                print(f"    Cross-references: {[(hex(r[0]), r[1], hex(r[2])) for r in refs[:10]]}")
                # For each reference, find function prologue
                for ref_offset, reg, target in refs[:5]:
                    prologues = find_function_prologue(data, ref_offset, 0x500)
                    if prologues:
                        print(f"    Function prologue candidates: {[hex(p) for p in prologues[:5]]}")
                        for p in prologues[:2]:
                            aob = generate_aob(data, p, 32)
                            print(f"    AOB at 0x{p:X}: {aob}")

    # Also search wide string
    sco_wide_hits = find_wide_string(data, "StaticConstructObject_Internal")
    if sco_wide_hits:
        print(f"\n  Wide string hits: {[hex(h) for h in sco_wide_hits[:5]]}")
        for h in sco_wide_hits[:3]:
            refs = scan_for_cross_references(data, h)
            if refs:
                print(f"    XRefs: {[(hex(r[0]), r[1], hex(r[2])) for r in refs[:5]]}")

    # Search for FName constructor specific strings
    print("\n--- Searching for FName constructor strings ---")
    fname_init = find_wide_string(data, "FName::Init")
    if fname_init:
        print(f"  FName::Init wide: {[hex(h) for h in fname_init[:5]]}")
        for h in fname_init[:3]:
            refs = scan_for_cross_references(data, h, 0x20000)
            if refs:
                print(f"    XRefs: {[(hex(r[0]), r[1], hex(r[2])) for r in refs[:5]]}")

    # Try broader FName searches
    for search_str in ["Illegal name", "NAME_None", "Unable to find", "FName could"]:
        hits = find_wide_string(data, search_str)
        if hits:
            print(f"  '{search_str}' wide: {[hex(h) for h in hits[:3]]}")
            for h in hits[:2]:
                refs = scan_for_cross_references(data, h, 0x20000)
                if refs:
                    print(f"    XRefs: {[(hex(r[0]), r[1], hex(r[2])) for r in refs[:3]]}")

    # Search for FUObjectHashTables
    print("\n--- Searching for FUObjectHashTables strings ---")
    hash_strs = find_wide_string(data, "FUObjectHashTables")
    if hash_strs:
        print(f"  FUObjectHashTables: {[hex(h) for h in hash_strs[:5]]}")
    for s in ["HashObject", "HashToObject", "AllocHashBucket"]:
        hits = find_wide_string(data, s)
        if hits:
            print(f"  '{s}': {[hex(h) for h in hits[:3]]}")

    # Search for GNatives / ProcessScriptFunction
    print("\n--- Searching for GNatives/VM strings ---")
    for s in ["ProcessScript", "ProcessNativeFunc", "GNatives", "ScriptExecution",
              "EX_LocalVariable", "EX_InstanceVariable", "EX_DefaultVariable",
              "ProcessInternal"]:
        hits = find_wide_string(data, s)
        if hits:
            print(f"  '{s}': {[hex(h) for h in hits[:3]]}")
        hits_a = find_string(data, s)
        if hits_a:
            print(f"  '{s}' (ascii): {[hex(h) for h in hits_a[:3]]}")

    # Phase 3: Try known UE5 AOB patterns
    print("\n" + "="*60)
    print("PHASE 3: Known UE5 AOB Patterns")
    print("="*60)

    known_patterns = {
        "FName_Ctor_v1": "48 8B 05 ?? ?? ?? ?? 41 8B 07 F0 0F C1 47 04",
        "FName_Ctor_v2": "40 53 48 83 EC 20 48 8B D9 48 85 C9 75",
        "StaticConstruct_v1": "48 89 5C 24 08 48 89 6C 24 10 48 89 74 24 18 57 41 56 41 57 48 83 EC 40",
        "StaticConstruct_v2": "48 8B C4 55 53 56 57 41 54 41 55 41 56 41 57 48 8D A8",
        "HashTables_v1": "48 8D 05 ?? ?? ?? ?? C3",
        "GNatives_ref": "48 8D 05 ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? 48 8D",
    }

    for name, pattern in known_patterns.items():
        matches = find_pattern(data, pattern)
        print(f"\n  {name}: '{pattern}'")
        if matches:
            print(f"    -> {len(matches)} matches: {[hex(m) for m in matches[:10]]}")
            for m in matches[:3]:
                print(f"    Context at 0x{m:X}: {generate_aob(data, m, 48)}")
        else:
            print(f"    -> No matches")

    # Phase 4: Search for large pointer tables (GNatives)
    print("\n" + "="*60)
    print("PHASE 4: GNatives Table Detection")
    print("="*60)

    # GNatives is typically a large array of function pointers.
    # In UE5, there are ~256-300+ opcodes, each with a native handler.
    # The table is usually in .data or .rdata section.
    # Look for sequences of pointers that point into .text section.

    # Get approximate .text section range (typically high addresses in the image)
    # For a 212MB exe, the image base is usually around 0x140000000
    # Let's find sections by parsing PE headers
    pe_sig_offset = struct.unpack_from('<I', data, 0x3C)[0]
    num_sections = struct.unpack_from('<H', data, pe_sig_offset + 6)[0]
    optional_header_size = struct.unpack_from('<H', data, pe_sig_offset + 20)[0]
    section_offset = pe_sig_offset + 24 + optional_header_size

    image_base = struct.unpack_from('<Q', data, pe_sig_offset + 24 + 24)[0]
    print(f"  Image base: 0x{image_base:X}")

    sections = []
    for i in range(num_sections):
        sec_start = section_offset + i * 40
        name = data[sec_start:sec_start+8].rstrip(b'\x00').decode('ascii', errors='replace')
        virtual_size = struct.unpack_from('<I', data, sec_start + 8)[0]
        virtual_addr = struct.unpack_from('<I', data, sec_start + 12)[0]
        raw_size = struct.unpack_from('<I', data, sec_start + 16)[0]
        raw_offset = struct.unpack_from('<I', data, sec_start + 20)[0]
        print(f"  Section '{name}': VA=0x{virtual_addr:X} VSize=0x{virtual_size:X} RawOff=0x{raw_offset:X} RawSize=0x{raw_size:X}")
        sections.append({
            'name': name,
            'virtual_addr': virtual_addr,
            'virtual_size': virtual_size,
            'raw_offset': raw_offset,
            'raw_size': raw_size,
        })

    # Find .text section
    text_section = None
    rdata_section = None
    data_section = None
    for sec in sections:
        if sec['name'] == '.text':
            text_section = sec
        elif sec['name'] == '.rdata':
            rdata_section = sec
        elif sec['name'] == '.data':
            data_section = sec

    if text_section:
        text_start = text_section['raw_offset']
        text_end = text_start + text_section['raw_size']
        print(f"\n  .text section: 0x{text_start:X} - 0x{text_end:X}")

        # GNatives table is typically in .data or .rdata
        # Look for it by finding a sequence of pointers into .text
        for sec in sections:
            if sec['name'] in ('.data', '.rdata', '.bss'):
                print(f"\n  Scanning {sec['name']} for pointer tables pointing into .text...")
                sec_data_start = sec['raw_offset']
                sec_data_end = sec_data_start + sec['raw_size']

                # Scan for sequences of 8+ consecutive pointers into .text
                consecutive = 0
                table_start = None
                max_consecutive = 0
                best_table_start = None

                for off in range(sec_data_start, sec_data_end - 8, 8):
                    ptr = struct.unpack_from('<Q', data, off)[0]
                    ptr_in_text = (ptr >= image_base + text_section['virtual_addr'] and
                                   ptr < image_base + text_section['virtual_addr'] + text_section['virtual_size'])
                    if ptr_in_text:
                        if consecutive == 0:
                            table_start = off
                        consecutive += 1
                        if consecutive > max_consecutive:
                            max_consecutive = consecutive
                            best_table_start = table_start
                    else:
                        if consecutive >= 64:  # GNatives has ~256+ entries
                            abs_addr = image_base + (table_start - sections[0]['raw_offset']) + sections[0]['virtual_addr']
                            # Actually calculate properly
                            for s in sections:
                                if table_start >= s['raw_offset'] and table_start < s['raw_offset'] + s['raw_size']:
                                    abs_addr = image_base + s['virtual_addr'] + (table_start - s['raw_offset'])
                                    break
                            print(f"    Large pointer table at file offset 0x{table_start:X} (VA ~0x{abs_addr:X}), {consecutive} entries")
                        consecutive = 0

                if max_consecutive >= 16:
                    print(f"    Longest pointer sequence: {max_consecutive} entries starting at 0x{best_table_start:X}")
                    if max_consecutive >= 64:
                        print(f"    This could be GNatives!")

    # Phase 5: Summary and save findings
    print("\n" + "="*60)
    print("SUMMARY")
    print("="*60)

    # Write findings to file
    output_file = OUTPUT_DIR / "aob_scan_results.md"
    with open(output_file, 'w', encoding='utf-8') as f:
        f.write("# AOB Scan Results for BET\n\n")
        f.write(f"Executable: {EXE_PATH.name}\n")
        f.write(f"Size: {EXE_PATH.stat().st_size} bytes\n\n")

        f.write("## String Hits\n\n")
        f.write("### FName::FName(wchar_t*)\n")
        for s, hits in fname_hits.items():
            f.write(f"- `{s}`: {[hex(h) for h in hits[:5]]}\n")

        f.write("\n### StaticConstructObject_Internal\n")
        for s, hits in sco_hits.items():
            f.write(f"- `{s}`: {[hex(h) for h in hits[:5]]}\n")

        f.write("\n### FUObjectHashTables::Get()\n")
        for s, hits in hash_hits.items():
            f.write(f"- `{s}`: {[hex(h) for h in hits[:5]]}\n")

        f.write("\n### GNatives\n")
        for s, hits in gnatives_hits.items():
            f.write(f"- `{s}`: {[hex(h) for h in hits[:5]]}\n")

    print(f"\nResults saved to {output_file}")
    print("Done.")

if __name__ == '__main__':
    main()
