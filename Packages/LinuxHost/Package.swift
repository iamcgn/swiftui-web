// swift-tools-version: 6.2
import PackageDescription

// The Linux host (pf-linux, decision 0018): a GTK4 window whose drawing area paints the scene
// with the Cairo painter and feeds it pointer, wheel and key events. Its own package so the
// substrate and the runtime build without GTK; CI builds it in the swift:6.3.3 container with
// the distribution's libgtk-4-dev and libcairo2-dev (`brew install gtk4 cairo` on a Mac).
//
//   swift run gtk-counter            the Counter example in a GTK window
// (the WebKitGTK bundle host is Packages/WebKitHost: `swift run gtk-host <package-dir>`)
let package = Package(
    name: "LinuxHost",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "WebGraphicsGTK", targets: ["WebGraphicsGTK"]),
        .library(name: "SwiftUIWebGTK", targets: ["SwiftUIWebGTK"]),
        .executable(name: "gtk-counter", targets: ["gtk-counter"]),
    ],
    dependencies: [
        .package(path: "../WebGraphics"),
        .package(name: "SwiftUIWeb", path: "../.."),
    ],
    targets: [
        .systemLibrary(
            name: "CGtk",
            pkgConfig: "gtk4",
            providers: [.apt(["libgtk-4-dev"]), .brew(["gtk4"])]
        ),
        // The GTK window over any `HostedScene`.
        .target(
            name: "WebGraphicsGTK",
            dependencies: [
                "CGtk",
                .product(name: "WebGraphics", package: "WebGraphics"),
                .product(name: "WebGraphicsCairo", package: "WebGraphics"),
            ],
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
        // The SwiftUI runtime in that window.
        .target(
            name: "SwiftUIWebGTK",
            dependencies: [
                "WebGraphicsGTK",
                .product(name: "SwiftUI", package: "SwiftUIWeb"),
            ],
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
        .testTarget(
            name: "SwiftUIWebGTKTests",
            dependencies: ["SwiftUIWebGTK", .product(name: "WebGraphicsCairo", package: "WebGraphics")],
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
        .executableTarget(
            name: "gtk-counter",
            dependencies: ["SwiftUIWebGTK", .product(name: "SwiftUI", package: "SwiftUIWeb")],
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
    ],
    swiftLanguageModes: [.v6]
)
