# 0013. iOS goldens come from a UIKit window on Mac Catalyst, built with the Command Line Tools

Date: 2026-09-05
Status: accepted (the user's first choice was the iOS Simulator; it needs Xcode, which this
machine does not have, so Catalyst is the route until then)

## Context

The iOS platform profile (Phase 4, item 3) needs goldens rendered by Apple's iOS SwiftUI. The
roadmap left two options open: Xcode's simulator, or the Catalyst trick (spike 0.10, never run).

## Evidence (macOS 26.2, Command Line Tools 26.2, 2026-09-05)

- The CLT SDK ships Mac Catalyst under `MacOSX.sdk/System/iOSSupport`: `UIKit.framework`,
  `SwiftUI.framework` and the Swift modules. `swiftc -target arm64-apple-ios18.0-macabi -sdk $SDK
  -Fsystem $SDK/System/iOSSupport/System/Library/Frameworks -I $SDK/System/iOSSupport/usr/lib/swift
  -L $SDK/System/iOSSupport/usr/lib -L $SDK/System/iOSSupport/usr/lib/swift` compiles and links a
  UIKit + SwiftUI program; SwiftPM does the same with `--triple arm64-apple-ios18.0-macabi` and
  the flags as `-Xswiftc`/`-Xcc`/`-Xlinker`, given `platforms: [.macCatalyst("18.0")]`.
- UIKit needs an app: a bare executable throws "NSApplication has not been created yet"
  (creating a `UIWindow`) and "Invalid parameter not satisfying: bundleIdentifier"
  (`UIApplicationMain`). A minimal `.app` bundle (Info.plist with `CFBundleIdentifier`,
  `CFBundleExecutable`, `UIDeviceFamily` 2, `LSBackgroundOnly`; ad-hoc codesign) run through
  `UIApplicationMain` works. Without a window, preferences never deliver and `layer.render`
  is blank; in a key window `drawHierarchy(afterScreenUpdates:)` captures at scale 2.
- The hosted view reports iOS geometry: `UIFont.preferredFont(.body)` 17 pt, a `Toggle` row
  28 pt tall, a `Slider` 31, a `TextField` 25, `Button("Tap")` 28.5 × 24.5. The idiom is iPad
  (`userInterfaceIdiom` 1, regular size class), which shares its text styles and controls with
  iPhone; iPhone-only behaviour (compact size class layouts, sheets vs popovers) is not covered.
- macOS-only APIs in the shared fixtures (`.checkbox`, `.radioGroup`, `.squareBorder`,
  `.bordered` lists, `.field` date pickers, `onMoveCommand`, `pointerStyle`) fail to compile for
  Catalyst; those statements are guarded with `#if !targetEnvironment(macCatalyst)`.

## Decision

- `Harness` gains `GoldenKit` (the generation shared by both hosts) and `GoldenGenCatalyst`
  (a `UIKitHost`: `UIHostingController` with `safeAreaRegions = []` in a `UIWindow` grown so the
  hosting view is exactly the fixture size). `scripts/gen-goldens-ios.sh [filter]` builds it,
  wraps it in the bundle and runs it.
- iOS fixtures are named `ios/…` and marked `.platform(.iOS)`; their goldens live under
  `Fixtures/Goldens/ios/` with `platformProfile: "iOS"` and `host: "macCatalyst"` in meta.json,
  their text metrics in `Fixtures/Goldens/ios/text-metrics.json`
  (`scripts/font-metrics-table.py --profile ios` → `SystemFontMetricsTableIOS.swift`).
- The runtime's `PlatformProfile.iOS` (text styles, `.body` default font, `PlatformMetricsTable.iOS`)
  is selected per fixture by `FixtureRunner`, the gallery and Tier A/C; hosts keep macOS as the
  default until the profile covers enough of the library to switch touch devices over.
- `PlatformMetrics` became a table per profile (`PlatformMetricsTable`, macOS values in place,
  iOS overrides in PlatformMetricsIOS.swift) read through generated accessors; `ViewNode`
  selects the table of its environment's profile on every layout and paint entry, so one page
  can hold subtrees in either look (the landing page's iOS demo).

## Consequences

- No Xcode or simulator is needed for iOS goldens; when Xcode is available, a simulator host can
  implement the same `GoldenHost` and replace the Catalyst run (iPhone idiom, compact size class).
- Catalyst renders through the Mac's window server: pixels are the Mac's antialiasing at 2×,
  not an iPhone's 3×; Tier B/C tolerances apply as for macOS.
