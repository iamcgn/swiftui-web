#!/usr/bin/env bash
# Regenerates goldens with Apple's SwiftUI (macOS only). Usage: scripts/gen-goldens.sh [filter]
set -euo pipefail
[[ "$(uname)" == "Darwin" ]] || { echo "Goldens can only be generated on macOS"; exit 1; }
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# Use the Apple toolchain (Command Line Tools / Xcode), not swiftly's, for the harness.
# Swift 6.4's build links through clang with `--sysroot`, which does not tell clang the SDK's
# version: it stamps the deployment target (15.4) as the SDK in LC_BUILD_VERSION and macOS 27
# then draws the pre-26 controls for the harness (20 pt buttons, 14 pt checkboxes, a 44 × 23
# colour well: the "macOS 27 control sizes" of 2026-10). `-isysroot` to the clang link step
# names the SDK whose version is stamped (decision 0019).
SDK="$(xcrun --sdk macosx --show-sdk-path)"
cd "$ROOT/Harness" && /usr/bin/swift run -c release -Xswiftc -Xclang-linker -Xswiftc -isysroot -Xswiftc -Xclang-linker -Xswiftc "$SDK" \
  GoldenGen --output "$ROOT/Fixtures/Goldens" ${1:+--filter "$1"}
