// swift-tools-version: 6.2
import PackageDescription

// WebGraphics: the graphics substrate SwiftUIWeb and UIKitWeb share (decision 0014): geometry
// (CoreGraphics types on wasm), paths, the display list and its encoder, text measuring and the
// measured font tables, asset catalogs, the value types hosts exchange with a scene (semantics,
// text input, keys), and the hosts themselves over the `HostedScene` protocol. No runtime.
//
// Module layout:
//   WebFoundation        Foundation for the substrate: Foundation itself, or FoundationEssentials
//                        plus the wasm stand-ins for its heaviest value types (decision 0017)
//   WebGraphics          geometry, display list, paths, text engine protocol, HostedScene
//   WebGraphicsCanvas    wasm-only Canvas2D painter, canvas host, semantics overlay, text input
//   WebGraphicsNative    macOS CoreText engine, CoreGraphics painter, AppKit host
//   WebGraphicsHeadless  recorded text metrics and the asset manifest reader for tests
let package = Package(
    name: "WebGraphics",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "WebFoundation", targets: ["WebFoundation"]),
        .library(name: "WebGraphics", targets: ["WebGraphics"]),
        .library(name: "WebGraphicsCanvas", targets: ["WebGraphicsCanvas"]),
        .library(name: "WebGraphicsNative", targets: ["WebGraphicsNative"]),
        .library(name: "WebGraphicsHeadless", targets: ["WebGraphicsHeadless"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftwasm/JavaScriptKit.git", from: "0.49.0"),
    ],
    targets: [
        .target(
            name: "WebFoundation",
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
        .target(
            name: "WebGraphics",
            dependencies: ["WebFoundation"],
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
        .target(
            name: "WebGraphicsCanvas",
            dependencies: [
                "WebFoundation",
                "WebGraphics",
                .product(name: "JavaScriptKit", package: "JavaScriptKit", condition: .when(platforms: [.wasi])),
            ],
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
        // Sources are `#if canImport(AppKit)`, so the target is empty elsewhere.
        .target(
            name: "WebGraphicsNative",
            dependencies: ["WebGraphics", "WebGraphicsHeadless"],
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
        .testTarget(
            name: "WebFoundationTests",
            dependencies: ["WebFoundation"],
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
        .target(
            name: "WebGraphicsHeadless",
            dependencies: ["WebFoundation", "WebGraphics"],
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
    ],
    swiftLanguageModes: [.v6]
)
