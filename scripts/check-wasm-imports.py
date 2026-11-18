#!/usr/bin/env python3
"""Checks that a .wasm module's import section is in the plain encoding every browser reads.

Binaryen's `--all-features` includes the compact import section proposal, and with it wasm-opt
writes imports grouped under one module name (an empty field name, then kind 0x7E or 0x7F),
which Chrome refuses without `--wasm-compact-imports` ("Invalid import kind 127"). Exits 1,
naming the first such import, when an import's kind is not one of the five plain kinds
(function, table, memory, global, tag); 0 otherwise.

Usage: check-wasm-imports.py MODULE.wasm
"""
import sys

PLAIN_KINDS = {0: "function", 1: "table", 2: "memory", 3: "global", 4: "tag"}


def uleb(data, pos):
    result = shift = 0
    while True:
        byte = data[pos]
        pos += 1
        result |= (byte & 0x7F) << shift
        shift += 7
        if byte < 0x80:
            return result, pos


def name(data, pos):
    length, pos = uleb(data, pos)
    return data[pos:pos + length].decode("utf-8", "replace"), pos + length


def check(path):
    data = open(path, "rb").read()
    if data[:4] != b"\0asm":
        return f"{path}: not a WebAssembly module"
    pos = 8
    while pos < len(data):
        section, pos = data[pos], pos + 1
        size, pos = uleb(data, pos)
        end = pos + size
        if section == 2:
            count, pos = uleb(data, pos)
            for index in range(count):
                module, pos = name(data, pos)
                field, pos = name(data, pos)
                kind = data[pos]
                if kind not in PLAIN_KINDS:
                    return (f"{path}: import {index} ({module!r} {field!r}) has kind 0x{kind:02X}, the compact "
                            "import encoding, which browsers without --wasm-compact-imports refuse")
                pos += 1
                if kind == 0:
                    _, pos = uleb(data, pos)  # type index
                elif kind == 1:
                    pos += 1  # reference type
                    flags, pos = uleb(data, pos)
                    _, pos = uleb(data, pos)
                    if flags & 1:
                        _, pos = uleb(data, pos)
                elif kind == 2:
                    flags, pos = uleb(data, pos)
                    _, pos = uleb(data, pos)
                    if flags & 1:
                        _, pos = uleb(data, pos)
                    if flags & 8:  # custom page size
                        _, pos = uleb(data, pos)
                elif kind == 3:
                    if data[pos] in (0x63, 0x64):  # (ref null? ht)
                        pos += 1
                        _, pos = uleb(data, pos)
                    else:
                        pos += 1
                    pos += 1  # mutability
                elif kind == 4:
                    pos += 1  # attribute
                    _, pos = uleb(data, pos)
            print(f"{path}: {count} imports, plain encoding")
            return None
        pos = end
    print(f"{path}: no imports")
    return None


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    problem = check(sys.argv[1])
    if problem:
        print(problem, file=sys.stderr)
        sys.exit(1)
