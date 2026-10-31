#!/usr/bin/env python3
"""Names what the differing data bytes of two builds of the same module are: maps each run of
differing bytes in the data section to its memory address (from the segment's offset), then to
the symbols and input files a wasm-ld map (`-Xlinker --Map=...`) places there.

Usage: Tools/Size/data-symbols.py a.wasm b.wasm a.map
"""
import re
import sys


def leb(data, i, signed=False):
    result = shift = 0
    while True:
        byte = data[i]
        i += 1
        result |= (byte & 0x7F) << shift
        shift += 7
        if byte < 0x80:
            if signed and byte & 0x40:
                result -= 1 << shift
            return result, i


def data_segments(data):
    """(address or None, payload start, payload end) of each data segment."""
    i = 8
    while i < len(data):
        sid = data[i]
        size, j = leb(data, i + 1)
        if sid == 11:
            count, k = leb(data, j)
            out = []
            for _ in range(count):
                flags, k = leb(data, k)
                address = None
                if flags in (0, 2):
                    if flags == 2:
                        _, k = leb(data, k)
                    op = data[k]
                    value, k = leb(data, k + 1, signed=True)
                    assert data[k] == 0x0B, "unexpected offset expression"
                    k += 1
                    address = value if op == 0x41 else None
                n, k = leb(data, k)
                out.append((address, k, k + n))
                k += n
            return out
        i = j + size
    return []


def runs(a, b, start, end, gap=16):
    """Runs of differing bytes in [start, end), merging runs closer than `gap`."""
    out = []
    for k in range(start, end):
        if a[k] != b[k]:
            if out and k - out[-1][1] <= gap:
                out[-1][1] = k + 1
            else:
                out.append([k, k + 1])
    return out


def map_entries(path):
    """(address, size, depth, text) of each line of a wasm-ld map that places something."""
    entries = []
    for line in open(path, errors="replace"):
        m = re.match(r"^(\s*)([0-9a-fA-F]+)\s+([0-9a-fA-F]+)\s+([0-9a-fA-F]+)\s+(.*)$", line.rstrip("\n"))
        if not m:
            continue
        address, size, rest = int(m.group(2), 16), int(m.group(4), 16), m.group(5)
        depth = len(rest) - len(rest.lstrip())
        entries.append((address, size, depth, rest.strip()))
    return entries


def main(a_path, b_path, map_path):
    a, b = open(a_path, "rb").read(), open(b_path, "rb").read()
    if len(a) != len(b):
        print(f"sizes differ ({len(a)} vs {len(b)}); comparing anyway up to the shorter")
    sa, sb = data_segments(a), data_segments(b)
    entries = map_entries(map_path) if map_path else []
    print(f"{len(sa)} data segments; {len(entries)} map entries")
    total = 0
    for index, ((address, s, e), (_, s2, e2)) in enumerate(zip(sa, sb)):
        if e - s != e2 - s2 or s != s2:
            print(f"segment {index}: layout differs ({e - s} vs {e2 - s2} bytes)")
            continue
        for lo, hi in runs(a, b, s, e):
            total += hi - lo
            at = None if address is None else address + (lo - s)
            where = f"0x{at:x}" if at is not None else f"passive +{lo - s}"
            print(f"segment {index} {where}: {hi - lo} bytes differ")
            if at is None:
                continue
            hits = [x for x in entries if x[0] <= at < x[0] + max(x[1], 1)]
            for address_, size, depth, text in sorted(hits, key=lambda x: x[2]):
                print(f"   {address_:#x} +{size:#x}  {text}")
            if not hits:
                before = [x for x in entries if x[0] <= at]
                for address_, size, depth, text in before[-3:]:
                    print(f"   (nearest before) {address_:#x} +{size:#x}  {text}")
    print(f"{total} differing bytes in data segments")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2], sys.argv[3] if len(sys.argv) > 3 else None)
