#!/usr/bin/env python3
"""The biggest modules and symbols in one wasm-ld link map, to find what to trim.

    Tools/Size/map-top.py app.map [--top 150] [--modules A,B]
"""
import collections
import importlib
import sys

sys.path.insert(0, __file__.rsplit("/", 1)[0])
md = importlib.import_module("map-diff")


def main():
    args = sys.argv[1:]
    top, modules = 150, None
    if "--top" in args:
        i = args.index("--top"); top = int(args[i + 1]); del args[i:i + 2]
    if "--modules" in args:
        i = args.index("--modules"); modules = set(args[i + 1].split(",")); del args[i:i + 2]
    sizes = md.read(args[0])
    by_module = collections.Counter()
    for (s, m, _), v in sizes.items():
        by_module[(s, m)] += v
    print("== by module")
    for (s, m), v in by_module.most_common(40):
        print(f"{v:>10} {s:4s} {m}")
    rows = [(v, s, m, sym) for (s, m, sym), v in sizes.items() if modules is None or m in modules]
    rows.sort(reverse=True)
    rows = rows[:top]
    names = md.demangle([r[3] for r in rows])
    print(f"== top {top} symbols" + (f" in {sorted(modules)}" if modules else ""))
    for (v, s, m, _), name in zip(rows, names):
        print(f"{v:>8} {s:4s} {m:16.16s} {name[:170]}")


if __name__ == "__main__":
    main()
