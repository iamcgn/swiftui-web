// swift-tools-version: 5.10
// Golden generator. Builds with the Apple toolchain against Apple's real SwiftUI.
// Must never depend on the root package, or `import SwiftUI` would resolve to SwiftUIWeb.
import PackageDescription

let package = Package(
    name: "Harness",
    platforms: [.macOS("15.0"), .macCatalyst("18.0"), .iOS("26.0")],
    targets: [
        .target(name: "FixtureKit"),                                     // real-SwiftUI implementation of the fixture API
        .target(name: "Fixtures", dependencies: ["FixtureKit"]),         // symlink -> ../../Fixtures/Sources
        .target(name: "GoldenKit", dependencies: ["FixtureKit", "Fixtures"]),   // generation shared by the hosts below
        .executableTarget(name: "GoldenGen", dependencies: ["GoldenKit", "FixtureKit", "Fixtures"]),          // AppKit window: macOS goldens
        .executableTarget(name: "GoldenGenIOS", dependencies: ["GoldenKit", "FixtureKit", "Fixtures"]), // UIKit window on Mac Catalyst: iOS goldens (scripts/gen-goldens-ios.sh)
        // UIKitWeb's fidelity loop (decision 0014): the UIKit fixtures against Apple's UIKit on Mac Catalyst.
        // The sources are empty where UIKit cannot be imported (the plain macOS build).
        .target(name: "UIKitFixtureKit"),                                        // real-UIKit implementation of the UIKit fixture API
        .target(name: "UIKitFixtures", dependencies: ["UIKitFixtureKit"]),       // symlink -> ../../Fixtures/UIKit
        .executableTarget(name: "UIKitGoldenGen", dependencies: ["UIKitFixtureKit", "UIKitFixtures"]), // scripts/gen-goldens-uikit.sh
    ]
)
