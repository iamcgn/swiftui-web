#!/usr/bin/env bash
# Runs the Counter smoke test in Chromium, WebKit and Firefox against a built Counter bundle.
# Usage: scripts/browser-smoke.sh [--port 8765] [chromium webkit firefox]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PORT=8765
if [[ "${1:-}" == "--port" ]]; then PORT="$2"; shift 2; fi
BROWSERS=("$@"); [[ ${#BROWSERS[@]} -gt 0 ]] || BROWSERS=(chromium webkit firefox)
python3 -m http.server "$PORT" --directory "$ROOT/Examples/Counter" >/dev/null 2>&1 &
SERVER=$!
trap 'kill $SERVER 2>/dev/null || true' EXIT
sleep 1
STATUS=0
for b in "${BROWSERS[@]}"; do
  echo "== $b"
  (cd "$ROOT/Playwright" && node counter.mjs "http://127.0.0.1:$PORT/index.html" --browser "$b" --shot "$ROOT/.build/counter-$b.png") || STATUS=1
done
exit $STATUS
