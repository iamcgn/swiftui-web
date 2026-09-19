#!/usr/bin/env python3
"""Aggregate a wasm-ld map file by module, archive member and symbol (decision 0017).

Build the app with a linker map, then run this on it:

    # in the app's Package.swift, next to the stack-size flags:
    #   "-Xlinker", "--Map=/tmp/app.map"    (and "--why-extract=/tmp/why.txt" for extraction chains)
    scripts/build-wasm.sh Examples/Counter
    scripts/wasm-size-map.py /tmp/app.map [--top 40]

Sizes are pre-wasm-opt bytes of the CODE and DATA sections; proportions hold after wasm-opt and
brotli. `swift demangle` from the active toolchain names the largest symbols.
"""
import collections
import re
import subprocess
import sys

SECTIONS = {'TYPE', 'IMPORT', 'FUNCTION', 'TABLE', 'MEMORY', 'GLOBAL', 'EXPORT', 'ELEM', 'CODE', 'DATA', 'CUSTOM', 'START', 'DATACOUNT'}


def source(path):
    match = re.search(r'/release/([^/]+)\.build/([^/]+)\.o', path)
    if match:
        return match.group(1), match.group(2)
    match = re.search(r'/(lib[^/]+\.a)\(([^)]+)\)', path)
    if match:
        return match.group(1), match.group(2)
    return path.rsplit('/', 1)[-1], ''


def main():
    args = sys.argv[1:]
    top = 40
    if '--top' in args:
        top = int(args[args.index('--top') + 1])
        del args[args.index('--top'):args.index('--top') + 2]
    if not args:
        sys.exit(__doc__)
    section = None
    code = collections.Counter()
    data = collections.Counter()
    members = collections.Counter()
    symbols = []
    for line in open(args[0]):
        parts = line.split()
        if len(parts) == 4 and parts[0] == '-' and parts[3] in SECTIONS:
            section = parts[3]
            continue
        if len(parts) == 4 and ':(' in parts[3] and section in ('CODE', 'DATA'):
            size = int(parts[2], 16)
            path, symbol = parts[3].split(':(', 1)
            module, member = source(path)
            (code if section == 'CODE' else data)[module] += size
            members[(module, member)] += size
            if section == 'CODE':
                symbols.append((size, module, symbol.rstrip(')')))
    print('== code by module')
    for module, size in code.most_common(top):
        print(f'{size:10d} {module}')
    print('== data by module')
    for module, size in data.most_common(top):
        print(f'{size:10d} {module}')
    print('== code + data by file or archive member')
    for (module, member), size in members.most_common(top):
        print(f'{size:10d} {module}/{member}')
    symbols.sort(reverse=True)
    names = subprocess.run(['swift', 'demangle', '--compact'], input='\n'.join(s[2] for s in symbols[:top]), capture_output=True, text=True).stdout.split('\n')
    print('== largest symbols')
    for (size, module, _), name in zip(symbols[:top], names):
        print(f'{size:10d} {module:20s} {name[:140]}')


if __name__ == '__main__':
    main()
