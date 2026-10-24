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
| SwiftUI-2048 | every file, with the Objective-C runtime SDK (decision 0023) | At the baseline: `@objc func newGame` → "Objective-C interoperability is disabled"; `#selector(newGame(_:))` → "'#selector' can only be used with the Objective-C runtime" (forcing `-Xfrontend -enable-objc-interop` crashed the frontend). Route 1 below was built (2026-10-14): with `SWIFTUIWEB_WASM_SDK=swift-6.3.3-RELEASE_wasm-objc` the app compiles from its unmodified sources, and `Playwright/2048-probe.mjs` passes (launch, swipes, ⌘N). `UIMenuBuilder`, `UIKeyCommand(action:)`, `UIMenu.edit/format/view` and `UIApplicationMain` were ours to add and are added. The stock SDK still stops at `AppDelegate.swift`. |
| Scrumdinger | every target but `AudioService` and `SpeechService` | `AVAudioPlayer`, `AVAudioSession`, `AVAudioApplication`, `AVAudioEngine`, `SFSpeechRecognizer`, `SFSpeechAudioBufferRecognitionRequest`, `SFSpeechRecognitionTask` (`pf-avfoundation-audio`, `pf-speech`). Two Swift 6 errors in `ViewComponents` were ours: `ToolbarContent` and `ProgressViewStyle` were not `@MainActor @preconcurrency` as Apple's are (fixed with the protocol family, `sw-isolation-fidelity`). At runtime: `Media.xcassets` theme colours (`pf-xcassets`), the sheet bar (`sw-ios-sheet-nav`), `ProcessInfo.environment` being empty makes `RuntimeEnvironment.current` the physical device, so the real services run, as on a phone. |
| CountriesSwiftUI (retired 2026-10-22, see "Ember replaces Countries") | not yet past `EnvironmentOverrides` (at the baseline; every file by 2026-10-13, see below) | its dependency needs `UIGraphicsImageRenderer`, `UIWindow.drawHierarchy`, `UIImageWriteToSavedPhotosAlbum`, the feedback generators and `Bundle.localizations`; then the app's `SwiftData`, `URLSession`, `UserNotifications`, `UIApplicationDelegateAdaptor` and `UISceneConfiguration.delegateClass`. |

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

Route 1 exists since 2026-10-14 (decision 0023): with the Objective-C runtime SDK installed,
SwiftUI-2048 is a wasm app from its unmodified sources; `full_app_pass` for it is recorded by
`Playwright/2048-probe.mjs`. With the stock SDK it stays "every file but `AppDelegate.swift`".

#### The portable port (2026-10-13, not acceptance)

Corey approved a *separate* fork, [iamcgn/SwiftUI-2048](https://github.com/iamcgn/SwiftUI-2048)
(MIT, Cyandev's copyright and attribution kept), as a portable source port of the game for
iOS 17+ and the browser: upstream's model and views unchanged, the UIKit/AppKit shells and
the Objective-C selector replaced by a SwiftUI `App` with a closure-based New Game (a File
menu command and a visible button) and the arrow keys through `onKeyPress` on the focused
board. It is published with its tests, a Chromium probe judged against a port of upstream's
algorithm, and a hosted build. It is **not** the unchanged-app pass of this decision: the
pinned upstream in `Apps/upstream/SwiftUI-2048` stays the benchmark, and the port counts for
nothing in this decision's `full_app_pass` — that is Route 1's, above, recorded by the probe
against the unmodified sources (CI since 2026-10-17, with the published SDK).

Two library gaps the port found, kept apart from the port itself:

- A press on a `focusable()` view swallowed the drag gesture of the view around it (the
  board's swipes), and a canvas mouse-down let the browser move the page's focus to the body,
  taking the board's arrow keys away after a click on the button. Fixed in this package
  (`FocusableNode` as `_FocusOnly`: the press goes to the interactive ancestor and the view
  takes focus at the release; the canvas host keeps the page's focus on mouse-down unless a
  system drag began), with GestureTests for both modifier orders.
- `withTransaction` and `withAnimation` are `@MainActor` here and nonisolated in Apple's
  SwiftUI (`SwiftUICore.swiftinterface`): upstream's nonisolated `@objc func newGame` calls
  `withTransaction` and would not compile against this package even with the selector
  barrier gone. Recorded under `sw-isolation-fidelity`; the port's own helpers are
  `@MainActor` and sidestep it.

### Scrumdinger (2026-10-12, later the same day)

Compiles for wasm from its sources exactly as pinned, every target, after `pf-avfoundation-audio`
(the audio API its services call, over the browser's audio element and microphone) and the
`Speech` surface, plus the fidelity fixes the build surfaced in this package (the protocol
isolation family, nonisolated `Shape`, plain action closures where Apple's are plain, a
`ProgressView(configuration)` inside a custom style drawing in the default style — an
unbounded recursion before). In Chromium (`Playwright/scrumdinger-probe.mjs`, a CI step of its
own): the add sheet with its bar, a title typed, an attendee added with the icon-only button
(which now reads as "Add Attendee"), the scrum on the list, still there after a reload through
its `FileService`, the detail screen, the meeting screen. **The meeting was blocked** until
2026-10-23: the app starts its timer only after `requestPermissions()` on its `SpeechService`
succeeds, and speech was unavailable in the browser by design — the page's `SpeechRecognition`
listens to a microphone stream of its own rather than the buffers the app appends from its
audio tap, and in Chrome sends the audio to Google's service; neither is the app's data flow
nor an approved transmission, so no recogniser was installed and the app presented its own
alert. A separate-stream recogniser would not have counted as the meeting working.

**The meeting runs (2026-10-23, decision 0022).** The host now recognises exactly the buffers
the app appends: each `AVAudioPCMBuffer` from its tap goes through an AudioWorklet into a
MediaStreamTrack that Chrome's on-device `SpeechRecognition` (`processLocally`) listens to;
nothing leaves the device, and the locale's language pack is the one download, at
`requestAuthorization`. In the probe the microphone is Chrome's fake device playing a committed
recording ("one two three four five", looping), the browser the installed Chrome with its
sandbox on: the app is authorised, starts its engine and timer, accumulates the partial results
("One two three four five…"), and on leaving saves the history whose screen shows the
transcript. Scrumdinger's `full_app_pass` is true; the three apps of this decision all pass.

Two `Button(action: storedClosure)` warnings remain in the app's build: Apple's frameworks are
compiled in the Swift 5 language mode, where a Swift 6 app sees `@MainActor` closure
parameters as preconcurrency; ours are Swift 6 modules, so the same call warns. Building the
API modules in Swift 5 mode with every Swift 6 upcoming feature except SE-0434 would silence
it (verified in a scratch package) at the cost of ~120 sites that rely on `@MainActor`
closures being Sendable; recorded under `sw-isolation-fidelity`, not done.

### Countries (2026-10-13; retired 2026-10-22, the record stands)

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

### Ember replaces Countries (2026-10-22)

Corey retired the Countries app and chose a replacement, after a search for an open-source
SwiftUI app whose service answers a browser today (MIT, no packages, a keyless API with a
CORS header on the exact endpoints the sources call, persistence, flows a probe can drive):
[DatanoiseTV/ember-hackernews](https://github.com/DatanoiseTV/ember-hackernews) — Ember, a
shipping Hacker News reader (MIT, 6 200 lines, iOS 18, no third-party packages), pinned at
`1ed87d7f` (2026-06-24) as `Apps/upstream/ember-hackernews`. Its data comes from
`hacker-news.firebaseio.com` and `hn.algolia.com`, both answering any origin; its
persistence is `UserDefaults` and JSON files through `FileManager`; its surface is wide:
a `TabView`, a `NavigationStack` per tab, a `fullScreenCover` onboarding, a `List` of custom
rows over hidden `NavigationLink`s, a `LazyVStack` comment thread rendered from HTML into
`AttributedString`s, `searchable`, `swipeActions`, `contextMenu`, a `Font.custom` (Inter),
`Material`, and the account features behind `WKWebView`, `SFSafariViewController` and the
keychain. Countries' retirement is recorded in `Apps/README.md`: the app compiled, the
service it is written against is gone, and the frameworks it asked for stay proven by their
tests and the Launches example.

**Ember compiles for wasm from its unmodified sources and its ten flows pass in Chromium
against the live API** (`Playwright/ember-probe.mjs`, a CI step of its own; `full_app_pass`
true since 2026-10-22): the onboarding's seven steps to "Start Reading", the Top feed's rows
(rank, title in Inter, host, points, author, age), the New chip replacing them, a story's
discussion with its comments and their ages, the story saved from the bar and listed under
Saved, a search on Algolia from the Search tab's field, the Settings screen down to its
cache size, and a reload that skips the onboarding and keeps the bookmark. The favicons
come from `icons.duckduckgo.com`, which sends no CORS header: the browser refuses them and
the app shows its globe fallback — the app's own path for a failed favicon, counted in the
report, not a problem of the run.

What the app asked of the library, in the order the build and the flows asked: the WebKit
UIKit face (`WKWebView` over the host's frame, its configuration, data store and cookie
store, user scripts, the delegates), `SafariServices` and `Security` as modules of
`Packages/Shadows` (a root module named `Security` shadows Apple's for every macOS build),
`HTTPCookie`/`HTTPCookieStorage`, `NSString` with `String as NSString` bridging,
`NSRegularExpression` over the browser's `RegExp` (UTF-16 indices are `NSRange`'s units; no
engine in the bundle), `JSONSerialization`, `trimmingCharacters(in:)`, the byte-count and
compact-name format styles, `URL.resourceValues`, `error as NSError` (the compiler's
`_convertErrorToNSError` in the module named Foundation), `Material`, `Text.monospacedDigit`,
`Color(hue:saturation:brightness:)`, `defaultMinListRowHeight`, `UIColor(named:)`; and the
JSON decoder's key and date strategies, which were recorded and never applied. Runtime
defects it exposed, fixed: a cross-origin image drawn into the canvas tainted it and the
frame was abandoned mid-paint (images from another origin now load with CORS); a
`safeAreaInset`'s inset view got the inset it creates as its own safe area and grew every
layout; a `.principal` toolbar item did not replace the inline title; the selected tab
ignored `tint(_:)` and `Color.accentColor` ignored the catalog's `AccentColor`; a list row
holding a `NavigationLink` under a custom row did not push; a `searchable` on the stack
itself was not the root screen's; a `repeatForever` transaction animation leaked onto every
change of the same pass and kept the scene animating.

Known limit, recorded under `sw-perf`: one layout of a discussion's comment thread takes
about 2.5 s in the release build (and ten in debug) — nested stacks measure their children
at the cross product of the widths and heights their parents probe, 800 000 `sizeThatFits`
calls for sixty comments. The thread settles after that one layout; scrolling it is slow.
CI builds Ember in release and the probe polls generously.

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
The modes this reads are iOS Safari's and Chrome on Android's default since 108
(`interactive-widget=resizes-visual`: the visual viewport alone shrinks —
developer.chrome.com/blog/viewport-resize-behavior). Also recorded, as limits rather than
guesses: `resizes-content` (Chrome before 108, Android WebView by default) shrinks the layout
viewport with the visual one, so the page itself gets shorter and nothing is reported;
`overlays-content` shrinks neither, so a viewport difference cannot see the keyboard and
nothing is reported; and `UIScreen.main.bounds` is not kept to the window for a SwiftUI app.
