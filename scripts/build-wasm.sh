#!/usr/bin/env bash
# Builds a wasm bundle for an example/app package using the JavaScriptKit PackageToJS plugin.
# Usage: scripts/build-wasm.sh Examples/Counter [--debug]
set -euo pipefail
PKG="${1:-Examples/Counter}"; shift || true
SDK="swift-$(cat "$(dirname "$0")/../.swift-version")-RELEASE_wasm"
# shellcheck disable=SC1091
. "$(dirname "$0")/env.sh"
case "$PKG" in *Gallery|*Gallery/) python3 "$(dirname "$0")/gen-fixture-sources.py";; esac   # fixture code shown in the gallery
cd "$PKG"
if [[ "${1:-}" == "--debug" ]]; then
  swift package --disable-sandbox --swift-sdk "$SDK" --scratch-path .build/wasm js --use-cdn --debug-info-format dwarf
else
  swift package --disable-sandbox --swift-sdk "$SDK" --scratch-path .build/wasm -c release -Xswiftc -Osize js --use-cdn
fi
echo "Bundle: $PKG/.build/wasm/plugins/PackageToJS/outputs/Package"
