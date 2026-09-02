#!/usr/bin/env bash
# Reproduces the development environment on a clean macOS or Linux machine.
set -euo pipefail
SWIFT_VERSION="$(cat "$(dirname "$0")/../.swift-version")"
WASM_SDK_URL="https://download.swift.org/swift-${SWIFT_VERSION}-release/wasm-sdk/swift-${SWIFT_VERSION}-RELEASE/swift-${SWIFT_VERSION}-RELEASE_wasm.artifactbundle.tar.gz"
WASM_SDK_CHECKSUM="cabfa08b73bb8ac783927ecd15fa386e99d0c139c5f232445067bcf58379cae7"  # 6.3.3; update with .swift-version

if ! command -v swiftly >/dev/null; then
  if [[ "$(uname)" == "Darwin" ]]; then brew install swiftly binaryen
  else
    curl -O https://download.swift.org/swiftly/linux/swiftly-$(uname -m).tar.gz
    tar zxf swiftly-$(uname -m).tar.gz && ./swiftly init --assume-yes --skip-install --no-modify-profile
  fi
fi
[[ -f "$HOME/.swiftly/config.json" ]] || swiftly init --assume-yes --skip-install --no-modify-profile
# shellcheck disable=SC1091
. "$(dirname "$0")/env.sh"
swiftly install "$SWIFT_VERSION" --use --assume-yes
swift sdk list | grep -q "swift-${SWIFT_VERSION}-RELEASE_wasm" || \
  swift sdk install "$WASM_SDK_URL" --checksum "$WASM_SDK_CHECKSUM"
swift --version
swift sdk list
echo "OK. Add '. ~/.swiftly/env.sh' to your shell profile."
