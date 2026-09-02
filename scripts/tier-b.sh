#!/usr/bin/env bash
# Tier B: browser fidelity check. Builds the fixture gallery for wasm (unless --no-build), serves
# it, and compares probe frames and pixels against Fixtures/Goldens in headless Chromium.
# Usage: scripts/tier-b.sh [--no-build] [--filter layout/] [--port 8766] [--browser chromium|webkit|firefox]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD=1; FILTER=""; PORT=8766; BROWSER=chromium
while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-build) BUILD=0; shift;;
    --filter) FILTER="$2"; shift 2;;
    --port) PORT="$2"; shift 2;;
    --browser) BROWSER="$2"; shift 2;;
    *) echo "unknown argument $1"; exit 1;;
  esac
done
if [[ $BUILD == 1 ]]; then "$ROOT/scripts/build-wasm.sh" Examples/Gallery --debug; fi
[[ -d "$ROOT/Playwright/node_modules" ]] || (cd "$ROOT/Playwright" && npm install && npm run install-browsers)
python3 -m http.server "$PORT" --directory "$ROOT/Examples/Gallery" >/dev/null 2>&1 &
SERVER=$!
trap 'kill $SERVER 2>/dev/null || true' EXIT
sleep 1
cd "$ROOT/Playwright" && node tier-b.mjs "http://127.0.0.1:$PORT/index.html" --filter "$FILTER" --browser "$BROWSER" --out "$ROOT/.build/tier-b-$BROWSER"
