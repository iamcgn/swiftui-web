// swift-tools-version: 6.2
import PackageDescription

// UIKitWeb: an open-source UIKit reimplementation that runs unmodified UIKit source in the
// browser (WebAssembly + Canvas) and natively, on the WebGraphics substrate it shares with
// SwiftUIWeb (decision 0014). It works on its own: a UIKit app depends on this package alone.
//
// Module layout:
//   UIKit          thin re-export so apps can `import UIKit` unchanged; `UIApplicationDelegate.main()`
//   UIKitSubmodules  the clang module map that gives `import UIKit.UIImage` its submodules (wasm)
//   UserNotifications  the notification centre over the browser's Notification API, which UIKit
//                  re-exports as Apple's does (UserNotificationsHost: its host hook)
//   UIKitWebCore   the view and layer trees, responders and touches, controls, view controllers,
//                  the window, screen and application, and the scene the substrate hosts drive
//   UIKitFixtureKit, UIKitFixtures   the fidelity loop's fixture API and fixtures (tests only)
let package = Package(
    name: "UIKitWeb",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "UIKit", targets: ["UIKit"]),
        .library(name: "UIKitWebCore", targets: ["UIKitWebCore"]),
        // UserNotifications (decision 0021), here because Apple's UIKit re-exports it: an app
        // delegate names `UNUserNotificationCenter` with only `import UIKit` (Harbour's). Its host
        // hook is a module of its own, so the browser host installs it without linking the
        // framework into an app that posts no notifications (decision 0006).
        .library(name: "UserNotifications", targets: ["UserNotifications"]),
        .library(name: "UserNotificationsHost", targets: ["UserNotificationsHost"]),
        // The fidelity loop's pieces, for the fixture gallery (Examples/Gallery).
        .library(name: "UIKitFixtureKit", targets: ["UIKitFixtureKit"]),
        .library(name: "UIKitFixtures", targets: ["UIKitFixtures"]),
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
                "UserNotifications",
                .product(name: "WebFoundation", package: "WebGraphics"),
                .product(name: "WebGraphicsCanvas", package: "WebGraphics"),
                .product(name: "WebGraphicsNative", package: "WebGraphics"),
                // Apple's UIKit brings ImageIO's image sources with it (Nuke and Kingfisher read
                // `CGImageSource` with only `import UIKit`).
                .product(name: "WebImageIO", package: "WebGraphics", condition: .when(platforms: [.wasi])),
                // Apple's UIKit brings Core Image with it (CoreImageBridges.swift).
                .product(name: "WebCoreImage", package: "WebGraphics"),
                .product(name: "JavaScriptEventLoop", package: "JavaScriptKit", condition: .when(platforms: [.wasi])),
                // `import UIKit.UIImage` and the other per-header submodules resolve through this
                // clang module of the same name (wasm only: elsewhere the API is reached as `UIKit`).
                .target(name: "UIKitSubmodules", condition: .when(platforms: [.wasi])),
            ],
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
        .target(name: "UIKitSubmodules"),
        .target(name: "UserNotificationsHost", swiftSettings: [.treatAllWarnings(as: .error)]),
        .target(name: "UserNotifications", dependencies: ["UserNotificationsHost", .product(name: "WebFoundation", package: "WebGraphics")],
                swiftSettings: [.treatAllWarnings(as: .error)]),
        // UIKit's option sets as C declares them, which UIKitWebCore imports with the Objective-C
        // runtime only, so `@objc` delegate methods can take and return them.
        .systemLibrary(name: "UIKitWebCTypes"),
        .target(
            name: "UIKitWebCore",
            dependencies: [.product(name: "WebFoundation", package: "WebGraphics"), .product(name: "WebGraphics", package: "WebGraphics"),
                           "UIKitWebCTypes"],
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
        // The fidelity loop (decision 0014): the UIKit fixture API, the fixtures themselves (a symlink
        // to Fixtures/UIKit at the repository root, shared with the Catalyst harness), and the tests
        // that hold UIKitWeb's layout to the goldens Apple's UIKit produced.
        .target(
            name: "UIKitFixtureKit",
            dependencies: ["UIKit"],
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
        .target(
            name: "UIKitFixtures",
            dependencies: ["UIKit", "UIKitFixtureKit"],
            path: "Fixtures",
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
        .testTarget(
            name: "UIKitWebTests",
            dependencies: ["UIKit", "UIKitFixtureKit", "UIKitFixtures",
                           .product(name: "WebFoundation", package: "WebGraphics"),
                           .product(name: "WebGraphicsHeadless", package: "WebGraphics"),
                           .product(name: "WebGraphicsNative", package: "WebGraphics")],
            // Testing declares a UIKit overlay that only ships on Apple platforms.
            swiftSettings: [.treatAllWarnings(as: .error), .unsafeFlags(["-disable-cross-import-overlays"], .when(platforms: [.wasi, .linux]))]
        ),
    ],
    swiftLanguageModes: [.v6]
)
