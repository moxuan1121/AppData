import struct
import sys

import lief
from capstone import Cs, CS_ARCH_ARM64, CS_MODE_ARM
from capstone.arm64 import ARM64_OP_IMM, ARM64_OP_MEM, ARM64_REG_X1


b = lief.parse(sys.argv[1])


def data(va, size):
    return bytes(b.get_content_from_virtual_address(va, size))


def u32(va):
    return struct.unpack("<I", data(va, 4))[0]


def i32(va):
    return struct.unpack("<i", data(va, 4))[0]


def u64(va):
    return struct.unpack("<Q", data(va, 8))[0]


def cstr(va):
    out = bytearray()
    while va and len(out) < 4096:
        chunk = data(va, 1)
        if not chunk or chunk == b"\0":
            break
        out += chunk
        va += 1
    return out.decode("utf-8", "replace")


def methods(list_va):
    if not list_va:
        return []
    flags, count = u32(list_va), u32(list_va + 4)
    relative = bool(flags & 0x80000000)
    entry_size = flags & 0xFFFF
    if entry_size == 0:
        entry_size = 12 if relative else 24
    result = []
    for index in range(count):
        entry = list_va + 8 + index * entry_size
        if relative:
            name = cstr(entry + i32(entry))
            imp = entry + 8 + i32(entry + 8)
        else:
            name = cstr(u64(entry))
            imp = u64(entry + 16)
        result.append((name, imp))
    return result


classlist = b.get_section("__objc_classlist")
all_methods = {}
for offset in range(0, classlist.size, 8):
    cls = u64(classlist.virtual_address + offset)
    ro = u64(cls + 32) & ~7
    name = cstr(u64(ro + 24))
    method_list = u64(ro + 32)
    show_listing = len(sys.argv) == 2
    if show_listing:
        print(f"CLASS {name} {cls:#x}")
    for method, imp in methods(method_list):
        all_methods[method] = imp
        if show_listing:
            print(f"  - {method} {imp:#x}")

if len(sys.argv) > 2:
    md = Cs(CS_ARCH_ARM64, CS_MODE_ARM)
    md.detail = True
    symbols = {symbol.value: symbol.name for symbol in b.symbols if symbol.value}
    stub_section = b.get_section("__objc_stubs")
    stub_names = {}
    for stub in range(stub_section.virtual_address, stub_section.virtual_address + stub_section.size, 12):
        instructions = list(md.disasm(data(stub, 12), stub))
        if len(instructions) < 2 or instructions[0].mnemonic != "adrp" or instructions[1].mnemonic != "ldr":
            continue
        page = instructions[0].operands[1].imm
        mem = instructions[1].operands[1].mem
        selref = page + mem.disp
        try:
            stub_names[stub] = cstr(u64(selref))
        except Exception:
            pass
    calls_only = "--calls-only" in sys.argv[2:]
    targets = [arg for arg in sys.argv[2:] if arg != "--calls-only"]
    ordered = sorted(all_methods.items(), key=lambda item: item[1])
    for target in targets:
        start = all_methods[target]
        end = next((address for _, address in ordered if address > start), start + 0x500)
        print(f"DISASSEMBLY {target} {start:#x}-{end:#x}")
        rendered = []
        for insn in md.disasm(data(start, end - start), start):
            suffix = ""
            if insn.mnemonic == "bl" and insn.operands and insn.operands[0].type == ARM64_OP_IMM:
                destination = insn.operands[0].imm
                if destination in stub_names:
                    suffix = f" ; objc_msgSend {stub_names[destination]}"
                elif destination in symbols:
                    suffix = f" ; {symbols[destination]}"
            rendered.append(f"{insn.address:08x}: {insn.mnemonic:8} {insn.op_str}{suffix}")
        if calls_only:
            emitted = set()
            for index, line in enumerate(rendered):
                if "objc_msgSend" not in line and "_objc_" not in line and "_NSClassFromString" not in line and "_NSSelectorFromString" not in line:
                    continue
                first = max(0, index - 7)
                last = min(len(rendered), index + 2)
                key = (first, last)
                if key in emitted:
                    continue
                emitted.add(key)
                print("\n".join(rendered[first:last]))
                print("--")
        else:
            print("\n".join(rendered))
