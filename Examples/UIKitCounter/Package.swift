// swift-tools-version: 6.1
import PackageDescription

// A UIKit counter that depends on UIKitWeb alone (decision 0014): `scripts/build-wasm.sh
// Examples/UIKitCounter`, or `swift run UIKitCounter` on macOS.
let package = Package(
    name: "UIKitCounter",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "UIKitWeb", path: "../../Packages/UIKitWeb"),
        // Direct dependency so the PackageToJS command plugin (`swift package js`) is available here.
        .package(url: "https://github.com/swiftwasm/JavaScriptKit.git", from: "0.49.0"),
    ],
    targets: [
        .executableTarget(
            name: "UIKitCounter",
            dependencies: [
                .product(name: "UIKit", package: "UIKitWeb"),
            ],
            // wasm-ld's default 64 KB shadow stack overflows on deep view trees; give the app 4 MB.
            linkerSettings: [.unsafeFlags(["-Xlinker", "-z", "-Xlinker", "stack-size=4194304"], .when(platforms: [.wasi]))]
        ),
    ]
)
