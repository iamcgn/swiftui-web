// swift-tools-version: 6.2
// Modules named after Apple's, for wasm only (decision 0021): `Combine` re-exports WebCombine
// and `Foundation` re-exports WebFoundation (decision 0017) with the names Apple's Foundation
// re-exports, so an app file's `import Foundation` or `import Combine` means what it does on
// iOS. An app's Package.swift adds them next to the SwiftUI product:
//     .package(name: "Shadows", path: "<SwiftUIWeb>/Packages/Shadows"),
//     .product(name: "Foundation", package: "Shadows", condition: .when(platforms: [.wasi])),
//     .product(name: "Combine", package: "Shadows", condition: .when(platforms: [.wasi])),
// A module named `Foundation` must never be built on macOS or Linux (it would shadow the
// system module for every target compiled after it; the sources are `#if os(WASI)`), and must
// stay out of SwiftUIWeb's own test builds: SwiftPM's wasm test discovery imports XCTest, whose
// binary module wants the SDK's Foundation.
import PackageDescription

let package = Package(
    name: "Shadows",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "Foundation", targets: ["Foundation"]),
        .library(name: "Combine", targets: ["Combine"]),
    ],
    dependencies: [
        .package(path: "../WebGraphics"),
    ],
    targets: [
        .target(
            name: "Foundation",
            dependencies: [.product(name: "WebFoundation", package: "WebGraphics"), "Combine"],
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
        .target(
            name: "Combine",
            dependencies: [.product(name: "WebCombine", package: "WebGraphics")],
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
    ]
)
