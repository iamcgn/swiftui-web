// swift-tools-version: 6.1
// An app whose model files import Foundation and Combine, as most do (decision 0021): the two
// product lines after SwiftUI's are what an app package adds for them.
import PackageDescription

let package = Package(
    name: "Launches",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "SwiftUIWeb", path: "../.."),
        .package(name: "Shadows", path: "../../Packages/Shadows"),
        // Direct dependency so the PackageToJS command plugin (`swift package js`) is available here.
        .package(url: "https://github.com/swiftwasm/JavaScriptKit.git", from: "0.49.0"),
    ],
    targets: [
        .executableTarget(
            name: "Launches",
            dependencies: [
                .product(name: "SwiftUI", package: "SwiftUIWeb"),
                .product(name: "SwiftUIWebCanvas", package: "SwiftUIWeb"),
                .product(name: "Foundation", package: "Shadows", condition: .when(platforms: [.wasi])),
                .product(name: "Combine", package: "Shadows", condition: .when(platforms: [.wasi])),
            ],
            // Swift 5 mode, as the apps of decision 0021 build (a nonisolated model captured by a dispatch closure).
            swiftSettings: [.swiftLanguageMode(.v5)],
            // wasm-ld's default 64 KB shadow stack overflows on deep view trees; give the app 4 MB.
            linkerSettings: [.unsafeFlags(["-Xlinker", "-z", "-Xlinker", "stack-size=4194304"], .when(platforms: [.wasi]))]
        ),
    ]
)
