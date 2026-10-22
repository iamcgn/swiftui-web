// swift-tools-version: 6.1
// The three apps of decision 0021, built from their upstream sources exactly as pinned in
// `Apps/upstream/*` (git submodules; `scripts/check-apps.sh` verifies the pins and that no
// upstream file differs). This manifest is the only thing that is not upstream's: it names each
// app's targets, where their sources are, and the SwiftUIWeb products they link in place of
// Apple's frameworks. Every Swift file of each app is compiled; `exclude:` lists only the
// non-Swift files Xcode would process (plists, storyboards, entitlements), `resources:` mirrors
// upstream's own manifests. The mapping is tabulated in `Apps/README.md`.
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
        .executable(name: "CountriesSwiftUI", targets: ["CountriesSwiftUI"]),
        .executable(name: "Ember", targets: ["Ember"]),
    ],
    dependencies: [
        .package(name: "SwiftUIWeb", path: ".."),
        .package(name: "Shadows", path: "../Packages/Shadows"),
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

        // MARK: nalexn/clean-architecture-swiftui — its Package.swift's one target (Swift 5 mode,
        // the same path, exclude and resources), as an executable so the app runs.
        .executableTarget(
            name: "CountriesSwiftUI",
            dependencies: swiftUI + [uiKit] + host + [
                "EnvironmentOverrides",
                .product(name: "SwiftData", package: "SwiftUIWeb"),
                .product(name: "UserNotifications", package: "SwiftUIWeb"),
            ],
            path: "upstream/clean-architecture-swiftui/CountriesSwiftUI",
            exclude: ["Resources/Preview Assets.xcassets"],
            resources: [.process("Resources/Assets.xcassets"), .process("Resources/Localizable.xcstrings")],
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: stack
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

        // Its one dependency, nalexn/EnvironmentOverrides 0.0.4 (the version Xcode resolves for
        // `from: "0.0.4"`), from its own pinned submodule: a package fetched by URL could not see
        // this package's SwiftUI (SwiftPM links a target only to the products it declares).
        .target(
            name: "EnvironmentOverrides",
            dependencies: swiftUI,
            path: "upstream/EnvironmentOverrides/Sources/EnvironmentOverrides",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
