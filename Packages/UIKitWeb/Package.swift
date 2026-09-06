// swift-tools-version: 6.2
import PackageDescription

// UIKitWeb: an open-source UIKit reimplementation that runs unmodified UIKit source in the
// browser (WebAssembly + Canvas) and natively, on the WebGraphics substrate it shares with
// SwiftUIWeb (decision 0014). It works on its own: a UIKit app depends on this package alone.
//
// Module layout:
//   UIKit          thin re-export so apps can `import UIKit` unchanged; `UIApplicationDelegate.main()`
//   UIKitWebCore   the view and layer trees, responders and touches, controls, view controllers,
//                  the window, screen and application, and the scene the substrate hosts drive
let package = Package(
    name: "UIKitWeb",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "UIKit", targets: ["UIKit"]),
        .library(name: "UIKitWebCore", targets: ["UIKitWebCore"]),
    ],
    dependencies: [
        .package(path: "../WebGraphics"),
        .package(url: "https://github.com/swiftwasm/JavaScriptKit.git", from: "0.49.0"),
    ],
    targets: [
        .target(
            name: "UIKit",
            dependencies: [
                "UIKitWebCore",
                .product(name: "WebGraphicsCanvas", package: "WebGraphics"),
                .product(name: "WebGraphicsNative", package: "WebGraphics"),
                .product(name: "JavaScriptEventLoop", package: "JavaScriptKit", condition: .when(platforms: [.wasi])),
            ],
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
        .target(
            name: "UIKitWebCore",
            dependencies: [.product(name: "WebGraphics", package: "WebGraphics")],
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
        .testTarget(
            name: "UIKitWebTests",
            dependencies: ["UIKit", .product(name: "WebGraphicsHeadless", package: "WebGraphics")],
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
    ],
    swiftLanguageModes: [.v6]
)
