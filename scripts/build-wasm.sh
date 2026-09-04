#!/usr/bin/env bash
# Builds a wasm bundle for an example/app package using the JavaScriptKit PackageToJS plugin.
# Usage: scripts/build-wasm.sh Examples/Counter [--debug]
set -euo pipefail
PKG="${1:-Examples/Counter}"; shift || true
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SDK="swift-$(cat "$ROOT/.swift-version")-RELEASE_wasm"
# shellcheck disable=SC1091
. "$(dirname "$0")/env.sh"
case "$PKG" in *Gallery|*Gallery/) python3 "$(dirname "$0")/gen-fixture-sources.py";; esac   # fixture code shown in the gallery
cd "$PKG"
# The 4 MB wasm stack (wasm-ld defaults to 64 KB) is set per package in Package.swift (linkerSettings).

if [[ "${1:-}" == "--debug" ]]; then
  swift package --disable-sandbox --swift-sdk "$SDK" --scratch-path .build/wasm js --use-cdn --debug-info-format dwarf
else
  swift package --disable-sandbox --swift-sdk "$SDK" --scratch-path .build/wasm -c release -Xswiftc -Osize js --use-cdn
fi
# Asset catalogs (decision 0011): every *.xcassets of the package becomes assets/manifest.js plus
# the image files in the bundle; index.html includes the script before the module.
BUNDLE=".build/wasm/plugins/PackageToJS/outputs/Package"
case "$PKG" in *Gallery|*Gallery/) ASSETS="$ROOT/Fixtures";; *) ASSETS=".";; esac
rm -rf "$BUNDLE/assets"
python3 "$ROOT/scripts/assets.py" "$ASSETS" --js "$BUNDLE/assets/manifest.js" --out "$BUNDLE/assets"
echo "Bundle: $PKG/$BUNDLE"
