// swift-tools-version: 6.2
import PackageDescription
import CompilerPluginSupport

// SwiftUIWeb: an open-source SwiftUI reimplementation that runs unmodified SwiftUI
// source in the browser (WebAssembly + Canvas) and, later, natively.
//
// Module layout (see Docs/ARCHITECTURE.md):
//   SwiftUI              thin re-export so apps can `import SwiftUI` unchanged
//   SwiftUIWebCore       API + runtime + layout + text + display list
//   SwiftUIWebHeadless   headless renderer over the substrate's recorded text metrics
//   SwiftUIWebCanvas     the runtime in the substrate's wasm canvas host
//   SwiftUIWebNative     the runtime in the substrate's AppKit host
//   SwiftUIWebTestSupport fixture registry, golden codecs, comparators
//   SwiftUIWebUIKit      UIViewRepresentable / UIViewControllerRepresentable over UIKitWeb (decision 0014)
//   Packages/WebGraphics the graphics substrate shared with UIKitWeb (decision 0014)
//   Packages/UIKitWeb    the UIKit reimplementation SwiftUI depends on, as Apple's does on iOS

let package = Package(
    name: "SwiftUIWeb",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SwiftUI", targets: ["SwiftUI"]),
        .library(name: "Charts", targets: ["Charts"]),
        .library(name: "MapKit", targets: ["MapKit"]),
        .library(name: "AVFoundation", targets: ["AVFoundation"]),
        .library(name: "AVKit", targets: ["AVKit"]),
        .library(name: "Speech", targets: ["Speech"]),
        .library(name: "SwiftData", targets: ["SwiftData"]),
        .library(name: "UserNotifications", targets: ["UserNotifications"]),
        .library(name: "WebKit", targets: ["WebKit"]),
        .library(name: "SwiftUIWebCanvas", targets: ["SwiftUIWebCanvas"]),
        .library(name: "SwiftUIWebNative", targets: ["SwiftUIWebNative"]),
        .library(name: "SwiftUIWebHeadless", targets: ["SwiftUIWebHeadless"]),
        .library(name: "FixtureKit", targets: ["FixtureKit"]),
        .library(name: "SwiftUIWebFixtures", targets: ["SwiftUIWebFixtures"]),
    ],
    dependencies: [
        // The graphics substrate shared with UIKitWeb (decision 0014), and UIKitWeb itself: the
        // `SwiftUI` module re-exports `UIKit` the way Apple's does on iOS.
        .package(path: "Packages/WebGraphics"),
        .package(path: "Packages/UIKitWeb"),
        .package(url: "https://github.com/swiftwasm/JavaScriptKit.git", from: "0.49.0"),
        // Only for the `#Preview` macro plugin (expands to nothing); SwiftPM uses prebuilt libraries.
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "601.0.1"),
    ],
    targets: [
        .target(
            name: "SwiftUI",
            dependencies: [
                "SwiftUIWebCore",
                "SwiftUIWebMacros",
                "SwiftUIWebUIKit",
                .product(name: "UIKit", package: "UIKitWeb"),
                .product(name: "WebFoundation", package: "WebGraphics"),
                .product(name: "WebCombine", package: "WebGraphics"),
                .target(name: "SwiftUIWebCanvas", condition: .when(platforms: [.wasi])),
                .target(name: "SwiftUIWebNative", condition: .when(platforms: [.macOS])),
            ],
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
        // Swift Charts over the display list (sw-frameworks, decision 0018): `import Charts`.
        .target(
            name: "Charts",
            dependencies: ["SwiftUI"],
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
        // Map, VideoPlayer and WebView (sw-frameworks): painted tiles, host elements over the canvas.
        .target(name: "CoreLocation", dependencies: [.product(name: "WebFoundation", package: "WebGraphics")], swiftSettings: [.treatAllWarnings(as: .error)]),
        .target(name: "MapKit", dependencies: ["SwiftUI", "CoreLocation"], swiftSettings: [.treatAllWarnings(as: .error)]),
        .target(name: "AVFoundation", dependencies: [.product(name: "WebFoundation", package: "WebGraphics")], swiftSettings: [.treatAllWarnings(as: .error)]),
        .target(name: "AVKit", dependencies: ["SwiftUI", "AVFoundation"], swiftSettings: [.treatAllWarnings(as: .error)]),
        .target(name: "SwiftData", dependencies: ["SwiftUIWebCore", "SwiftDataMacros", .product(name: "WebFoundation", package: "WebGraphics"), .product(name: "WebCombine", package: "WebGraphics")], swiftSettings: [.treatAllWarnings(as: .error)]),
        // The `@Model`, `#Predicate` and `@ModelActor` macros (host-compiled, as `#Preview`'s plugin).
        .macro(
            name: "SwiftDataMacros",
            dependencies: [
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
            ],
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
        .target(name: "UserNotifications", dependencies: [.product(name: "WebFoundation", package: "WebGraphics")], swiftSettings: [.treatAllWarnings(as: .error)]),
        .target(name: "Speech", dependencies: ["AVFoundation", .product(name: "WebFoundation", package: "WebGraphics")], swiftSettings: [.treatAllWarnings(as: .error)]),
        .target(name: "WebKit", dependencies: ["SwiftUI"], swiftSettings: [.treatAllWarnings(as: .error)]),
        // The representables (decision 0014, Phase 2): UIKit views hosted as SwiftUI leaves.
        .target(
            name: "SwiftUIWebUIKit",
            dependencies: ["SwiftUIWebCore", .product(name: "UIKitWebCore", package: "UIKitWeb")],
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
        // Compiler plugin: `#Preview` expands to nothing, so preview blocks in app sources compile.
        .macro(
            name: "SwiftUIWebMacros",
            dependencies: [
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
            ],
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
        .target(
            name: "SwiftUIWebCore",
            dependencies: [.product(name: "WebFoundation", package: "WebGraphics"), .product(name: "WebCombine", package: "WebGraphics"), .product(name: "WebGraphics", package: "WebGraphics")],
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
        .target(
            name: "SwiftUIWebHeadless",
            dependencies: ["SwiftUIWebCore", .product(name: "WebGraphicsHeadless", package: "WebGraphics")],
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
        .target(
            name: "SwiftUIWebTestSupport",
            dependencies: ["SwiftUIWebCore", "SwiftUIWebHeadless"],
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
        // The native macOS host: the runtime in the substrate's AppKit host (decisions 0012, 0014).
        // Its sources are `#if canImport(AppKit)`, so the target is empty elsewhere.
        .target(
            name: "SwiftUIWebNative",
            dependencies: ["SwiftUIWebCore", .product(name: "WebGraphicsNative", package: "WebGraphics")],
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
        // The browser host: the runtime in the substrate's canvas host (decisions 0007, 0014).
        .target(
            name: "SwiftUIWebCanvas",
            dependencies: [
                "SwiftUIWebCore",
                // The audio, notification and data stand-ins' host hooks (decision 0021): Web
                // Audio, the microphone, the Notification API, localStorage for SwiftData's
                // stores. Speech installs nothing (pf-speech).
                "AVFoundation", "UserNotifications", "SwiftData",
                .product(name: "WebGraphicsCanvas", package: "WebGraphics"),
                .product(name: "JavaScriptEventLoop", package: "JavaScriptKit", condition: .when(platforms: [.wasi])),
            ],
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
        // FixtureKit is the SwiftUIWeb twin of Harness/Sources/FixtureKit; SwiftUIWebFixtures compiles
        // the fixture sources shared with Harness/ (which builds them against Apple's SwiftUI).
        .target(
            name: "FixtureKit",
            dependencies: ["SwiftUI"],
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
        .target(
            name: "SwiftUIWebFixtures",
            dependencies: ["SwiftUI", "FixtureKit", "Charts", "MapKit", "AVKit", "WebKit"],
            path: "Fixtures/Sources",
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
        // The Linux and wasm Testing modules declare a `_Testing_UIKit` cross-import overlay that
        // does not exist on those platforms; with `import SwiftUI` re-exporting UIKitWeb's `UIKit`, the tests would try
        // to load it. Disable overlay lookup for those test builds.
        .testTarget(
            name: "CoreRuntimeTests",
            dependencies: ["SwiftUI", "Charts", "MapKit", "AVKit", "Speech", "SwiftData", "UserNotifications", "WebKit", "SwiftUIWebTestSupport", "FixtureKit", "SwiftUIWebFixtures", .product(name: "WebFoundation", package: "WebGraphics")],
            swiftSettings: [.treatAllWarnings(as: .error), .unsafeFlags(["-disable-cross-import-overlays"], .when(platforms: [.wasi, .linux]))]
        ),
        .testTarget(
            name: "LayoutFidelityTests",
            dependencies: ["SwiftUI", "SwiftUIWebHeadless", "SwiftUIWebTestSupport", "FixtureKit", "SwiftUIWebFixtures"],
            swiftSettings: [.treatAllWarnings(as: .error), .unsafeFlags(["-disable-cross-import-overlays"], .when(platforms: [.wasi, .linux]))]
        ),
        // Tier C: the native painter against Apple's goldens (macOS only; empty elsewhere).
        .testTarget(
            name: "NativeFidelityTests",
            dependencies: ["SwiftUI", "SwiftUIWebNative", "SwiftUIWebHeadless", "FixtureKit", "SwiftUIWebFixtures"],
            swiftSettings: [.treatAllWarnings(as: .error), .unsafeFlags(["-disable-cross-import-overlays"], .when(platforms: [.wasi, .linux]))]
        ),
        .testTarget(
            name: "BrowserTests",
            dependencies: ["SwiftUI", "SwiftUIWebCanvas", "SwiftUIWebTestSupport"],
            swiftSettings: [.treatAllWarnings(as: .error), .unsafeFlags(["-disable-cross-import-overlays"], .when(platforms: [.wasi, .linux]))]
        ),
    ],
    swiftLanguageModes: [.v6]
)
