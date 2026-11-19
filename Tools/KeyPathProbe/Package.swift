// swift-tools-version: 6.2
// Scratch probe: does TCA's Binding-to-Store scope pattern form a key path to a main-actor
// subscript under this repo's Binding? Each target is one variant, built separately.
import PackageDescription

let package = Package(
    name: "KeyPathProbe",
    platforms: [.macOS(.v14)],
    dependencies: [.package(path: "../..")],
    targets: [
        .target(name: "Ours5", dependencies: [.product(name: "SwiftUI", package: "swiftui-web")],
                swiftSettings: [.swiftLanguageMode(.v5)]),
        .target(name: "Ours6", dependencies: [.product(name: "SwiftUI", package: "swiftui-web")]),
        .target(name: "Local6"),
        .target(name: "PercOurs", dependencies: [.product(name: "SwiftUI", package: "swiftui-web")],
                swiftSettings: [.swiftLanguageMode(.v5)]),
        .target(name: "TCAOurs", dependencies: ["PercOurs", .product(name: "SwiftUI", package: "swiftui-web")]),
        .target(name: "PercLocal", swiftSettings: [.swiftLanguageMode(.v5)]),
        .target(name: "TCALocal", dependencies: ["PercLocal"]),
    ]
)
