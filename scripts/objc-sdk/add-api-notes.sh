#!/usr/bin/env bash
# Puts ObjectiveC.apinotes beside the installed Objective-C runtime SDK's module map. The file is
# swift-objc-wasm's (runtime/include/objc, after v0.1.1): Swift sees the runtime's NSObject
# `description` and `debugDescription` as `__description` and `__debugDescription`, so the one
# WebFoundation declares is the only `description` (decision 0023). Run it after
# `swift sdk install` of v0.1.1; a release that carries the file makes this a no-op.
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
done
[ "$found" = 1 ] || { echo "no installed wasm-objc SDK found" >&2; exit 1; }
