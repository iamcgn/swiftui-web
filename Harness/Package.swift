// swift-tools-version: 5.10
// Golden generator. Builds with the Apple toolchain against Apple's real SwiftUI.
// Must never depend on the root package, or `import SwiftUI` would resolve to SwiftUIWeb.
import PackageDescription

let package = Package(
    name: "Harness",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "FixtureKit"),                                     // real-SwiftUI implementation of the fixture API
        .target(name: "Fixtures", dependencies: ["FixtureKit"]),         // symlink -> ../../Fixtures/Sources
        .executableTarget(name: "GoldenGen", dependencies: ["FixtureKit", "Fixtures"]),
    ]
)
