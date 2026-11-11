// swift-tools-version: 6.1
// The apps of decision 0021, built from their upstream sources exactly as pinned in
// `Apps/upstream/*` (git submodules; `scripts/check-apps.sh` verifies the pins and that no
// upstream file differs). This manifest is the only thing that is not upstream's: it names each
// app's targets, where their sources are, and the SwiftUIWeb products they link in place of
// Apple's frameworks. (An app listed in `ios-conditions.txt` builds from a generated copy of
// its upstream tree in which `os(iOS)` reads as true, decision 0025.) Every Swift file of each
// app is compiled; `exclude:` lists only the non-Swift files Xcode would process (plists,
// storyboards, entitlements), `resources:` mirrors upstream's own manifests. The mapping is tabulated in `Apps/README.md`.
import PackageDescription

let shadows: [Target.Dependency] = [
    .product(name: "Foundation", package: "Shadows", condition: .when(platforms: [.wasi])),
    .product(name: "Combine", package: "Shadows", condition: .when(platforms: [.wasi])),
]
let swiftUI: [Target.Dependency] = [.product(name: "SwiftUI", package: "SwiftUIWeb")] + shadows
let uiKit: Target.Dependency = .product(name: "UIKit", package: "UIKitWeb")
let host: [Target.Dependency] = [
    .product(name: "SwiftUIWebCanvas", package: "SwiftUIWeb", condition: .when(platforms: [.wasi])),
    .product(name: "SwiftUIWebNative", package: "SwiftUIWeb", condition: .when(platforms: [.macOS])),
]
// wasm-ld's default 64 KB shadow stack overflows on deep view trees; give an app 4 MB.
let stack: [LinkerSetting] = [.unsafeFlags(["-Xlinker", "-z", "-Xlinker", "stack-size=4194304"], .when(platforms: [.wasi]))]

let package = Package(
    name: "Apps",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "SwiftUI2048", targets: ["SwiftUI2048"]),
        .executable(name: "Scrumdinger", targets: ["Scrumdinger"]),
        .executable(name: "Ember", targets: ["Ember"]),
        .executable(name: "ChartsExamples", targets: ["ChartsExamples"]),
        .executable(name: "Buttoncraft", targets: ["Buttoncraft"]),
        .executable(name: "Pompaddo", targets: ["Pompaddo"]),
        .executable(name: "SimpleScores", targets: ["SimpleScores"]),
        .executable(name: "EasyCrypto", targets: ["EasyCrypto"]),
    ],
    dependencies: [
        .package(name: "SwiftUIWeb", path: "..", traits: ["FoundationFormats", "DecimalFormatting"]),
        .package(name: "Shadows", path: "../Packages/Shadows", traits: ["DecimalFormatting"]),
        .package(name: "UIKitWeb", path: "../Packages/UIKitWeb"),
        // Direct dependency so the PackageToJS command plugin (`swift package js`) is available here.
        .package(url: "https://github.com/swiftwasm/JavaScriptKit.git", from: "0.49.0"),
    ],
    targets: [
        // MARK: unixzii/SwiftUI-2048 — one Xcode target (SWIFT_VERSION 5.0), a UIKit app delegate
        // hosting the SwiftUI game.
        .executableTarget(
            name: "SwiftUI2048",
            dependencies: swiftUI + [uiKit] + host,
            path: "upstream/SwiftUI-2048/SwiftUI2048",
            exclude: ["Info.plist", "Base.lproj", "MainMenu.xib", "SwiftUI2048.entitlements", "Preview Content"],
            resources: [.process("Assets.xcassets")],
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: stack
        ),

        // MARK: Sedlacek-Solutions/Scrumdinger — the app target plus the targets of its four
        // local packages (Models, Services, ViewComponents, Library; tools 6.0, Swift 6 mode),
        // one wrapper target per upstream target with upstream's dependencies and resources.
        .executableTarget(
            name: "Scrumdinger",
            dependencies: swiftUI + host + ["Configuration", "Scrum"],
            path: "upstream/Scrumdinger/Scrumdinger/App",
            linkerSettings: stack
        ),
        // Models/Package.swift
        .target(name: "Protocols", dependencies: swiftUI, path: "upstream/Scrumdinger/Models/Sources/Protocols"),
        .target(name: "Enumerations", dependencies: swiftUI + ["Protocols"], path: "upstream/Scrumdinger/Models/Sources/Enumerations"),
        .target(name: "Models", dependencies: swiftUI + ["Enumerations"], path: "upstream/Scrumdinger/Models/Sources/Models"),
        .target(name: "Extensions", dependencies: swiftUI + ["Models"], path: "upstream/Scrumdinger/Models/Sources/Extensions"),
        // Services/Package.swift
        .target(
            name: "AudioService",
            dependencies: swiftUI + [.product(name: "AVFoundation", package: "SwiftUIWeb")],
            path: "upstream/Scrumdinger/Services/Sources/AudioService",
            resources: [.process("Resources")]
        ),
        .target(name: "FileService", dependencies: swiftUI, path: "upstream/Scrumdinger/Services/Sources/FileService"),
        .target(
            name: "SpeechService",
            dependencies: swiftUI + [.product(name: "AVFoundation", package: "SwiftUIWeb"), .product(name: "Speech", package: "SwiftUIWeb")],
            path: "upstream/Scrumdinger/Services/Sources/SpeechService"
        ),
        // ViewComponents/Package.swift
        .target(name: "ViewComponents", dependencies: swiftUI, path: "upstream/Scrumdinger/ViewComponents/Sources/ViewComponents"),
        // Library/Package.swift (the `Models` and `Services` products are their packages' targets)
        .target(
            name: "Configuration",
            dependencies: swiftUI + ["Protocols", "Enumerations", "Models", "Extensions", "AudioService", "FileService", "SpeechService"],
            path: "upstream/Scrumdinger/Library/Sources/Configuration"
        ),
        .target(
            name: "Resources",
            dependencies: swiftUI + ["Protocols", "Enumerations", "Models", "Extensions", "ViewComponents"],
            path: "upstream/Scrumdinger/Library/Sources/Resources",
            resources: [.process("Media.xcassets")]
        ),
        .target(
            name: "Scrum",
            dependencies: swiftUI + ["Resources", "Protocols", "Enumerations", "Models", "Extensions", "AudioService", "FileService", "SpeechService", "ViewComponents"],
            path: "upstream/Scrumdinger/Library/Sources/Scrum"
        ),

        // MARK: DatanoiseTV/ember-hackernews — one XcodeGen target (project.yml: `Sources` and
        // `Resources`, SWIFT_VERSION 5.0, iOS 18), the repository root as the target path so
        // both folders are its; everything else at the root (the Skip port `EmberSkip`, `Tools`,
        // `docs`, the project and text files) excluded, and of `Resources` the files Xcode
        // processes through other phases (the plist, the privacy manifest).
        .executableTarget(
            name: "Ember",
            dependencies: swiftUI + [uiKit] + host + [
                .product(name: "WebKit", package: "SwiftUIWeb"),
                .product(name: "SafariServices", package: "Shadows", condition: .when(platforms: [.wasi])),
                .product(name: "Security", package: "Shadows", condition: .when(platforms: [.wasi])),
            ],
            path: "upstream/ember-hackernews",
            exclude: ["EmberSkip", "Tools", "docs", "project.yml", "README.md", "CHANGELOG.md", "LICENSE",
                      "Resources/Info.plist", "Resources/PrivacyInfo.xcprivacy"],
            sources: ["Sources"],
            resources: [.process("Resources/Assets.xcassets"), .process("Resources/Fonts")],
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: stack
        ),

        // MARK: jordibruin/Swift-Charts-Examples — one Xcode target (SWIFT_VERSION 5.7, iOS 16):
        // the app folder as the target path; the entitlements and the preview assets are
        // Xcode's, the asset catalog the app's resources.
        .executableTarget(
            name: "ChartsExamples",
            dependencies: swiftUI + [uiKit] + host + [
                .product(name: "Charts", package: "SwiftUIWeb"),
                .product(name: "AVFoundation", package: "SwiftUIWeb"),
            ],
            path: "upstream/Swift-Charts-Examples/Swift Charts Examples",
            exclude: ["Swift_Charts_Examples.entitlements", "Preview Content"],
            resources: [.process("Assets.xcassets")],
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: stack
        ),

        // MARK: atrinh0/buttoncraft — one Xcode target (SWIFT_VERSION 5.0, iOS 14): the app
        // folder as the target path; the plist, the launch storyboard and the preview assets
        // are Xcode's, the asset catalog the app's resources.
        .executableTarget(
            name: "Buttoncraft",
            dependencies: swiftUI + [uiKit] + host,
            path: "upstream/buttoncraft/buttoncraft/buttoncraft",
            exclude: ["Info.plist", "Launch Screen.storyboard", "Preview Content"],
            resources: [.process("Assets.xcassets")],
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: stack
        ),
        // MARK: twostraws/simple-swiftui — the SimpleScores Xcode target (SWIFT_VERSION 5.0, iOS
        // 15.2): its app folder as the target path, the asset catalog (the players' named colours)
        // its resources. `Preview Content`'s Swift file is compiled (the previews use its
        // example), its asset catalog is Xcode's; the .lproj folders hold the translations, which
        // this target leaves out, as the English strings are the keys themselves.
        .executableTarget(
            name: "SimpleScores",
            dependencies: swiftUI + host,
            path: "upstream/simple-swiftui/SimpleScores/SimpleScores",
            exclude: ["Preview Content/Preview Assets.xcassets", "Resources/de.lproj", "Resources/en.lproj", "Resources/es.lproj",
                      "Resources/fr.lproj", "Resources/nl.lproj"],
            resources: [.process("Resources/Assets.xcassets")],
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: stack
        ),
        // MARK: mehrankmlf/EasyCrypto — the EasyCrypto Xcode target (SWIFT_VERSION 5.0, iOS 16): its
        // app folder as the target path, Core Data through the CoreDataModel plugin (its
        // `CoinsDB.xcdatamodeld`, as Xcode generates the model's classes), the asset catalog and the
        // bundled font its resources. `Preview Content` holds only Xcode's preview asset catalog.
        // It sends `#selector(UIResponder.resignFirstResponder)`, so it builds with the
        // Objective-C runtime SDK (decision 0023).
        .executableTarget(
            name: "EasyCrypto",
            dependencies: swiftUI + [uiKit] + host + [
                .product(name: "WebCoreData", package: "SwiftUIWeb"),
                .product(name: "CoreData", package: "Shadows", condition: .when(platforms: [.wasi])),
                .product(name: "SafariServices", package: "Shadows", condition: .when(platforms: [.wasi])),
                .product(name: "os", package: "Shadows", condition: .when(platforms: [.wasi])),
            ],
            path: "upstream/EasyCrypto/EasyCrypto",
            exclude: ["Info.plist", "Launch Screen.storyboard", "Preview Content", "Persistance/CoinsDB.xcdatamodeld"],
            resources: [.process("Assets.xcassets"), .process("Theme/Fonts/Files/arialbold.ttf")],
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: stack,
            plugins: [.plugin(name: "CoreDataModel", package: "SwiftUIWeb")]
        ),
        // MARK: amikhaylin/pompaddo — the iOS app target `PomPadDo.mobile` (SWIFT_VERSION 6.2,
        // approachable concurrency): its synchronized folder `PomPadDo.mobile` plus the files of
        // `Shared` the target lists as members (every Swift file there), with the two packages it
        // links, CloudStorage and swiftdata-transferrable, at the versions its Package.resolved
        // pins. The repository root is the target path so both folders are its; of them, the files
        // Xcode handles through other phases are excluded. The macOS, watchOS, widget, share and
        // Safari targets are not the iOS app's and are left out.
        .executableTarget(
            name: "Pompaddo",
            dependencies: swiftUI + [uiKit] + host + [
                "CloudStorage", "SwiftDataTransferrable",
                .product(name: "SwiftData", package: "SwiftUIWeb"),
                .product(name: "UserNotifications", package: "SwiftUIWeb"),
                .product(name: "WidgetKit", package: "SwiftUIWeb"),
                .product(name: "StoreKit", package: "SwiftUIWeb"),
                .product(name: "Charts", package: "SwiftUIWeb"),
                .product(name: "AVFoundation", package: "SwiftUIWeb"),
                .product(name: "EventKit", package: "SwiftUIWeb"),
                .product(name: "AudioToolbox", package: "SwiftUIWeb"),
            ],
            // Its upstream tree with `os(iOS)` read as true (decision 0025): `ios-sources/pompaddo`,
            // which scripts/build-wasm.sh makes from `upstream/pompaddo` before every build.
            path: "ios-sources/pompaddo",
            exclude: ["PomPadDo.mobile/Info.plist", "PomPadDo.mobile/LaunchScreen.storyboard",
                      "PomPadDo.mobile/PomPadDo_mobile.entitlements", "PomPadDo.mobile/Preview Content",
                      "Shared/Tests", "Shared/Localizable.xcstrings"],
            // The folder's Swift, not the folder: its asset catalog is a resource of its own.
            sources: ["PomPadDo.mobile/Activities", "PomPadDo.mobile/CustomViews", "PomPadDo.mobile/Settings",
                      "PomPadDo.mobile/MainTabsView.swift", "PomPadDo.mobile/MainView.swift",
                      "PomPadDo.mobile/PomPadDo_mobileApp.swift", "Shared"],
            resources: [.process("PomPadDo.mobile/Assets.xcassets")],
            swiftSettings: [.swiftLanguageMode(.v6), .enableUpcomingFeature("InferIsolatedConformances"),
                            .enableUpcomingFeature("NonisolatedNonsendingByDefault")],
            linkerSettings: stack
        ),
        // tomlokhorst/CloudStorage 0.7.0 (its Package.swift: one target, tools 5.9).
        .target(name: "CloudStorage", dependencies: swiftUI + [uiKit], path: "upstream/CloudStorage/Sources/CloudStorage",
                swiftSettings: [.swiftLanguageMode(.v5)]),
        // Whiffer/swiftdata-transferrable 3.0.2 (its Package.swift: one target, tools 5.9).
        .target(name: "SwiftDataTransferrable",
                dependencies: swiftUI + [.product(name: "SwiftData", package: "SwiftUIWeb"),
                                         .product(name: "UniformTypeIdentifiers", package: "Shadows", condition: .when(platforms: [.wasi]))],
                path: "upstream/swiftdata-transferrable/Sources/SwiftDataTransferrable",
                swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
