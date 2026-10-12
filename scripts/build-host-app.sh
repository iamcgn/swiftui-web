#!/usr/bin/env bash
# Wraps Tools/Host's swiftui-host as dist/SwiftUIHost.app (pf-native-text): an app the Finder
# opens `.swiftuiweb` bundles with by double click (a built package directory — the output of
# scripts/build-wasm.sh — renamed with the extension) and that takes bundle folders dropped on
# it; each opens in a window of its own. Usage: scripts/build-host-app.sh [dist-dir]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="${1:-$ROOT/dist}"
APP="$DIST/SwiftUIHost.app"
(cd "$ROOT/Tools/Host" && /usr/bin/swift build -c release 2>&1 | tail -1)
BIN="$ROOT/Tools/Host/.build/release/swiftui-host"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/SwiftUIHost"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>dev.swiftuiweb.host</string>
<key>CFBundleExecutable</key><string>SwiftUIHost</string>
<key>CFBundleName</key><string>SwiftUIHost</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>CFBundleDocumentTypes</key><array>
  <dict>
    <key>CFBundleTypeName</key><string>SwiftUIWeb bundle</string>
    <key>CFBundleTypeRole</key><string>Viewer</string>
    <key>LSHandlerRank</key><string>Owner</string>
    <key>LSItemContentTypes</key><array><string>dev.swiftuiweb.bundle</string></array>
  </dict>
  <dict>
    <key>CFBundleTypeName</key><string>Folder</string>
    <key>CFBundleTypeRole</key><string>Viewer</string>
    <key>LSHandlerRank</key><string>Alternate</string>
    <key>LSItemContentTypes</key><array><string>public.folder</string></array>
  </dict>
</array>
<key>UTExportedTypeDeclarations</key><array>
  <dict>
    <key>UTTypeIdentifier</key><string>dev.swiftuiweb.bundle</string>
    <key>UTTypeDescription</key><string>SwiftUIWeb bundle</string>
    <key>UTTypeConformsTo</key><array><string>com.apple.package</string><string>public.directory</string></array>
    <key>UTTypeTagSpecification</key><dict><key>public.filename-extension</key><array><string>swiftuiweb</string></array></dict>
  </dict>
</array>
</dict></plist>
PLIST
codesign -s - --force "$APP" >/dev/null 2>&1 || true
echo "$APP"
