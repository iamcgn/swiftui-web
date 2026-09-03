// swift-tools-version: 6.2
import PackageDescription
import CompilerPluginSupport

// SwiftUIWeb: an open-source SwiftUI reimplementation that runs unmodified SwiftUI
// source in the browser (WebAssembly + Canvas) and, later, natively.
//
// Module layout (see Docs/ARCHITECTURE.md):
//   SwiftUI              thin re-export so apps can `import SwiftUI` unchanged
//   SwiftUIWebCore       API + runtime + layout + text + display list
//   SwiftUIWebHeadless   display-list recorder + recorded text metrics for native tests
//   SwiftUIWebCanvas     wasm-only Canvas2D painter, semantics overlay, text input host
//   SwiftUIWebTestSupport fixture registry, golden codecs, comparators

let package = Package(
    name: "SwiftUIWeb",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SwiftUI", targets: ["SwiftUI"]),
        .library(name: "SwiftUIWebCanvas", targets: ["SwiftUIWebCanvas"]),
        .library(name: "SwiftUIWebHeadless", targets: ["SwiftUIWebHeadless"]),
        .library(name: "FixtureKit", targets: ["FixtureKit"]),
        .library(name: "SwiftUIWebFixtures", targets: ["SwiftUIWebFixtures"]),
    ],
    dependencies: [
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
                .target(name: "SwiftUIWebCanvas", condition: .when(platforms: [.wasi])),
            ],
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
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
        .target(
            name: "SwiftUIWebHeadless",
            dependencies: ["SwiftUIWebCore"],
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
        .target(
            name: "SwiftUIWebTestSupport",
            dependencies: ["SwiftUIWebCore", "SwiftUIWebHeadless"],
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
        .target(
            name: "SwiftUIWebCanvas",
            dependencies: [
                "SwiftUIWebCore",
                .product(name: "JavaScriptKit", package: "JavaScriptKit", condition: .when(platforms: [.wasi])),
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
            dependencies: ["SwiftUI", "FixtureKit"],
            path: "Fixtures/Sources",
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
        .testTarget(
            name: "CoreRuntimeTests",
            dependencies: ["SwiftUI", "SwiftUIWebTestSupport", "FixtureKit", "SwiftUIWebFixtures"],
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
        .testTarget(
            name: "LayoutFidelityTests",
            dependencies: ["SwiftUI", "SwiftUIWebHeadless", "SwiftUIWebTestSupport", "FixtureKit", "SwiftUIWebFixtures"],
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
        .testTarget(
            name: "BrowserTests",
            dependencies: ["SwiftUI", "SwiftUIWebCanvas", "SwiftUIWebTestSupport"],
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
    ],
    swiftLanguageModes: [.v6]
)
