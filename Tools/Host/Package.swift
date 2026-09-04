// swift-tools-version: 6.1
import PackageDescription

// swiftui-host: a macOS executable that serves a built wasm bundle over loopback HTTP and loads
// it in a WKWebView window (Docs/ROADMAP.md, Phase 4). Built with the Apple toolchain like the
// harness (`/usr/bin/swift run swiftui-host <package-dir>`); it never depends on the root package.
let package = Package(
    name: "SwiftUIHost",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "swiftui-host", targets: ["SwiftUIHost"]),
    ],
    targets: [
        .executableTarget(
            name: "SwiftUIHost",
            path: "Sources/SwiftUIHost",
            swiftSettings: [.unsafeFlags(["-warnings-as-errors"])]
        ),
    ]
)
