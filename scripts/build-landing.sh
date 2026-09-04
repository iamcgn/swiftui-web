#!/usr/bin/env bash
# Builds the landing page as a static site for GitHub Pages: Examples/Landing/dist holds
# index.html and the wasm bundle. Usage: scripts/build-landing.sh [--debug]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
python3 "$ROOT/scripts/gen-landing-support.py"
"$ROOT/scripts/build-wasm.sh" Examples/Landing ${1:+"$1"}
DIST="$ROOT/Examples/Landing/dist"
rm -rf "$DIST" && mkdir -p "$DIST"
cp -R "$ROOT/Examples/Landing/.build/wasm/plugins/PackageToJS/outputs/Package" "$DIST/bundle"
sed 's|./.build/wasm/plugins/PackageToJS/outputs/Package/index.js|./bundle/index.js|' "$ROOT/Examples/Landing/index.html" > "$DIST/index.html"
touch "$DIST/.nojekyll"
echo "Site: $DIST ($(du -sh "$DIST" | cut -f1)); serve with: python3 -m http.server --directory $DIST"
