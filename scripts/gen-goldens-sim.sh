#!/usr/bin/env bash
# Regenerates the iOS goldens on a real iOS simulator (decision 0015): the SwiftUI iOS fixtures
# (ios/…, Fixtures/Goldens/ios, GoldenGenIOS) or the UIKit fixtures (uikit/…, Fixtures/Goldens/uikit,
# UIKitGoldenGen). The device is an iPhone SE (3rd generation) on iOS 26, the one current iPhone
# with a 2× screen, so frames land on the same half-point grid as the runtime and the macOS goldens.
# The harness is built with SwiftPM against the iPhoneSimulator SDK, wrapped in an app bundle,
# installed and launched with its console attached; the app writes straight into the repository
# (simulator processes run as the user, unsandboxed on the host file system). The status bar is
# hidden so navigation bars sit at the window's top as they do in the browser.
# Usage: scripts/gen-goldens-sim.sh ios   [filter]     (filter: a fixture-name prefix such as ios/toggle/, or text-metrics)
#        scripts/gen-goldens-sim.sh uikit [filter]     (uikit/label/, text-metrics, font-metrics; --dump [filter] prints view trees)
# GOLDENS_OUT=<dir> writes somewhere other than Fixtures/Goldens (to compare a run without touching the tree).
set -euo pipefail
[[ "$(uname)" == "Darwin" ]] || { echo "simulator goldens can only be generated on macOS"; exit 1; }
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KIND="${1:-ios}"; shift || true
case "$KIND" in
  ios)   PRODUCT=GoldenGenIOS;  BUNDLE=dev.swiftuiweb.GoldenGenIOS ;;
  uikit) PRODUCT=UIKitGoldenGen; BUNDLE=dev.swiftuiweb.UIKitGoldenGen ;;
  *) echo "usage: $0 ios|uikit [filter]"; exit 1 ;;
esac
DUMP=; if [[ "${1:-}" == "--dump" ]]; then DUMP=--dump; shift; fi
FILTER="${1:-}"

# IOS_DEVICE=ipad runs on an iPad Pro 13-inch (the regular-width idiom: split view
# controllers, uk-splitviewcontroller; 1032 pt wide in portrait, so fixtures up to that width
# fit on the screen — a window past the screen's edge snapshots stale); the default is the iPhone SE.
case "${IOS_DEVICE:-iphone}" in
  ipad) DEVICE_TYPE="com.apple.CoreSimulator.SimDeviceType.iPad-Pro-13-inch-M5-12GB"; DEVICE_LABEL="iPad"; DEVICE_FAMILY_IPAD="<integer>2</integer>" ;;
  *) DEVICE_TYPE="com.apple.CoreSimulator.SimDeviceType.iPhone-SE-3rd-generation"; DEVICE_LABEL="SE"; DEVICE_FAMILY_IPAD="" ;;
esac
# The harness built with Xcode 27's SDK no longer loads on the iOS 26.0 runtime (a SwiftUI
# conformance it references is missing there); IOS_RUNTIME selects another installed runtime,
# e.g. IOS_RUNTIME=com.apple.CoreSimulator.SimRuntime.iOS-27-0 (the golden's meta.json records the host).
RUNTIME="${IOS_RUNTIME:-com.apple.CoreSimulator.SimRuntime.iOS-26-0}"
DEVICE_NAME="SwiftUIWeb ${DEVICE_LABEL}${IOS_RUNTIME:+ ${IOS_RUNTIME##*.}}"
UDID="$(xcrun simctl list devices -j | python3 -c '
import json, sys
name, runtime = sys.argv[1], sys.argv[2]
for device in json.load(sys.stdin)["devices"].get(runtime, []):
    if device["name"] == name and device.get("isAvailable", True): print(device["udid"]); break
' "$DEVICE_NAME" "$RUNTIME")"
if [[ -z "$UDID" ]]; then
  echo "creating $DEVICE_NAME ($DEVICE_TYPE, $RUNTIME)"
  UDID="$(xcrun simctl create "$DEVICE_NAME" "$DEVICE_TYPE" "$RUNTIME")"
fi
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b >/dev/null

SDK="$(xcrun --sdk iphonesimulator --show-sdk-path)"
cd "$ROOT/Harness"
# `-Xclang-linker -isysroot`: Swift 6.4 links with `--sysroot`, which leaves clang stamping the
# deployment target (26.0) as the SDK version, and the OS treats the harness as an iOS 26 app
# (gen-goldens.sh, decision 0019).
/usr/bin/swift build -c release --product "$PRODUCT" --triple arm64-apple-ios26.0-simulator --scratch-path .build/sim \
  -Xswiftc -sdk -Xswiftc "$SDK" -Xcc -isysroot -Xcc "$SDK" -Xswiftc -Xclang-linker -Xswiftc -isysroot -Xswiftc -Xclang-linker -Xswiftc "$SDK"
APP=".build/sim/$PRODUCT.app"
rm -rf "$APP"
BIN="$(find .build/sim -type f -perm +111 -name "$PRODUCT" -not -path "*.app/*" | head -1)"
[[ -n "$BIN" ]] || { echo "$PRODUCT not built"; exit 1; }
mkdir -p "$APP"
cp "$BIN" "$APP/$PRODUCT"
cat > "$APP/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>$BUNDLE</string>
<key>CFBundleExecutable</key><string>$PRODUCT</string>
<key>CFBundleName</key><string>$PRODUCT</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>CFBundleSupportedPlatforms</key><array><string>iPhoneSimulator</string></array>
<key>DTPlatformName</key><string>iphonesimulator</string>
<key>MinimumOSVersion</key><string>26.0</string>
<key>LSRequiresIPhoneOS</key><true/>
<key>UIDeviceFamily</key><array><integer>1</integer>${DEVICE_FAMILY_IPAD}</array>
<key>UILaunchScreen</key><dict/>
<key>UIRequiresFullScreen</key><true/>
<key>UIStatusBarHidden</key><true/>
<key>UIApplicationSceneManifest</key><dict>
<key>UIApplicationSupportsMultipleScenes</key><false/>
<key>UISceneConfigurations</key><dict><key>UIWindowSceneSessionRoleApplication</key><array><dict>
<key>UISceneConfigurationName</key><string>Default</string>
<key>UISceneDelegateClassName</key><string>SceneDelegate</string>
</dict></array></dict></dict>
<key>UIViewControllerBasedStatusBarAppearance</key><false/>
</dict></plist>
PLIST
codesign -s - --force "$APP" >/dev/null 2>&1
xcrun simctl install "$UDID" "$APP"
LOG="$ROOT/Harness/.build/sim/$PRODUCT.log"
xcrun simctl launch --console-pty --terminate-running-process "$UDID" "$BUNDLE" \
  --output "${GOLDENS_OUT:-$ROOT/Fixtures/Goldens}" $DUMP ${FILTER:+--filter "$FILTER"} | tee "$LOG"
! grep -q "^FAILED" "$LOG"
