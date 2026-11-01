#!/usr/bin/env python3
"""Compare two wasm-ld link maps of the same app: what grew and what shrank between two commits.

    Tools/Size/map-diff.py before.map after.map [--top 60]

Sizes are the linked module's CODE and DATA bytes, before wasm-opt and brotli; the proportions
hold after both (decision 0006). Lists the change by module, then the symbols that appeared,
disappeared or changed size, demangled with the active toolchain's `swift demangle`.
"""
import collections
import subprocess
import sys

SECTIONS = {'TYPE', 'IMPORT', 'FUNCTION', 'TABLE', 'MEMORY', 'GLOBAL', 'EXPORT', 'ELEM', 'CODE', 'DATA',
            'CUSTOM', 'START', 'DATACOUNT'}


def module_of(path):
    # .../release/<Module>.build/<File>.o or .../lib<Name>.a(<member>)
    if '.build/' in path:
        return path.split('.build/')[-2].rsplit('/', 1)[-1]
    if '.a(' in path:
        return path.rsplit('/', 1)[-1].split('(')[0]
    return path.rsplit('/', 1)[-1]


def read(path):
    """{(section, module, symbol): bytes} from a map."""
    sizes = collections.Counter()
    section = None
    for line in open(path, errors='replace'):
        parts = line.split()
        if len(parts) == 4 and parts[0] == '-' and parts[3] in SECTIONS:
            section = parts[3]
            continue
        if len(parts) == 4 and ':(' in parts[3] and section in ('CODE', 'DATA'):
            where, symbol = parts[3].split(':(', 1)
            sizes[(section, module_of(where), symbol.rstrip(')'))] += int(parts[2], 16)
    return sizes


def demangle(names):
    if not names:
        return []
    try:
        out = subprocess.run(['swift', 'demangle', '--compact'], input='\n'.join(names),
                             capture_output=True, text=True).stdout.split('\n')
        return out[:len(names)] if len(out) >= len(names) else names
    except OSError:
        return names


def main():
    args = sys.argv[1:]
    top = 60
    if '--top' in args:
        i = args.index('--top')
        top = int(args[i + 1])
        del args[i:i + 2]
    if len(args) != 2:
        sys.exit(__doc__)
    before, after = read(args[0]), read(args[1])
    total = lambda m, s: sum(v for (sec, _, _), v in m.items() if sec == s)
    for s in ('CODE', 'DATA'):
        print(f'{s}: {total(before, s)} -> {total(after, s)} ({total(after, s) - total(before, s):+d})')
    by_module = collections.Counter()
    for (s, m, _), v in after.items():
        by_module[(s, m)] += v
    for (s, m, _), v in before.items():
        by_module[(s, m)] -= v
    print('== change by module')
    for (s, m), d in sorted(by_module.items(), key=lambda kv: -abs(kv[1]))[:top]:
        if d:
            print(f'{d:+9d} {s:4s} {m}')
    changes = []
    for key in set(before) | set(after):
        d = after.get(key, 0) - before.get(key, 0)
        if d:
            tag = 'new' if key not in before else 'gone' if key not in after else 'size'
            changes.append((d, tag, key))
    grew = sorted((c for c in changes if c[0] > 0), key=lambda c: -c[0])[:top]
    shrank = sorted((c for c in changes if c[0] < 0), key=lambda c: c[0])[:top // 2]
    for title, rows in (('== grew or appeared', grew), ('== shrank or disappeared', shrank)):
        print(title)
        names = demangle([k[2] for _, _, k in rows])
        for (d, tag, (s, m, _)), name in zip(rows, names):
            print(f'{d:+8d} {tag:4s} {s:4s} {m:18s} {name[:150]}')
    counts = collections.Counter(tag for _, tag, _ in changes)
    print(f'== {counts["new"]} symbols new, {counts["gone"]} gone, {counts["size"]} resized')


if __name__ == '__main__':
    main()
