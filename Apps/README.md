# Apps — real apps, unmodified

Decision 0021's acceptance standard: an app runs from its upstream sources **exactly as
published**. Missing API and runtime behaviour belong in this package; nothing is patched,
excluded, mocked or rewritten on the app's side. What can be built is a wrapper manifest.

```
Apps/
  Package.swift            the only non-upstream code: one target per upstream target
  upstream/<app>/          git submodule at the pinned commit (never edited)
  upstream/<app>.sha256    SHA-256 of every tracked file at the pin
```

`scripts/check-apps.sh` verifies each submodule is at its pin with no file modified, added or
missing (git status plus the manifest), then builds every app for wasm; `--verify` checks
only, `--pin` rewrites the manifests after a pin is moved on purpose. CI runs it.

## Pins

| App | Upstream | Commit | Date | Licence |
|---|---|---|---|---|
| SwiftUI-2048 | [unixzii/SwiftUI-2048](https://github.com/unixzii/SwiftUI-2048) | `34f315a4103527eac366403b9e4632326cc2f257` | 2020-07-18 | MIT |
| Scrumdinger | [Sedlacek-Solutions/Scrumdinger](https://github.com/Sedlacek-Solutions/Scrumdinger) | `d575833721b0428ab407ceef10a7d43cffb7ad9f` | 2025-05-17 | MIT |
| CountriesSwiftUI | [nalexn/clean-architecture-swiftui](https://github.com/nalexn/clean-architecture-swiftui) | `9eca97b8cfff96a14084b564b1fefd949c93d232` | 2025-07-14 | MIT |
| EnvironmentOverrides | [nalexn/EnvironmentOverrides](https://github.com/nalexn/EnvironmentOverrides) (CountriesSwiftUI's dependency, 0.0.4) | `d0b763a678d254e51c74c48e83119bd063250ba3` | 0.0.4 | MIT |

## What the wrapper manifest does, and does not do

Each wrapper target has the upstream target's name, sources (`path:` into the submodule),
language mode, `exclude:` and `resources:`, and links this package's products where Xcode
links Apple's frameworks (`SwiftUI`, `UIKit`, `AVFoundation`, `Speech`, `SwiftData`,
`UserNotifications`, and on wasm the `Foundation` and `Combine` shadows). **Every `.swift` file
of every app target is compiled.** The excluded files are the non-Swift files Xcode processes
through other build phases:

| Target | Upstream path | Excluded (non-Swift) | Resources |
|---|---|---|---|
| SwiftUI2048 | `SwiftUI-2048/SwiftUI2048` (Xcode target, SWIFT_VERSION 5.0) | `Info.plist`, `Base.lproj/LaunchScreen.storyboard`, `MainMenu.xib`, `SwiftUI2048.entitlements`, `Preview Content/` | `Assets.xcassets` (app icon only) |
| Scrumdinger | `Scrumdinger/Scrumdinger/App` (Xcode target, Swift 6) | — (the target folder's `Assets.xcassets`, `Info.plist`, `Preview Content`, `TestPlan.xctestplan` sit beside `App/`, not inside it) | — |
| Protocols, Enumerations, Models, Extensions | `Scrumdinger/Models/Sources/*` (Models/Package.swift, tools 6.0) | — | — |
| AudioService, FileService, SpeechService | `Scrumdinger/Services/Sources/*` (Services/Package.swift) | — | AudioService: `Resources/` (`ding.wav`), as upstream |
| ViewComponents | `Scrumdinger/ViewComponents/Sources/ViewComponents` | — | — |
| Configuration, Resources, Scrum | `Scrumdinger/Library/Sources/*` (Library/Package.swift) | — | Resources: `Media.xcassets` (theme colours), as upstream |
| CountriesSwiftUI | `clean-architecture-swiftui/CountriesSwiftUI` (its Package.swift, Swift 5 mode) | `Resources/Preview Assets.xcassets`, as upstream | `Resources/Assets.xcassets`, `Resources/Localizable.xcstrings`, as upstream |
| EnvironmentOverrides | `EnvironmentOverrides/Sources/EnvironmentOverrides` (its Package.swift, tools 5.1) | — | — |

Not compiled from any app: the apps' Xcode test targets (`ScrumdingerUITests`, `UnitTests`,
`Models/Tests`), their `SwiftUI2048-mac` Catalyst target, and `Preview Content`. The SwiftUI
2048 Xcode project's `Info.plist` (no scene manifest, no storyboard) is what makes its
`@UIApplicationMain` delegate create the window itself.

Why the wrapper mirrors the upstream manifests instead of depending on them: an upstream
package's targets declare no dependency on this package, and SwiftPM links a target only to the
products it declares — their `import SwiftUI` finds no module on wasm (a target fetched by URL
sees not even the transitive clang modules). The mirror is the dependency wiring, recorded
here and nowhere in the upstream trees.

Status and the remaining gaps per app: `Docs/decisions/0021-real-apps.md`.
