// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "Counter",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "../.."),
    ],
    targets: [
        .executableTarget(
            name: "Counter",
            dependencies: [
                .product(name: "SwiftUI", package: "SwiftUIWeb"),
                .product(name: "SwiftUIWebCanvas", package: "SwiftUIWeb"),
            ]
        ),
    ]
)
