#!/usr/bin/env bash
# Apple's API surface for the coverage diff (Tools/Coverage/README.md): one symbol graph folder
# per framework, extracted from the iOS SDK of the selected Xcode. macOS only.
# Usage: Tools/Coverage/apple-symbols.sh <out-dir>
set -uo pipefail
OUT="${1:?usage: apple-symbols.sh <out-dir>}"
mkdir -p "$OUT"
SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
VER="$(xcrun --sdk iphoneos --show-sdk-version)"
echo "iOS $VER ($(xcodebuild -version | head -1))" > "$OUT/sdk-version"
# SwiftUI first: the headline. The others are the frameworks SwiftUIWeb ships a module for, and
# the ones the sweep finds apps importing most.
MODULES="SwiftUI SwiftUICore Observation Combine SwiftData Charts MapKit CoreLocation AVKit AVFoundation \
  WebKit UserNotifications Speech SafariServices UIKit Foundation \
  OSLog CoreData StoreKit PhotosUI CryptoKit CoreHaptics AuthenticationServices LocalAuthentication \
  UniformTypeIdentifiers CoreTransferable TipKit WidgetKit AppIntents"
for m in $MODULES; do
  mkdir -p "$OUT/$m"
  args=(-module-name "$m" -target "arm64-apple-ios$VER" -sdk "$SDK" -output-dir "$OUT/$m" -minimum-access-level public)
  if ! xcrun swift-symbolgraph-extract "${args[@]}" -skip-synthesized-members 2> "$OUT/$m.err"; then
    xcrun swift-symbolgraph-extract "${args[@]}" 2> "$OUT/$m.err" || { echo "::warning::$m: no symbol graph ($(tail -1 "$OUT/$m.err"))"; continue; }
  fi
  echo "$m: $(ls "$OUT/$m" | wc -l | tr -d ' ') graph files"
done
