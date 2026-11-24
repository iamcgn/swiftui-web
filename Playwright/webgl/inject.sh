#!/usr/bin/env bash
# Copies a served app directory and loads the WebGL painter shim in its index.html, before the
# app's module runs. With a mode (blit, overlay, 2d) the copy is fixed to it; without one the
# page's `?webgl=` query picks it.
#   Playwright/webgl/inject.sh <served dir> <copy> [mode]
set -euo pipefail
SRC="$1"; DST="$2"; MODE="${3:-}"
HERE="$(cd "$(dirname "$0")" && pwd)"
rm -rf "$DST"; mkdir -p "$(dirname "$DST")"; cp -R "$SRC" "$DST"
cp "$HERE/painter-gl.js" "$DST/painter-gl.js"
TAG='<script src="./painter-gl.js"></script>'
[[ -n "$MODE" ]] && TAG="<script>window.__swiftuiwebGLConfig = { mode: '$MODE' };</script>$TAG"
python3 - "$DST/index.html" "$TAG" <<'PY'
import sys, re
path, tag = sys.argv[1], sys.argv[2]
html = open(path).read()
m = re.search(r'<script\b', html)
html = html[:m.start()] + tag + '\n' + html[m.start():] if m else html.replace('</head>', tag + '\n</head>')
open(path, 'w').write(html)
PY
echo "injected the WebGL painter into $DST/index.html${MODE:+ (mode $MODE)}"
