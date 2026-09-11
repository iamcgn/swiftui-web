#!/usr/bin/env bash
# The Mac Catalyst fallback for the UIKit goldens (fixtures named uikit/…, Fixtures/Goldens/uikit):
# the committed goldens come from an iPhone simulator (scripts/gen-goldens-sim.sh uikit, decision
# 0015); Catalyst's UIKit measures text wider, reports other font metrics and draws the Mac switch,
# so use this only to compare, never to commit. Needs only the Command Line Tools: their SDK carries the
# Catalyst UIKit and SwiftUI under System/iOSSupport (decision 0013). UIKit runs only inside an
# app bundle with a bundle identifier, so the executable is wrapped in one and launched directly.
# Usage: scripts/gen-goldens-uikit.sh [filter]          (filter: a fixture-name prefix such as uikit/label/, text-metrics or font-metrics)
#        scripts/gen-goldens-uikit.sh --dump [filter]   prints the laid-out view trees (UIKit's internal geometry) instead
set -euo pipefail
[[ "$(uname)" == "Darwin" ]] || { echo "UIKit goldens can only be generated on macOS"; exit 1; }
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SDK="$(/usr/bin/xcrun --show-sdk-path)"
IOS="$SDK/System/iOSSupport"
[[ -d "$IOS/System/Library/Frameworks/UIKit.framework" ]] || { echo "no Catalyst UIKit under $IOS"; exit 1; }
TRIPLE="$(uname -m)-apple-ios18.0-macabi"
cd "$ROOT/Harness"
/usr/bin/swift build -c release --product UIKitGoldenGen --triple "$TRIPLE" --scratch-path .build/catalyst \
  -Xswiftc -Fsystem -Xswiftc "$IOS/System/Library/Frameworks" -Xswiftc -I -Xswiftc "$IOS/usr/lib/swift" \
  -Xcc -F"$IOS/System/Library/Frameworks" -Xcc -I"$IOS/usr/include" \
  -Xlinker -L -Xlinker "$IOS/usr/lib" -Xlinker -L -Xlinker "$IOS/usr/lib/swift" -Xlinker -F -Xlinker "$IOS/System/Library/Frameworks"
BIN="$(find .build/catalyst -type f -perm +111 -name UIKitGoldenGen | head -1)"
[[ -n "$BIN" ]] || { echo "UIKitGoldenGen not built"; exit 1; }
APP=".build/catalyst/UIKitGoldenGen.app"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/UIKitGoldenGen"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>dev.swiftuiweb.UIKitGoldenGen</string>
<key>CFBundleExecutable</key><string>UIKitGoldenGen</string>
<key>CFBundleName</key><string>UIKitGoldenGen</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>LSMinimumSystemVersion</key><string>15.0</string>
<key>UIDeviceFamily</key><array><integer>2</integer></array>
<key>LSBackgroundOnly</key><true/>
</dict></plist>
PLIST
codesign -s - --force "$APP" >/dev/null 2>&1
if [[ "${1:-}" == "--dump" ]]; then shift; DUMP=--dump; else DUMP=; fi
"$APP/Contents/MacOS/UIKitGoldenGen" --output "$ROOT/Fixtures/Goldens" $DUMP ${1:+--filter "$1"}
