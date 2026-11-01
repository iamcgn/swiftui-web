#!/usr/bin/env python3
"""Count a wasm module's exports and list a sample of them: whether the link exported every
public symbol (`--export-dynamic`), which keeps code no one calls alive.

    Tools/Size/exports.py App.wasm [--show 30]
"""
import sys


def leb(data, i):
    result = shift = 0
    while True:
        b = data[i]; i += 1
        result |= (b & 0x7f) << shift; shift += 7
        if b < 0x80:
            return result, i


def exports(path):
    data = open(path, 'rb').read()
    assert data[:4] == b'\0asm', f'{path}: not a wasm module'
    i = 8
    while i < len(data):
        sid = data[i]; i += 1
        size, i = leb(data, i)
        end = i + size
        if sid == 7:
            count, j = leb(data, i)
            out = []
            for _ in range(count):
                n, j = leb(data, j)
                name = data[j:j + n].decode('utf-8', 'replace'); j += n
                kind = data[j]; j += 1
                _, j = leb(data, j)
                out.append((kind, name))
            return out
        i = end
    return []


def main():
    args = sys.argv[1:]
    show = 30
    if '--show' in args:
        k = args.index('--show'); show = int(args[k + 1]); del args[k:k + 2]
    if len(args) != 1:
        sys.exit(__doc__)
    ex = exports(args[0])
    kinds = {0: 'func', 1: 'table', 2: 'memory', 3: 'global'}
    by = {}
    for k, _ in ex:
        by[kinds.get(k, k)] = by.get(kinds.get(k, k), 0) + 1
    print(f'{args[0]}: {len(ex)} exports {by}')
    for k, name in ex[:show]:
        print(f'  {kinds.get(k, k):6s} {name[:120]}')


if __name__ == '__main__':
    main()
