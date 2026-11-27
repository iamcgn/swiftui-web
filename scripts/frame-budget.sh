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
# A server another job left on the port (a self-hosted runner keeps the machine between jobs)
# would answer in this one's place and 404 the bundle: take a free port then, and say what
# holds the usual one.
if curl -s -o /dev/null --max-time 2 "http://127.0.0.1:$PORT/"; then
  echo "port $PORT is already answering; holder:"
  (lsof -nP -iTCP:"$PORT" -sTCP:LISTEN 2>/dev/null || true) | sed 's/^/  /'
  PORT=$(python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')
  echo "using port $PORT"
fi
python3 -m http.server "$PORT" --bind 127.0.0.1 --directory "$ROOT/Examples/Landing" >/dev/null 2>&1 &
SERVER=$!
trap 'kill $SERVER 2>/dev/null || true' EXIT
BUNDLE_URL="http://127.0.0.1:$PORT/.build/wasm/plugins/PackageToJS/outputs/Package/index.js"
for i in $(seq 1 60); do curl -sf "$BUNDLE_URL" >/dev/null && break; sleep 1; done
# Fail here, not two minutes later as a missing first frame, when the server isn't this one or
# doesn't have the bundle.
kill -0 "$SERVER" 2>/dev/null || { echo "the server on port $PORT exited (port taken?)"; exit 1; }
curl -sf "$BUNDLE_URL" >/dev/null || { echo "the server on port $PORT does not serve $BUNDLE_URL"; ls "$DIR"; exit 1; }
(cd "$ROOT/Playwright" && node frame-budget.mjs "http://127.0.0.1:$PORT/index.html" --first-frame-ms "${FIRST_FRAME_MS:-3000}" --frame-ms "${FRAME_MS:-40}" --gzip-bytes "$GZIP")
# The Controls demo (issue 54): Notifications toggles off and on again by keyboard, and Name follows it.
(cd "$ROOT/Playwright" && node landing-controls-probe.mjs "http://127.0.0.1:$PORT/index.html")
