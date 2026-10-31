#!/usr/bin/env python3
"""Compares two builds of the same wasm section by section (why the brotli size of one raw size
varies from run to run) and measures what stripping custom sections would save.

Usage: Tools/Size/section-diff.py a.wasm b.wasm
"""
import hashlib
import subprocess
import sys


def leb(data, i):
    result = shift = 0
    while True:
        byte = data[i]
        i += 1
        result |= (byte & 0x7F) << shift
        shift += 7
        if byte < 0x80:
            return result, i


def sections(data):
    """(id, name, start, end, header) of each section: its payload's bounds and where it begins."""
    assert data[:4] == b"\0asm", "not a wasm module"
    i, out = 8, []
    while i < len(data):
        sid = data[i]
        size, j = leb(data, i + 1)
        name = str(sid)
        if sid == 0:
            n, k = leb(data, j)
            name = "custom:" + data[k:k + n].decode("utf-8", "replace")
        out.append((sid, name, j, j + size, i))
        i = j + size
    return out


def brotli(blob):
    return len(subprocess.run(["brotli", "-q", "11", "-c"], input=blob, capture_output=True, check=True).stdout)


def functions(data, start, end):
    """The code section's function bodies, as byte strings."""
    count, i = leb(data, start)
    bodies = []
    for _ in range(count):
        size, j = leb(data, i)
        bodies.append(data[j:j + size])
        i = j + size
    return bodies


def main(a_path, b_path):
    a, b = open(a_path, "rb").read(), open(b_path, "rb").read()
    print(f"a: raw {len(a)} brotli {brotli(a)}; b: raw {len(b)} brotli {brotli(b)}")
    sa, sb = sections(a), sections(b)
    print(f"{'section':32} {'raw':>10} {'brotli a':>10} {'brotli b':>10}  same")
    for (ida, na, s1, e1, _), (idb, nb, s2, e2, _) in zip(sa, sb):
        pa, pb = a[s1:e1], b[s2:e2]
        same = hashlib.sha256(pa).digest() == hashlib.sha256(pb).digest()
        print(f"{na:32} {e1 - s1:>10} {brotli(pa):>10} {brotli(pb):>10}  {'yes' if same else 'NO'}")
        if not same and len(pa) == len(pb):
            diff = [k for k in range(len(pa)) if pa[k] != pb[k]]
            print(f"   {len(diff)} bytes differ, first at {diff[0]}, last at {diff[-1]}")
            # The differing window with some context, as text where it is text (to name its source).
            lo, hi = max(0, diff[0] - 256), min(len(pa), diff[-1] + 257)
            show = lambda b: "".join(chr(c) if 32 <= c < 127 else "." for c in b)
            for label, blob in (("a", pa), ("b", pb)):
                print(f"   {label} [{lo}:{hi}]:")
                for k in range(lo, hi, 96):
                    print("     " + show(blob[k:min(k + 96, hi)]))
        if not same and ida == 10:
            fa, fb = functions(a, s1, e1), functions(b, s2, e2)
            moved = sum(1 for x, y in zip(fa, fb) if x != y)
            print(f"   {len(fa)} vs {len(fb)} functions; {moved} differ at the same index;"
                  f" as multisets {'equal' if sorted(fa) == sorted(fb) else 'different'}")
        if not same and na.startswith("custom:name"):
            print("   the name section differs (function order or names)")
    if [s[1] for s in sa] != [s[1] for s in sb]:
        print("section lists differ:", [s[1] for s in sa], [s[1] for s in sb])
    # What the module would weigh without its custom sections (names, producers, target features).
    kept = bytearray(a[:8])
    for sid, _, _, e, header in sa:
        if sid != 0:
            kept += a[header:e]
    print(f"a without custom sections: raw {len(kept)} brotli {brotli(bytes(kept))}")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
