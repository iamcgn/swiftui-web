// swift-tools-version: 6.2
// Modules named after Apple's, for wasm only (decision 0021): `Combine` re-exports WebCombine
// and `Foundation` re-exports WebFoundation (decision 0017) with the names Apple's Foundation
// re-exports, so an app file's `import Foundation` or `import Combine` means what it does on
// iOS. An app's Package.swift adds them next to the SwiftUI product:
//     .package(name: "Shadows", path: "<SwiftUIWeb>/Packages/Shadows"),
//     .product(name: "Foundation", package: "Shadows", condition: .when(platforms: [.wasi])),
//     .product(name: "Combine", package: "Shadows", condition: .when(platforms: [.wasi])),
// `os` and `OSLog` (`Logger` over the console), `CoreGraphics` (the geometry types) and
// `UniformTypeIdentifiers` (`UTType`) are here for the same reason as the rest, and so is
// `CoreData` (WebCoreData; the app's models go through SwiftUIWeb's CoreDataModel plugin). With
// `CoreGraphics` importable on wasm, SwiftUIWeb's own sources test for Apple's with
// `canImport(CoreGraphics) && !os(WASI)`.
// `Security` (the keychain item functions over a host store) and `SafariServices`
// (`SFSafariViewController` over `WKWebView`) live here for the same reason (decision 0021, the
// Ember app): a root-package module named `Security` would shadow Apple's for every macOS
// build, the testing library's included. Their sources are `#if os(WASI)` too.
// A module named `Foundation` must never be built on macOS or Linux (it would shadow the
// system module for every target compiled after it; the sources are `#if os(WASI)`), and must
// stay out of SwiftUIWeb's own test builds: SwiftPM's wasm test discovery imports XCTest, whose
// binary module wants the SDK's Foundation.
import PackageDescription

let package = Package(
    name: "Shadows",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "Foundation", targets: ["Foundation"]),
        .library(name: "Combine", targets: ["Combine"]),
        .library(name: "Security", targets: ["Security"]),
        .library(name: "SafariServices", targets: ["SafariServices"]),
        .library(name: "os", targets: ["os"]),
        .library(name: "OSLog", targets: ["OSLog"]),
        .library(name: "CoreGraphics", targets: ["CoreGraphics"]),
        .library(name: "UniformTypeIdentifiers", targets: ["UniformTypeIdentifiers"]),
        .library(name: "CoreData", targets: ["CoreData"]),
    ],
    // `CoreData` (decision 0024): `import Foundation` re-exports WebCoreData too, as Apple's
    // declares `NSPredicate`, `NSSortDescriptor` and `NSExpression`. Enable it with SwiftUIWeb's.
    // `DecimalFormatting`: `import Foundation` re-exports WebDecimalFormats (`Decimal.FormatStyle`),
    // for an app that names Decimal (Tools/Traits/traits.py).
    traits: [
        .trait(name: "CoreData", description: "`import Foundation` re-exports WebCoreData (`NSPredicate`, `NSSortDescriptor`)."),
        .trait(name: "DecimalFormatting", description: "`import Foundation` re-exports WebDecimalFormats (`Decimal.formatted`, `Decimal.FormatStyle`)."),
    ],
    dependencies: [
        .package(path: "../WebGraphics"),
        .package(name: "SwiftUIWeb", path: "../.."),
    ],
    targets: [
        .target(
            name: "Foundation",
            dependencies: [
                .product(name: "WebFoundation", package: "WebGraphics"), .product(name: "WebFoundationFormats", package: "WebGraphics"), "Combine", "CoreGraphics",
                .product(name: "WebCoreData", package: "SwiftUIWeb", condition: .when(traits: ["CoreData"])),
                .product(name: "WebDecimalFormats", package: "WebGraphics", condition: .when(traits: ["DecimalFormatting"])),
            ],
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
        .target(
            name: "Combine",
            dependencies: [.product(name: "WebCombine", package: "WebGraphics")],
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
        .target(
            name: "Security",
            dependencies: [.product(name: "WebFoundation", package: "WebGraphics")],
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
        .target(
            name: "SafariServices",
            dependencies: [.product(name: "SwiftUI", package: "SwiftUIWeb"), .product(name: "WebKit", package: "SwiftUIWeb")],
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
        .target(
            name: "os",
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
        .target(
            name: "OSLog",
            dependencies: ["os"],
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
        .target(
            name: "CoreGraphics",
            dependencies: [.product(name: "WebGraphics", package: "WebGraphics")],
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
        .target(
            name: "UniformTypeIdentifiers",
            dependencies: [.product(name: "WebGraphics", package: "WebGraphics")],
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
        .target(
            name: "CoreData",
            dependencies: [.product(name: "WebCoreData", package: "SwiftUIWeb")],
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
    ]
)
