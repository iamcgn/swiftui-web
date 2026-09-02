// swift-tools-version: 6.1
import PackageDescription

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
    ],
    dependencies: [
        .package(url: "https://github.com/swiftwasm/JavaScriptKit.git", from: "0.49.0"),
    ],
    targets: [
        .target(
            name: "SwiftUI",
            dependencies: ["SwiftUIWebCore"]
        ),
        .target(
            name: "SwiftUIWebCore"
        ),
        .target(
            name: "SwiftUIWebHeadless",
            dependencies: ["SwiftUIWebCore"]
        ),
        .target(
            name: "SwiftUIWebTestSupport",
            dependencies: ["SwiftUIWebCore", "SwiftUIWebHeadless"]
        ),
        .target(
            name: "SwiftUIWebCanvas",
            dependencies: [
                "SwiftUIWebCore",
                .product(name: "JavaScriptKit", package: "JavaScriptKit", condition: .when(platforms: [.wasi])),
                .product(name: "JavaScriptEventLoop", package: "JavaScriptKit", condition: .when(platforms: [.wasi])),
            ]
        ),
        // FixtureKit is the SwiftUIWeb twin of Harness/Sources/FixtureKit; SwiftUIWebFixtures compiles
        // the fixture sources shared with Harness/ (which builds them against Apple's SwiftUI).
        .target(
            name: "FixtureKit",
            dependencies: ["SwiftUI"]
        ),
        .target(
            name: "SwiftUIWebFixtures",
            dependencies: ["SwiftUI", "FixtureKit"],
            path: "Fixtures/Sources"
        ),
        .testTarget(
            name: "CoreRuntimeTests",
            dependencies: ["SwiftUI", "SwiftUIWebTestSupport", "FixtureKit", "SwiftUIWebFixtures"]
        ),
        .testTarget(
            name: "LayoutFidelityTests",
            dependencies: ["SwiftUI", "SwiftUIWebHeadless", "SwiftUIWebTestSupport", "FixtureKit", "SwiftUIWebFixtures"]
        ),
        .testTarget(
            name: "BrowserTests",
            dependencies: ["SwiftUI", "SwiftUIWebCanvas", "SwiftUIWebTestSupport"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
