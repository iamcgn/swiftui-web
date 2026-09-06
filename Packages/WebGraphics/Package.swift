// swift-tools-version: 6.2
import PackageDescription

// WebGraphics: the graphics substrate SwiftUIWeb and UIKitWeb share (decision 0014): geometry
// (CoreGraphics types on wasm), paths, the display list and its encoder, text measuring and the
// measured font tables, asset catalogs, and the value types hosts exchange with a scene
// (semantics, text input, keys). No dependencies, no runtime.
//
// Module layout:
//   WebGraphics          geometry, display list, paths, text engine protocol, host value types
let package = Package(
    name: "WebGraphics",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "WebGraphics", targets: ["WebGraphics"]),
    ],
    targets: [
        .target(
            name: "WebGraphics",
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
    ],
    swiftLanguageModes: [.v6]
)
