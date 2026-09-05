#!/usr/bin/env bash
# Regenerates the iOS goldens (fixtures named ios/…, Fixtures/Goldens/ios) with Apple's SwiftUI
# in a UIKit window on Mac Catalyst. Needs only the Command Line Tools: their SDK carries the
# Catalyst UIKit and SwiftUI under System/iOSSupport (decision 0013). UIKit runs only inside an
# app bundle with a bundle identifier, so the executable is wrapped in one and launched directly.
# Usage: scripts/gen-goldens-ios.sh [filter]     (filter: a fixture-name prefix such as ios/toggle/)
set -euo pipefail
[[ "$(uname)" == "Darwin" ]] || { echo "iOS goldens can only be generated on macOS"; exit 1; }
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SDK="$(/usr/bin/xcrun --show-sdk-path)"
IOS="$SDK/System/iOSSupport"
[[ -d "$IOS/System/Library/Frameworks/UIKit.framework" ]] || { echo "no Catalyst UIKit under $IOS"; exit 1; }
TRIPLE="$(uname -m)-apple-ios18.0-macabi"
cd "$ROOT/Harness"
/usr/bin/swift build -c release --product GoldenGenCatalyst --triple "$TRIPLE" --scratch-path .build/catalyst \
  -Xswiftc -Fsystem -Xswiftc "$IOS/System/Library/Frameworks" -Xswiftc -I -Xswiftc "$IOS/usr/lib/swift" \
  -Xcc -F"$IOS/System/Library/Frameworks" -Xcc -I"$IOS/usr/include" \
  -Xlinker -L -Xlinker "$IOS/usr/lib" -Xlinker -L -Xlinker "$IOS/usr/lib/swift" -Xlinker -F -Xlinker "$IOS/System/Library/Frameworks"
BIN="$(find .build/catalyst -type f -perm +111 -name GoldenGenCatalyst | head -1)"
[[ -n "$BIN" ]] || { echo "GoldenGenCatalyst not built"; exit 1; }
APP=".build/catalyst/GoldenGenCatalyst.app"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/GoldenGenCatalyst"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>dev.swiftuiweb.GoldenGenCatalyst</string>
<key>CFBundleExecutable</key><string>GoldenGenCatalyst</string>
<key>CFBundleName</key><string>GoldenGenCatalyst</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>LSMinimumSystemVersion</key><string>15.0</string>
<key>UIDeviceFamily</key><array><integer>2</integer></array>
<key>LSBackgroundOnly</key><true/>
</dict></plist>
PLIST
codesign -s - --force "$APP" >/dev/null 2>&1
"$APP/Contents/MacOS/GoldenGenCatalyst" --output "$ROOT/Fixtures/Goldens" ${1:+--filter "$1"}
