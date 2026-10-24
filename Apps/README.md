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
only, `--pin` rewrites the manifests after a pin is moved on purpose. CI (the browser job,
`.github/workflows/ci.yml`) checks the submodules out and runs three separate steps, each
failing on its own: `check-apps.sh --verify` (integrity: the trees are exactly their pins),
a wasm build of an app (compilation), and its Playwright flow (behaviour). A claim in one is
not a claim in the others. The flows leave `report.json` (commit, pin, every flow's outcome,
`full_app_pass`), screenshots and a trace under `.build/apps/<app>`, uploaded as the
`apps-evidence` artifact; `full_app_pass` is true only when every flow passed, and a blocked
flow records what blocks it rather than being stubbed around (Scrumdinger's meeting was
blocked on speech until decision 0022's recogniser, 2026-10-23; all three apps pass now). The flows (`Playwright/scrumdinger-probe.mjs`, `Playwright/ember-probe.mjs`,
`Playwright/2048-probe.mjs`) are each a CI step of their own.

To run an app by hand: `scripts/build-wasm.sh Apps --debug --product <SwiftUI2048|Scrumdinger|Ember>`
(the last product built is what `Apps/index.html` loads; SwiftUI2048 needs the Objective-C
runtime SDK, `SWIFTUIWEB_WASM_SDK=swift-6.3.3-RELEASE_wasm-objc`, decision 0023; Ember is
built in release, `--debug` lays out a comment thread in tens of seconds), serve `Apps/` and
open `index.html?platform=ios`.

## Pins

| App | Upstream | Commit | Date | Licence |
|---|---|---|---|---|
| SwiftUI-2048 | [unixzii/SwiftUI-2048](https://github.com/unixzii/SwiftUI-2048) | `34f315a4103527eac366403b9e4632326cc2f257` | 2020-07-18 | MIT |
| Scrumdinger | [Sedlacek-Solutions/Scrumdinger](https://github.com/Sedlacek-Solutions/Scrumdinger) | `d575833721b0428ab407ceef10a7d43cffb7ad9f` | 2025-05-17 | MIT |
| Ember | [DatanoiseTV/ember-hackernews](https://github.com/DatanoiseTV/ember-hackernews) | `1ed87d7fcf2f3a6eeb466595f45300e10aba5267` | 2026-06-24 | MIT |

Retired 2026-10-22: [nalexn/clean-architecture-swiftui](https://github.com/nalexn/clean-architecture-swiftui)
(CountriesSwiftUI, pinned `9eca97b8`, with its EnvironmentOverrides dependency) — the app
compiled from its unmodified sources, and the service it is written against,
`restcountries.com/v2`, answers a deprecation notice without a CORS header, so no flow of
it can pass in a browser without a fixture or proxy the standard rules out. Ember took its
place (decision 0021, "Ember replaces Countries"); the frameworks Countries asked for
(SwiftData, URLSession, UserNotifications, the delegate adaptor) stay, proven by their tests
and the Launches example.

## What the wrapper manifest does, and does not do

Each wrapper target has the upstream target's name, sources (`path:` into the submodule),
language mode, `exclude:` and `resources:`, and links this package's products where Xcode
links Apple's frameworks (`SwiftUI`, `UIKit`, `AVFoundation`, `Speech`, `WebKit`, and on
wasm the `Foundation`, `Combine`, `Security` and `SafariServices` shadows). **Every `.swift` file
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
| Ember | `ember-hackernews` (XcodeGen `project.yml`: `Sources` + `Resources`, SWIFT_VERSION 5.0, iOS 18) | `EmberSkip/` (the Skip port), `Tools/`, `docs/`, `project.yml`, the text files, `Resources/Info.plist`, `Resources/PrivacyInfo.xcprivacy` | `Resources/Assets.xcassets` (accent, icon, launch colour), `Resources/Fonts` (Inter), as the target's |

Not compiled from any app: the apps' Xcode test targets (`ScrumdingerUITests`,
`Models/Tests`), their `SwiftUI2048-mac` Catalyst target, Ember's `EmberSkip` (its Skip/Android
port, a separate app) and `Tools`, and `Preview Content`. The SwiftUI
2048 Xcode project's `Info.plist` (no scene manifest, no storyboard) is what makes its
`@UIApplicationMain` delegate create the window itself.

Why the wrapper mirrors the upstream manifests instead of depending on them: an upstream
package's targets declare no dependency on this package, and SwiftPM links a target only to the
products it declares — their `import SwiftUI` finds no module on wasm (a target fetched by URL
sees not even the transitive clang modules). The mirror is the dependency wiring, recorded
here and nowhere in the upstream trees.

Status and the remaining gaps per app: `Docs/decisions/0021-real-apps.md`.
