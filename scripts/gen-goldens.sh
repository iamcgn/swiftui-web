#!/usr/bin/env bash
# Regenerates goldens with Apple's SwiftUI (macOS only). Usage: scripts/gen-goldens.sh [filter]
set -euo pipefail
[[ "$(uname)" == "Darwin" ]] || { echo "Goldens can only be generated on macOS"; exit 1; }
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# Use the Apple toolchain (Command Line Tools / Xcode), not swiftly's, for the harness.
cd "$ROOT/Harness" && /usr/bin/swift run -c release GoldenGen --output "$ROOT/Fixtures/Goldens" ${1:+--filter "$1"}
