// swift-tools-version: 6.1
// Spike 0.5: Canvas2D painter fed by a flat display list from wasm, one JS call per frame.
import PackageDescription

let package = Package(
    name: "CanvasSpike",
    dependencies: [
        .package(url: "https://github.com/swiftwasm/JavaScriptKit.git", from: "0.49.0"),
    ],
    targets: [
        .executableTarget(
            name: "CanvasSpike",
            dependencies: [
                .product(name: "JavaScriptKit", package: "JavaScriptKit"),
                .product(name: "JavaScriptEventLoop", package: "JavaScriptKit"),
            ]
        ),
    ]
)
