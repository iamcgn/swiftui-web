#!/usr/bin/env bash
# Copies a served app directory and fixes the WebGL painter's mode (blit, overlay, 2d, off) in its
# index.html, before the app's module runs. The painter itself is in the bundle (decision 0026);
# without a mode the page's `?webgl=` query picks it.
#   Playwright/webgl/inject.sh <served dir> <copy> [mode]
set -euo pipefail
SRC="$1"; DST="$2"; MODE="${3:-}"
rm -rf "$DST"; mkdir -p "$(dirname "$DST")"; cp -R "$SRC" "$DST"
[[ -n "$MODE" ]] || { echo "copied $SRC to $DST"; exit 0; }
TAG="<script>window.__swiftuiwebGLConfig = { mode: '$MODE' };</script>"
python3 - "$DST/index.html" "$TAG" <<'PY'
import sys, re
path, tag = sys.argv[1], sys.argv[2]
html = open(path).read()
m = re.search(r'<script\b', html)
html = html[:m.start()] + tag + '\n' + html[m.start():] if m else html.replace('</head>', tag + '\n</head>')
open(path, 'w').write(html)
PY
echo "fixed the WebGL painter's mode in $DST/index.html (mode $MODE)"
