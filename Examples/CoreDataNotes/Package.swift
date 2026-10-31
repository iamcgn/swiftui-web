// swift-tools-version: 6.2
// A Core Data app whose files import only SwiftUI or only Foundation, as on iOS (decision 0024):
// the `CoreData` trait on SwiftUIWeb and Shadows is what makes `import SwiftUI` bring
// `@FetchRequest` and `import Foundation` bring `NSPredicate`. Tools/Traits/traits.py finds that
// an app needs it (scripts/build-wasm.sh warns when the manifest leaves it off).
import PackageDescription

let package = Package(
    name: "CoreDataNotes",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "SwiftUIWeb", path: "../..", traits: ["CoreData"]),
        .package(name: "Shadows", path: "../../Packages/Shadows", traits: ["CoreData"]),
        .package(name: "UIKitWeb", path: "../../Packages/UIKitWeb"),
        // Direct dependency so the PackageToJS command plugin (`swift package js`) is available here.
        .package(url: "https://github.com/swiftwasm/JavaScriptKit.git", from: "0.49.0"),
    ],
    targets: [
        .executableTarget(
            name: "CoreDataNotes",
            dependencies: [
                .product(name: "SwiftUI", package: "SwiftUIWeb"),
                .product(name: "SwiftUIWebCanvas", package: "SwiftUIWeb"),
                // The classes the CoreDataModel plugin generates import it, as Xcode's import CoreData.
                .product(name: "WebCoreData", package: "SwiftUIWeb"),
                .product(name: "UIKit", package: "UIKitWeb"),
                .product(name: "Foundation", package: "Shadows", condition: .when(platforms: [.wasi])),
                .product(name: "Combine", package: "Shadows", condition: .when(platforms: [.wasi])),
                .product(name: "CoreData", package: "Shadows", condition: .when(platforms: [.wasi])),
            ],
            exclude: ["Notes.xcdatamodeld"],
            // wasm-ld's default 64 KB shadow stack overflows on deep view trees; give the app 4 MB.
            linkerSettings: [.unsafeFlags(["-Xlinker", "-z", "-Xlinker", "stack-size=4194304"], .when(platforms: [.wasi]))],
            plugins: [.plugin(name: "CoreDataModel", package: "SwiftUIWeb")]
        ),
    ]
)
