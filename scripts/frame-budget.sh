#!/usr/bin/env bash
# The landing page's frame budget (pf-perf): builds Examples/Landing in release, serves it and
# runs Playwright/frame-budget.mjs against the budgets — the first frame within 3 s of the
# resources arriving, scroll frames at a 40 ms median (a CI runner is several times slower
# than a laptop) — and reports the bundle's gzip size (what Pages serves).
# Usage: scripts/frame-budget.sh [--no-build]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PORT=8769
if [[ "${1:-}" != "--no-build" ]]; then "$ROOT/scripts/build-wasm.sh" Examples/Landing; fi
DIR="$ROOT/Examples/Landing/.build/wasm/plugins/PackageToJS/outputs/Package"
WASM="$(ls "$DIR"/*.wasm | head -1)"
GZIP=$(gzip -9 -c "$WASM" | wc -c | tr -d ' ')
echo "$WASM: gzip $GZIP bytes"
python3 -m http.server "$PORT" --bind 127.0.0.1 --directory "$ROOT/Examples/Landing" >/dev/null 2>&1 &
SERVER=$!
trap 'kill $SERVER 2>/dev/null || true' EXIT
for i in $(seq 1 60); do curl -sf "http://127.0.0.1:$PORT/index.html" >/dev/null && break; sleep 1; done
(cd "$ROOT/Playwright" && node frame-budget.mjs "http://127.0.0.1:$PORT/index.html" --first-frame-ms "${FIRST_FRAME_MS:-3000}" --frame-ms "${FRAME_MS:-40}" --gzip-bytes "$GZIP")
