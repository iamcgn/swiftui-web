// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "Counter",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "SwiftUIWeb", path: "../.."),
        // Direct dependency so the PackageToJS command plugin (`swift package js`) is available here.
        .package(url: "https://github.com/swiftwasm/JavaScriptKit.git", from: "0.49.0"),
    ],
    targets: [
        .executableTarget(
            name: "Counter",
            dependencies: [
                .product(name: "SwiftUI", package: "SwiftUIWeb"),
                .product(name: "SwiftUIWebCanvas", package: "SwiftUIWeb"),
            ],
            // wasm-ld's default 64 KB shadow stack overflows on deep view trees; give the app 4 MB.
            linkerSettings: [.unsafeFlags(["-Xlinker", "-z", "-Xlinker", "stack-size=4194304"], .when(platforms: [.wasi]))]
        ),
    ]
)
