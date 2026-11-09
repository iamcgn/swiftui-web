#!/usr/bin/env python3
"""The iOS branches of an app's `#if os(iOS)` (decision 0025).

On wasm every `os(...)` condition is false, so an iOS app's `#if os(iOS)` code (a binding one
view passes and another declares only on iOS, the iOS toolbar placement) would compile its
other branch, which is not the app the browser emulates. For each app listed in
`Apps/ios-conditions.txt` this copies `Apps/upstream/<app>` to `Apps/ios-sources/<app>` with
`os(iOS)` read as true in `#if`/`#elseif` lines and nothing else changed (same files, same
lines, so diagnostics keep their line numbers); `Apps/Package.swift` builds the copy. The
upstream tree itself stays exactly its pin (scripts/check-apps.sh). A file is rewritten only
when its text changes, so an incremental build recompiles nothing it need not.
"""
import os
import re
import shutil
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APPS = os.path.join(ROOT, "Apps")
CONDITION = re.compile(r"^(\s*#\s*(?:if|elseif)\b.*)$")
IOS = re.compile(r"\bos\(\s*iOS\s*\)")


def rewrite(text: str) -> str:
    lines = text.split("\n")
    for i, line in enumerate(lines):
        if CONDITION.match(line):
            lines[i] = IOS.sub("true", line)
    return "\n".join(lines)


def mirror(app: str) -> int:
    source = os.path.join(APPS, "upstream", app)
    target = os.path.join(APPS, "ios-sources", app)
    if not os.path.isdir(source):
        print(f"ios-conditions: no Apps/upstream/{app} (submodules not checked out?)", file=sys.stderr)
        return 1
    seen = set()
    changed = 0
    for directory, dirs, files in os.walk(source):
        dirs[:] = [d for d in dirs if d != ".git"]
        relative = os.path.relpath(directory, source)
        os.makedirs(os.path.join(target, relative), exist_ok=True)
        for name in files:
            if name == ".git":
                continue
            src = os.path.join(directory, name)
            dst = os.path.normpath(os.path.join(target, relative, name))
            seen.add(dst)
            if name.endswith(".swift"):
                with open(src, encoding="utf-8", errors="surrogateescape") as f:
                    text = rewrite(f.read())
                old = None
                if os.path.exists(dst):
                    with open(dst, encoding="utf-8", errors="surrogateescape") as f:
                        old = f.read()
                if old != text:
                    with open(dst, "w", encoding="utf-8", errors="surrogateescape") as f:
                        f.write(text)
                    changed += 1
            elif not os.path.exists(dst) or os.path.getmtime(dst) < os.path.getmtime(src) or os.path.getsize(dst) != os.path.getsize(src):
                shutil.copy2(src, dst)
                changed += 1
    # Files upstream no longer has.
    for directory, _, files in os.walk(target):
        for name in files:
            path = os.path.normpath(os.path.join(directory, name))
            if path not in seen:
                os.remove(path)
                changed += 1
    print(f"ios-conditions: Apps/ios-sources/{app} ({changed} files written)")
    return 0


def main() -> int:
    listing = os.path.join(APPS, "ios-conditions.txt")
    with open(listing, encoding="utf-8") as f:
        apps = [line.split("#")[0].strip() for line in f]
    status = 0
    for app in filter(None, apps):
        status |= mirror(app)
    return status


if __name__ == "__main__":
    sys.exit(main())
