#!/usr/bin/env bash
# Two fixes to the installed Objective-C runtime SDK (swift-objc-wasm v0.1.1); run it after
# `swift sdk install`. A release that carries both makes this a no-op.
#
# 1. Puts ObjectiveC.apinotes beside the SDK's module map. The file is swift-objc-wasm's
#    (runtime/include/objc, after v0.1.1): Swift sees the runtime's NSObject `description` and
#    `debugDescription` as `__description` and `__debugDescription`, so the one WebFoundation
#    declares is the only `description` (decision 0023).
# 2. Adds `-Xllvm -type-lowering-disable-verification` to the SDK's toolset. v0.1.1's compiler is
#    built with assertions, and those builds check every type lowering in SILGen, a check release
#    compilers never run. Swift 6.3.3's check aborts the build of Hipstapaper's V3Style ("Found
#    non-trivial lexical leaf in non-trivial non-lexical type", issue #343). The flag skips only
#    that check; the SIL is the same.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
roots=("$HOME/Library/org.swift.swiftpm/swift-sdks" "$HOME/.swiftpm/swift-sdks" "${XDG_CONFIG_HOME:-$HOME/.config}/swiftpm/swift-sdks")
found=0
for root in "${roots[@]}"; do
    [ -d "$root" ] || continue
    while IFS= read -r header; do
        dir="$(dirname "$header")"
        [ -f "$dir/module.modulemap" ] || continue
        cp "$here/ObjectiveC.apinotes" "$dir/ObjectiveC.apinotes"
        echo "API notes: $dir/ObjectiveC.apinotes"
        found=1
    done < <(find "$root" -path '*wasm-objc*' -path '*/include/objc/NSObject.h' 2>/dev/null)
    while IFS= read -r toolset; do
        python3 - "$toolset" <<'PY'
import json, sys
path = sys.argv[1]
with open(path) as f:
    toolset = json.load(f)
options = toolset.setdefault("swiftCompiler", {}).setdefault("extraCLIOptions", [])
flag = "-type-lowering-disable-verification"
if flag not in options:
    options += ["-Xllvm", flag]
    with open(path, "w") as f:
        json.dump(toolset, f, indent=2)
        f.write("\n")
print(f"Toolset: {path}: {' '.join(options)}")
PY
    done < <(find "$root" -path '*wasm-objc*' -name toolset.json 2>/dev/null)
done
[ "$found" = 1 ] || { echo "no installed wasm-objc SDK found" >&2; exit 1; }
