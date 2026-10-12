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

Wontfix (`pf-non-web-frameworks`): `Speech`, `AVAudioSession`, `AVAudioEngine`,
`AVAudioPlayer`, `UserNotifications` and `@objc`/`#selector`. Apps that isolate them behind
protocols (Scrumdinger's services) swap the implementation for the web build.

## Consequences

- The support matrix gains a `Platform` row per module (`Foundation` on wasm, `Combine` on
  wasm) and the apps become a standing check beside the fixtures.
- macOS native keeps Apple's Foundation and Combine; the `ObservableObject` ambiguity under
  `import Foundation` + `import SwiftUI` stays recorded in `pf-combine-module` until the
  native host matters enough to shadow there too.

## Outcome of item 1 (2026-10-12)

A module named `Foundation` in `Packages/Shadows` builds and links for wasm beside the SDK's
(nothing else in the graph imports the SDK's Foundation; JavaScriptKit's
`JavaScriptFoundationCompat` is not linked), and the SwiftUI shim re-exports it. The 2048
port's patches for `import Foundation`, libm and `UserDefaults` are gone and its probe runs;
Scrumdinger's `@Observable` under `import Foundation`, `Bundle.module` and its real
`FileService` compile. The shadow moves the boundary: files that used to compile against the
SDK's Foundation now meet WebFoundation's stand-ins, which is where `FileManager`,
`JSONEncoder`, `NSError` and `Error.localizedDescription` came from. Counter grows 8.7 KB
brotli. Next: `pf-combine-module`.

