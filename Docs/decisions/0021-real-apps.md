# 0021 — Phase 10: open-source apps, unmodified

Date: 2026-10-12
Status: accepted

## Context

Phases 0–9 built the API surface element by element, each measured against Apple's SwiftUI.
What that order does not test is whether a real app's source compiles and runs as it is. Three
open-source iOS apps were wrapped in a package over SwiftUIWeb (the app's sources copied into an
executable target, `SwiftUI` from this package, nothing else changed) and built for wasm and for
the native host:

| App | Shape | Outcome |
|---|---|---|
| [SwiftUI-2048](https://github.com/unixzii/SwiftUI-2048) (MIT, 1 000 lines; a 2019 `UIApplicationDelegate` + `UIHostingController` game) | pure SwiftUI | Runs in the browser and the native host after 9 source patches; swipes move and merge tiles as on iOS |
| [Scrumdinger](https://github.com/Sedlacek-Solutions/Scrumdinger) (MIT, 3 500 lines in 11 SPM targets; Apple's tutorial app rebuilt with iOS 17 idioms) | modular app with Speech, AVFoundation and file persistence behind protocols | Builds and launches after 10 patches; the add-scrum sheet loses its Dismiss and Add buttons |
| [clean-architecture-swiftui](https://github.com/nalexn/clean-architecture-swiftui) (MIT, 2 400 lines; SwiftData, Combine, URLSession, UserNotifications, a third-party package) | layered app over Apple frameworks | Does not get past its imports |

Every patch is a gap the project can close, except the ones the web cannot host.

## Findings

Three gaps are at the module level and bite every app:

1. **`import Foundation` next to `import SwiftUI`.** On wasm the SDK's Foundation and
   WebFoundation's stand-ins (decision 0017) both declare `URL`, `Data`, `DateFormatter` and
   `NumberFormatter`, so an app file that imports both cannot name them; and the names Apple's
   Foundation re-exports (libm's `log2` and `pow`, `DispatchQueue`, `@Observable`, `Bundle`)
   are out of scope. On macOS the same pair leaves `ObservableObject` and `@Published`
   ambiguous because Foundation re-exports Combine. Nearly every app file imports Foundation.
2. **`import Combine`** is `no such module` on wasm. The Combine-free publishers cover
   `onReceive`, not an app's `AnyPublisher`, `map`, `removeDuplicates`, `first`,
   `Publishers.Merge`, `Cancellable` or completion.
3. **Resources.** `Bundle.module`, `Color(_:bundle:)` and `Image(_:bundle:)`: SPM's generated
   accessor imports Foundation and extends `Bundle`.

Below them, a short list of API (`contentShape`, the `Shape` shortcuts, `Button(systemImage:)`,
the error and `presenting:` alerts, `Transaction(animation:)`,
`AnyTransition.modifier`, `Scene.environment`, the deprecated `navigationBarTitle` family,
`@UIApplicationDelegateAdaptor`), one iOS runtime bug (a `NavigationStack` inside a sheet has no
bar of its own), and three framework-sized absences (`URLSession`, SwiftData, durable files).
Speech, audio sessions, push notifications and `@objc` have no web equivalent.

## Decision

Phase 10 makes the three apps build unmodified, in this order, each item through the element
workflow and recorded in `Docs/todo.json`:

| # | Item | Why here |
|---|---|---|
| 1 | `pf-foundation-module` | A package module named `Foundation`, linked only on wasm, re-exporting WebFoundation, WASILibc, Observation and Dispatch and declaring `Bundle`. The same shadowing the `SwiftUI` module already relies on; unblocks every app file. |
| 2 | `pf-combine-module` | A `Combine` module, linked only on wasm, over the existing publishers with operators, `AnyPublisher`, `Cancellable` and a completion path. |
| 3 | `sw-shape-shortcuts`, `sw-app-api-gaps`, `sw-scene-environment` | The API list; each small, each with a fixture. |
| 4 | `sw-ios-sheet-nav` | The sheet bar, from a simulator golden. |
| 5 | `uk-app-delegate-adaptor` | The app-level UIKit entry points. |
| 6 | `ap-app-ports` | `scripts/check-apps.sh` builds the three apps from pinned commits; the patches that remain are the wontfix set. |
| 7 | `pf-urlsession`, `pf-persistence`, `pf-swiftdata` | Later: each needs its own decision (fetch and CORS; the origin private file system; the predicate language). |

Shadowing rules: a module named `Foundation` or `Combine` must never be built on macOS or
Linux (it would shadow the system module for every target compiled after it, `-I` paths come
before the SDK), so the targets live in a package of their own that the `SwiftUI` target
depends on with `.when(platforms: [.wasi])`; nothing runs `swift build` in that package on a
native platform.

~~Wontfix (`pf-non-web-frameworks`): `Speech`, `AVAudioSession`, `AVAudioEngine`,
`AVAudioPlayer`, `UserNotifications` and `@objc`/`#selector`. Apps that isolate them behind
protocols (Scrumdinger's services) swap the implementation for the web build.~~ Withdrawn, see
the acceptance standard below.

## Consequences

- The support matrix gains a `Platform` row per module (`Foundation` on wasm, `Combine` on
  wasm) and the apps become a standing check beside the fixtures.
- macOS native keeps Apple's Foundation and Combine; the `ObservableObject` ambiguity under
  `import Foundation` + `import SwiftUI` stays recorded in `pf-combine-module` until the
  native host matters enough to shadow there too.

## Outcome of items 1 and 2 (2026-10-12)

A module named `Foundation` in `Packages/Shadows` builds and links for wasm beside the SDK's
(nothing in an app's graph imports the SDK's Foundation; JavaScriptKit's
`JavaScriptFoundationCompat` is not linked). It cannot be a dependency of this package's
`SwiftUI` target, though: SwiftPM's wasm test discovery generates `import XCTest`, and XCTest's
binary module wants the SDK's Foundation (`_BridgedStoredNSError`; the generated runner also
names `NSObject` and `FileHandle`), so the Linux CI job crashed the compiler. The shadows are
therefore products an app's `Package.swift` links (two lines, in the README and
`Examples/Launches`), and the `SwiftUI` shim re-exports `WebFoundation`, `WASILibc` and
`WebCombine` itself so `import SwiftUI` alone gives libm and the ObservableObject family, as
Apple's does. Two size traps surfaced on the way: naming FoundationEssentials' `LocalizedError`
protocol descriptor extracted `CocoaError.swift` and 3.3 MB of FoundationEssentials into the
Gallery (WebFoundation now declares its own), and a second re-export hop made fixture code's
`String.contains(_:)` resolve to `_StringProcessing` (the Regex engine; the shim re-exports
WebFoundation directly). Counter 2,934,562 → 2,967,145 brotli for both items; the Gallery
3,714,742 → 3,771,277.

The 2048 port's patches for `import Foundation`, `import Combine`, libm and the nonisolated
model are gone; Scrumdinger's `@Observable` under `import Foundation`, `Bundle.module` and its
real `FileService` compile; the Countries app moves on to `UserNotifications`. The shadow moved
the boundary: files that used to compile against the SDK's Foundation now meet WebFoundation's
stand-ins, which is where `FileManager`, `JSONEncoder`, `NSError` and `Error.localizedDescription`
came from. A `@StateObject` on the `App` struct, which `Examples/Launches` has as most apps do,
was a new object on every access with the body read once; the app is now one instance and a
change re-reads its body. Next: `sw-shape-shortcuts`, `sw-app-api-gaps`, `sw-scene-environment`.

## Acceptance standard (2026-10-12)

The survey above counted "runs after N patches". That is not the bar. An app counts when it
runs **from its upstream sources exactly as published**: no edited file, no source left out,
no entry point replaced, no feature swapped for a mock, no test weakened. What this package
is allowed to add is the API and runtime behaviour the app reaches for, with real web
behaviour behind it, and a wrapper manifest that names the upstream targets and links this
package's products where Xcode links Apple's frameworks (`Apps/README.md` records every line
of that wiring). The earlier outcome statements ("2048 runs modulo three Objective-C lines",
"Scrumdinger builds after its Speech and audio mock swaps") are withdrawn; by this standard
no app has passed yet.

The baseline is auditable: the four upstream trees (the three apps and the Countries app's
`EnvironmentOverrides` dependency) are git submodules under `Apps/upstream/` at the commits in
`Apps/README.md`, each with a SHA-256 manifest of every tracked file; `scripts/check-apps.sh`
fails on any pin, file or hash that differs before it builds anything.

### Status at the baseline

| App | Compiles on wasm | What stops it |
|---|---|---|
| SwiftUI-2048 | every file but `AppDelegate.swift` | `@objc func newGame` → "Objective-C interoperability is disabled"; `#selector(newGame(_:))` → "'#selector' can only be used with the Objective-C runtime" (forcing `-Xfrontend -enable-objc-interop` crashes the frontend). Also `UIMenuBuilder`, `UIKeyCommand`, `UIMenu.edit/format/view` and `@UIApplicationMain`'s `init()` requirement, which are ours to add. |
| Scrumdinger | every target but `AudioService` and `SpeechService` | `AVAudioPlayer`, `AVAudioSession`, `AVAudioApplication`, `AVAudioEngine`, `SFSpeechRecognizer`, `SFSpeechAudioBufferRecognitionRequest`, `SFSpeechRecognitionTask` (`pf-avfoundation-audio`, `pf-speech`). Two Swift 6 errors in `ViewComponents` were ours: `ToolbarContent` and `ProgressViewStyle` were not `@MainActor @preconcurrency` as Apple's are (fixed with the protocol family, `sw-isolation-fidelity`). At runtime: `Media.xcassets` theme colours (`pf-xcassets`), the sheet bar (`sw-ios-sheet-nav`), `ProcessInfo.environment` being empty makes `RuntimeEnvironment.current` the physical device, so the real services run, as on a phone. |
| CountriesSwiftUI | not yet past `EnvironmentOverrides` (at the baseline; every file by 2026-10-13, see below) | its dependency needs `UIGraphicsImageRenderer`, `UIWindow.drawHierarchy`, `UIImageWriteToSavedPhotosAlbum`, the feedback generators and `Bundle.localizations`; then the app's `SwiftData`, `URLSession`, `UserNotifications`, `UIApplicationDelegateAdaptor` and `UISceneConfiguration.delegateClass`. |

The first row's compiler error is a barrier this package cannot lift by adding API: wasm Swift
is built without Objective-C interop, so `@objc` and `#selector` are rejected at the parse
(forcing `-enable-objc-interop` on the wasm frontend aborts it). The barrier stays **open**;
neither a native-only acceptance nor another app in its place is authorised. The
source-preserving routes, all design-level and material:

1. An Objective-C runtime for wasm and a Swift toolchain built with interop on for the wasm
   target: `@objc` methods get selectors, `#selector` a `Selector`, `UIKeyCommand(action:)` a
   real target-action. A port of an open-source runtime (GNUstep's libobjc2 compiles with
   clang; Apple's objc4 is Darwin-only), then a stdlib/toolchain rebuild — a toolchain
   project, not a package change; the frontend abort is the first thing to report upstream.
2. An upstream compiler relaxation: `@objc` accepted as an annotation and `#selector` lowered
   to a string-backed `Selector` on platforms without the runtime, with the framework (our
   UIKit) dispatching by name. A Swift evolution matter; this package could then supply
   `UIMenuBuilder`, `UIKeyCommand`, `UIMenu.edit/format/view` and the `@UIApplicationMain`
   path, which are ordinary API work.
3. Nothing else: excluding the file, generating a rewrite without the two lines, or supplying
   an entry point are the modifications the standard rules out.

Until one of the first two exists, SwiftUI-2048 is "every file but `AppDelegate.swift`
compiles" and not a wasm app.

### Scrumdinger (2026-10-12, later the same day)

Compiles for wasm from its sources exactly as pinned, every target, after `pf-avfoundation-audio`
(the audio API its services call, over the browser's audio element and microphone) and the
`Speech` surface, plus the fidelity fixes the build surfaced in this package (the protocol
isolation family, nonisolated `Shape`, plain action closures where Apple's are plain, a
`ProgressView(configuration)` inside a custom style drawing in the default style — an
unbounded recursion before). In Chromium (`Playwright/scrumdinger-probe.mjs`, a CI step of its
own): the add sheet with its bar, a title typed, an attendee added with the icon-only button
(which now reads as "Add Attendee"), the scrum on the list, still there after a reload through
its `FileService`, the detail screen, the meeting screen. **The meeting is blocked**: the app
starts its timer only after `requestPermissions()` on its `SpeechService` succeeds, and speech
is unavailable in the browser by design — the page's `SpeechRecognition` listens to a
microphone stream of its own rather than the buffers the app appends from its audio tap, and
in Chrome sends the audio to Google's service; neither is the app's data flow nor an approved
transmission, so no recogniser is installed and the app presents its own alert. The faithful
options (the appended buffers into a local recogniser: an AudioWorklet-fed track for
`SpeechRecognition.start(track)` with `processLocally`, or an in-page model) are in
`pf-speech` for a decision. A separate-stream recogniser would not count as the meeting
working even if it were enabled.

Two `Button(action: storedClosure)` warnings remain in the app's build: Apple's frameworks are
compiled in the Swift 5 language mode, where a Swift 6 app sees `@MainActor` closure
parameters as preconcurrency; ours are Swift 6 modules, so the same call warns. Building the
API modules in Swift 5 mode with every Swift 6 upcoming feature except SE-0434 would silence
it (verified in a scratch package) at the cost of ~120 sites that rely on `@MainActor`
closures being Sendable; recorded under `sw-isolation-fidelity`, not done.

### Countries (2026-10-13)

Compiles for wasm from its sources exactly as pinned, every file, after `uk-app-delegate-adaptor`,
`pf-usernotifications`, `pf-urlsession` and `pf-swiftdata` — the last written against its
models and repositories as published: `DBModel.Country`, `CountryDetails` and `Currency` with
their `@Attribute(.unique)` codes and one-sided `@Relationship(inverse:)` declarations, the
`@ModelActor` repository's `store(countries:)` (an upsert per fetch), `store(countryDetails:for:)`
(fresh `Currency` instances each call, neighbours from a `#Predicate` fetch) and
`countryDetails(for:)` on the main context, the list's search `#Predicate` over
`localizedStandardContains` sorted by name, the `Query+Search` helper (`@Query var query: [T]`
assigned through `_query`, `.equatable()`). `SwiftDataTests` holds those shapes verbatim and
proves upsert, both-sided inverses, delete, predicate/sort, reopen with relationships, in-memory
independence, autosave counts and a `@Query` following the actor's save; the Launches example
proves persistence across reloads in Chromium. Those are framework proofs. In Chromium
(`Playwright/countries-probe.mjs`, a CI step of its own with its evidence): the app launches,
its persistent `ModelContainer` opens over localStorage (its own "issue with local database"
footer — the stub fallback — is absent; the hosts now install before the `App` value is made,
since `AppEnvironment.bootstrap()` opens the container from the delegate), and **its request
to `https://restcountries.com/v2` fails as that service stands** (a 301 to a deprecation notice
without a CORS header, verified 2026-10-12 under `pf-urlsession`): the app shows its own
`ErrorView` ("An Error Occured", the browser's `TypeError: Failed to fetch`, Retry), and Retry
lands on it again. That is the app's real path for a gone service, recorded with the commit,
the pin, screenshots and a trace — not a pass. The list, search and detail flows are blocked
on the external service; `full_app_pass` is false. No fixture data, proxy or endpoint rewrite
is used, and the endpoint decision is held (`pf-urlsession`).

### The keyboard host (2026-10-13)

`uk-app-delegate-adaptor` had one gap left open: no browser host set `UIKitScene.keyboardFrame`,
while the Countries `SystemEventsHandler` consumes `keyboardWillShow`/`keyboardWillHide` and
`keyboardFrameEndUserInfoKey`. `KeyboardHost` (SwiftUIWebCanvas) now reads the visual viewport
against the window while a text input has the focus (`_KeyboardFrameEstimator`: a pinch zoom,
a plain resize, the URL bar's collapse and a shrink without focus are not the keyboard) and
sets the frame, which posts the notifications. Three kinds of evidence, not interchangeable:
seven native tests on synthetic readings; the Launches probe in desktop Chromium on synthetic
readings injected through a debug hook (the host→scene→notification path, read as the
Countries handler reads it; a plain viewport resize stays 0); and the phone's own keyboard
through `Playwright/device-keyboard.mjs`, **not obtained in this session** — safaridriver could
not use the paired iPhone (`available`, not `connected`; the user's hands), and the iOS 27
Simulator run was inconclusive (the automation's tap never focused the field, so no keyboard
was asked for). The real-keyboard claim stays open until that script passes on the phone.
Also recorded: a browser that resizes the layout viewport for the keyboard (Chrome on Android
without `interactive-widget=overlays-content`) reports nothing — the page itself shrinks; and
`UIScreen.main.bounds` is not kept to the window for a SwiftUI app.
