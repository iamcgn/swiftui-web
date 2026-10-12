// swift-tools-version: 6.2
import PackageDescription

// The WebKitGTK host (pf-linux, decision 0018): the Linux counterpart of Tools/Host — a GTK4
// window with a WebKitWebView showing a built wasm bundle served over loopback. Its own
// package because WebKitGTK exists only on Linux (libwebkitgtk-6.0-dev); CI builds it in the
// swift:6.3.3 container.
//
//   swift run gtk-host <package-dir> [--port N] [--path index.html] [--width W] [--height H] [--timeout seconds]
let package = Package(
    name: "WebKitHost",
    products: [
        .executable(name: "gtk-host", targets: ["gtk-host"]),
    ],
    targets: [
        .systemLibrary(
            name: "CGtk",
            pkgConfig: "gtk4",
            providers: [.apt(["libgtk-4-dev"]), .brew(["gtk4"])]
        ),
        .systemLibrary(
            name: "CWebKitGTK",
            pkgConfig: "webkitgtk-6.0",
            providers: [.apt(["libwebkitgtk-6.0-dev"])]
        ),
        .executableTarget(
            name: "gtk-host",
            dependencies: ["CGtk", "CWebKitGTK"],
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
    ],
    swiftLanguageModes: [.v6]
)
