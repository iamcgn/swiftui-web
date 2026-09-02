#!/usr/bin/env bash
# Serves a built wasm bundle. Usage: scripts/serve.sh Examples/Counter [port]
set -euo pipefail
PKG="${1:-Examples/Counter}"; PORT="${2:-8080}"
DIR="$PKG/.build/wasm/plugins/PackageToJS/outputs/Package"
[[ -d "$DIR" ]] || { echo "No bundle at $DIR; run scripts/build-wasm.sh $PKG first"; exit 1; }
echo "http://localhost:$PORT/"
python3 -m http.server "$PORT" --directory "$PKG"
