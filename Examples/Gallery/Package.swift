// swift-tools-version: 6.1
import PackageDescription

// Fixture gallery: mounts any fixture by name (`index.html?fixture=layout/spacer`) for the
// browser Tier B job and for eyeballing elements. Build: scripts/build-wasm.sh Examples/Gallery
let package = Package(
    name: "Gallery",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "SwiftUIWeb", path: "../.."),
        // Direct dependency so the PackageToJS command plugin (`swift package js`) is available here.
        .package(url: "https://github.com/swiftwasm/JavaScriptKit.git", from: "0.49.0"),
    ],
    targets: [
        .executableTarget(
            name: "Gallery",
            dependencies: [
                .product(name: "SwiftUI", package: "SwiftUIWeb"),
                .product(name: "SwiftUIWebCanvas", package: "SwiftUIWeb"),
                .product(name: "SwiftUIWebFixtures", package: "SwiftUIWeb"),
                .product(name: "FixtureKit", package: "SwiftUIWeb"),
                .product(name: "JavaScriptKit", package: "JavaScriptKit"),
                .product(name: "JavaScriptEventLoop", package: "JavaScriptKit"),
            ]
        ),
    ]
)
