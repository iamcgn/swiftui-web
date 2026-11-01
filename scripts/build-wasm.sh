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
# SWIFTUIWEB_WASM_SDK picks the Swift SDK: the stock one, or the Objective-C runtime one
# (`swift-<version>-RELEASE_wasm-objc`, decision 0023) that unmodified @objc apps need.
SDK="${SWIFTUIWEB_WASM_SDK:-swift-$(cat "$ROOT/.swift-version")-RELEASE_wasm}"
# shellcheck disable=SC1091
. "$(dirname "$0")/env.sh"
case "$PKG" in *Gallery|*Gallery/) python3 "$(dirname "$0")/gen-fixture-sources.py";; esac   # fixture code shown in the gallery
cd "$PKG"
# Package traits the app needs (decision 0024): a Core Data app whose files import only SwiftUI
# or Foundation needs the CoreData trait on its SwiftUIWeb and Shadows dependencies, and an app
# that names Decimal needs the DecimalFormatting trait on Shadows for Decimal.formatted; one that
# names DateComponentsFormatter or the like needs FoundationFormats on SwiftUIWeb.
python3 "$ROOT/Tools/Traits/traits.py" . --check Package.swift || true
# The 4 MB wasm stack (wasm-ld defaults to 64 KB) is set per package in Package.swift (linkerSettings).
# Each SDK builds in a scratch path of its own: a module the stock SDK's compiler wrote is
# stale for the Objective-C runtime SDK's and the other way round (the same triple, different
# compilers and `canImport`s — SwiftPM does not rebuild it). The page loads the bundle from
# `.build/wasm`, so another SDK's bundle is copied there after its build.
STOCK_SDK="swift-$(cat "$ROOT/.swift-version")-RELEASE_wasm"
SCRATCH=.build/wasm; [[ "$SDK" != "$STOCK_SDK" ]] && SCRATCH=".build/wasm-${SDK#swift-*-RELEASE_wasm-}"
# No `.swift_modhash`: swiftc stamps each object with a hash of its LLVM module (to skip
# unchanged codegen in incremental builds). On Mach-O and ELF it is a section the loader never
# maps, but wasm-ld links it as data, so every bundle shipped about 7 KB of hashes that brotli
# cannot compress, and some of them changed from one clean build to the next (the drift of
# Counter's compressed size around the decision 0006 budget).
NO_MODHASH=(-Xswiftc -Xfrontend -Xswiftc -disable-incremental-llvm-codegen)
if [[ $DEBUG == 1 ]]; then
  swift package --disable-sandbox --swift-sdk "$SDK" --scratch-path "$SCRATCH" "${NO_MODHASH[@]}" js $PRODUCT_FLAG --use-cdn --debug-info-format dwarf
else
  # `-internalize-at-link`: without it the compiler marks every public declaration as used, so
  # the linker keeps each library's whole public surface whether or not the app calls it (an
  # unused `NSString.draw(at:)` shipped in Counter). With it, public symbols are ordinary ones
  # that `--gc-sections` drops when nothing references them. An executable is the end of the
  # line, so nothing outside the bundle can need them (decision 0006: Counter 3,145,362 →
  # 3,050,901 bytes brotli).
  swift package --disable-sandbox --swift-sdk "$SDK" --scratch-path "$SCRATCH" -c release -Xswiftc -Osize "${NO_MODHASH[@]}" \
    -Xswiftc -Xfrontend -Xswiftc -internalize-at-link js $PRODUCT_FLAG --use-cdn
fi
# Asset catalogs (decision 0011): every *.xcassets of the package becomes assets/manifest.js plus
# the image files in the bundle; index.html includes the script before the module.
BUNDLE=".build/wasm/plugins/PackageToJS/outputs/Package"
if [[ "$SCRATCH" != .build/wasm ]]; then
  rm -rf "$BUNDLE" && mkdir -p "$(dirname "$BUNDLE")" && cp -R "$SCRATCH/plugins/PackageToJS/outputs/Package" "$BUNDLE"
fi
# An app of decision 0021 takes the catalogs of its own upstream tree (Apps/README.md), not
# every app's (three AccentColors).
case "$PKG" in *Gallery|*Gallery/) ASSETS="$ROOT/Fixtures";; *) ASSETS=".";; esac
case "$PRODUCT" in
  SwiftUI2048) ASSETS="upstream/SwiftUI-2048";;
  Scrumdinger) ASSETS="upstream/Scrumdinger";;
  Ember) ASSETS="upstream/ember-hackernews";;
esac
rm -rf "$BUNDLE/assets"
python3 "$ROOT/scripts/assets.py" "$ASSETS" --js "$BUNDLE/assets/manifest.js" --out "$BUNDLE/assets"
# A package target's processed resources (`resources: [.process("Resources")]`, SwiftPM lays
# them out as `<Package>_<Target>.resources`) join the assets, where `Bundle.url(forResource:)`
# looks (decision 0021); catalogs and string catalogs are the manifest's.
for RES in "$SCRATCH"/wasm32-unknown-wasip1/*/*.resources; do
  [[ -d "$RES" ]] || continue
  (cd "$RES" && find . -type f ! -path '*.xcassets/*' ! -name '*.xcstrings' ! -name 'Info.plist' | while read -r f; do
    mkdir -p "$OLDPWD/$BUNDLE/assets/$(dirname "$f")" && cp "$f" "$OLDPWD/$BUNDLE/assets/$f"; done)
done
# The full SF Symbol layout table (sw-symbols): fetched by the host on the first symbol outside
# the built-in set.
cp "$ROOT/Fixtures/Goldens/symbol/metrics-full.txt" "$BUNDLE/assets/symbol-metrics.txt"
echo "Bundle: $PKG/$BUNDLE"
