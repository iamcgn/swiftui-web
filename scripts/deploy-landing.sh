#!/usr/bin/env bash
# Publishes the landing page to GitHub Pages: builds Examples/Landing/dist (release) and pushes
# its contents as the `gh-pages` branch of the repository (Pages source: gh-pages, root).
# Usage: scripts/deploy-landing.sh [--no-build] [remote-url]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD=1
if [[ "${1:-}" == "--no-build" ]]; then BUILD=0; shift; fi
REMOTE="${1:-$(git -C "$ROOT" remote get-url origin)}"
[[ $BUILD == 1 ]] && "$ROOT/scripts/build-landing.sh"
DIST="$ROOT/Examples/Landing/dist"
[[ -f "$DIST/index.html" ]] || { echo "no site in $DIST; run scripts/build-landing.sh"; exit 1; }
SHA="$(git -C "$ROOT" rev-parse --short HEAD)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cp -R "$DIST/." "$TMP/"
cd "$TMP"
git init -q -b gh-pages
git add -A
git -c user.name="$(git -C "$ROOT" config user.name)" -c user.email="$(git -C "$ROOT" config user.email)" \
  commit -q -m "Landing page built from $SHA"
git push -f "$REMOTE" gh-pages:gh-pages
echo "Pushed gh-pages ($(du -sh "$TMP" | cut -f1)); Pages serves it at https://<owner>.github.io/<repo>/ once enabled."
