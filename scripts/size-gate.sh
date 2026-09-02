#!/usr/bin/env bash
# Fails when the release wasm bundle exceeds the brotli budget (decision 0006: 3 MB for Counter).
# Usage: scripts/size-gate.sh Examples/Counter [budget-bytes]
set -euo pipefail
PKG="${1:-Examples/Counter}"; BUDGET="${2:-3145728}"
DIR="$PKG/.build/wasm/plugins/PackageToJS/outputs/Package"
WASM="$(ls "$DIR"/*.wasm | head -1)"
RAW=$(stat -f%z "$WASM" 2>/dev/null || stat -c%s "$WASM")
BR=$(brotli -q 11 -c "$WASM" | wc -c | tr -d ' ')
echo "$WASM: raw $RAW bytes, brotli $BR bytes (budget $BUDGET)"
[[ "$BR" -le "$BUDGET" ]] || { echo "size gate FAILED"; exit 1; }
