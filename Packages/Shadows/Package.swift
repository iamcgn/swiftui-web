// swift-tools-version: 6.2
// Modules named after Apple's, for wasm only (decision 0021): `Foundation` re-exports
// WebFoundation (decision 0017) with the names Apple's Foundation re-exports, so an app file's
// `import Foundation` means the same thing it does on iOS. A module named `Foundation` must
// never be built on macOS or Linux: it would shadow the system module for every target compiled
// after it, so the root package links these products only `.when(platforms: [.wasi])` and
// nothing runs `swift build` in this package natively (their sources are `#if os(WASI)`).
import PackageDescription

let package = Package(
    name: "Shadows",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "Foundation", targets: ["Foundation"]),
    ],
    dependencies: [
        .package(path: "../WebGraphics"),
    ],
    targets: [
        .target(
            name: "Foundation",
            dependencies: [.product(name: "WebFoundation", package: "WebGraphics")],
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
    ]
)
