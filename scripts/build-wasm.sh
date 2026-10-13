#!/usr/bin/env bash
# Builds a wasm bundle for an example/app package using the JavaScriptKit PackageToJS plugin.
# Usage: scripts/build-wasm.sh Examples/Counter [--debug] [--product Name]
#        scripts/build-wasm.sh Apps --product Scrumdinger   (one of the apps of decision 0021)
set -euo pipefail
PKG="${1:-Examples/Counter}"; shift || true
DEBUG=0; PRODUCT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --debug) DEBUG=1; shift;;
    --product) PRODUCT="$2"; shift 2;;
    *) echo "unknown argument $1"; exit 1;;
  esac
done
PRODUCT_FLAG=""; [[ -n "$PRODUCT" ]] && PRODUCT_FLAG="--product $PRODUCT"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SDK="swift-$(cat "$ROOT/.swift-version")-RELEASE_wasm"
# shellcheck disable=SC1091
. "$(dirname "$0")/env.sh"
case "$PKG" in *Gallery|*Gallery/) python3 "$(dirname "$0")/gen-fixture-sources.py";; esac   # fixture code shown in the gallery
cd "$PKG"
# The 4 MB wasm stack (wasm-ld defaults to 64 KB) is set per package in Package.swift (linkerSettings).

if [[ $DEBUG == 1 ]]; then
  swift package --disable-sandbox --swift-sdk "$SDK" --scratch-path .build/wasm js $PRODUCT_FLAG --use-cdn --debug-info-format dwarf
else
  swift package --disable-sandbox --swift-sdk "$SDK" --scratch-path .build/wasm -c release -Xswiftc -Osize js $PRODUCT_FLAG --use-cdn
fi
# Asset catalogs (decision 0011): every *.xcassets of the package becomes assets/manifest.js plus
# the image files in the bundle; index.html includes the script before the module.
BUNDLE=".build/wasm/plugins/PackageToJS/outputs/Package"
# An app of decision 0021 takes the catalogs of its own upstream tree (Apps/README.md), not
# every app's (three AccentColors).
case "$PKG" in *Gallery|*Gallery/) ASSETS="$ROOT/Fixtures";; *) ASSETS=".";; esac
case "$PRODUCT" in
  SwiftUI2048) ASSETS="upstream/SwiftUI-2048";;
  Scrumdinger) ASSETS="upstream/Scrumdinger";;
  CountriesSwiftUI) ASSETS="upstream/clean-architecture-swiftui";;
esac
rm -rf "$BUNDLE/assets"
python3 "$ROOT/scripts/assets.py" "$ASSETS" --js "$BUNDLE/assets/manifest.js" --out "$BUNDLE/assets"
# A package target's processed resources (`resources: [.process("Resources")]`, SwiftPM lays
# them out as `<Package>_<Target>.resources`) join the assets, where `Bundle.url(forResource:)`
# looks (decision 0021); catalogs and string catalogs are the manifest's.
for RES in .build/wasm/wasm32-unknown-wasip1/*/*.resources; do
  [[ -d "$RES" ]] || continue
  (cd "$RES" && find . -type f ! -path '*.xcassets/*' ! -name '*.xcstrings' ! -name 'Info.plist' | while read -r f; do
    mkdir -p "$OLDPWD/$BUNDLE/assets/$(dirname "$f")" && cp "$f" "$OLDPWD/$BUNDLE/assets/$f"; done)
done
# The full SF Symbol layout table (sw-symbols): fetched by the host on the first symbol outside
# the built-in set.
cp "$ROOT/Fixtures/Goldens/symbol/metrics-full.txt" "$BUNDLE/assets/symbol-metrics.txt"
echo "Bundle: $PKG/$BUNDLE"
