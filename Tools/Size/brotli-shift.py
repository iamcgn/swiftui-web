#!/usr/bin/env python3
"""Whether brotli -q 11's swings near the budget follow where sections fall in the file: inserts
an empty-content custom section of each size before the data section (or after the header) and
prints the whole file's brotli size for each.

Usage: Tools/Size/brotli-shift.py module.wasm [where=data|start] [sizes...]
"""
import subprocess
import sys

sys.path.insert(0, __file__.rsplit("/", 1)[0])
from importlib import import_module

sd = import_module("section-diff")


def uleb(n):
    out = bytearray()
    while True:
        b = n & 0x7F
        n >>= 7
        out.append(b | (0x80 if n else 0))
        if not n:
            return bytes(out)


def pad_section(size):
    name = b"pad"
    payload = uleb(len(name)) + name + b"\0" * size
    return b"\0" + uleb(len(payload)) + payload


def br(blob):
    return len(subprocess.run(["brotli", "-q", "11", "-c"], input=blob, capture_output=True, check=True).stdout)


def main(path, where, sizes):
    data = open(path, "rb").read()
    secs = sd.sections(data)
    for sid, name, s, e, h in secs:
        print(f"  section {name:30} header at {h:>9} payload {s:>9}..{e:>9} ({e - s})")
    at = 8 if where == "start" else next(h for sid, _, _, _, h in secs if sid == 11)
    print(f"{path}: raw {len(data)} brotli {br(data)}; inserting at {at}")
    for k in sizes:
        blob = data[:at] + pad_section(k) + data[at:]
        print(f"  pad {k:>7} at {where}: raw {len(blob)} brotli {br(blob)}")


if __name__ == "__main__":
    args = sys.argv[1:]
    main(args[0], args[1] if len(args) > 1 else "data", [int(x) for x in args[2:]] or [512, 2048, 4096, 8192, 32768, 131072])
