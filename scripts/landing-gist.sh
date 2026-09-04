#!/usr/bin/env bash
# Keeps the landing page's sources in sync with a GitHub gist.
#   scripts/landing-gist.sh pull <gist-id-or-url>   downloads every file of the gist into Examples/Landing/Sources/Landing
#   scripts/landing-gist.sh push [<gist-id>]        creates (or updates) a gist from those files with the gh CLI
# The sources depend on nothing but `import SwiftUI`, so the gist is the whole app; build it with
# scripts/build-wasm.sh Examples/Landing (or scripts/build-landing.sh for a GitHub Pages bundle).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/Examples/Landing/Sources/Landing"
case "${1:-}" in
  pull)
    ID="${2:?gist id or url}"; ID="${ID##*/}"
    curl -fsSL "https://api.github.com/gists/$ID" | python3 -c '
import json, sys, urllib.request, pathlib
gist = json.load(sys.stdin)
target = pathlib.Path(sys.argv[1])
for name, info in gist["files"].items():
    if not name.endswith(".swift"): continue
    content = info["content"] if not info.get("truncated") else urllib.request.urlopen(info["raw_url"]).read().decode()
    (target / name).write_text(content)
    print(f"wrote {target / name}")
' "$SRC"
    ;;
  push)
    command -v gh >/dev/null || { echo "push needs the gh CLI (brew install gh)"; exit 1; }
    if [[ -n "${2:-}" ]]; then
      for f in "$SRC"/*.swift; do gh gist edit "$2" -f "$(basename "$f")" "$f"; done
      echo "updated gist $2"
    else
      gh gist create --public --desc "SwiftUIWeb landing page (Examples/Landing)" "$SRC"/*.swift
    fi
    ;;
  *) echo "usage: $0 pull <gist-id-or-url> | push [<gist-id>]"; exit 1;;
esac
