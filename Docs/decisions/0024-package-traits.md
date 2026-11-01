# 0024. Core Data through `import SwiftUI` and `import Foundation`, per app, by a package trait

Date: 2026-10-31
Status: accepted

## Context
On iOS, a file that imports only SwiftUI uses `@FetchRequest`, `FetchedResults` and
`\.managedObjectContext`, and one that imports only Foundation uses `NSPredicate` and
`NSSortDescriptor`. Here all of them live in WebCoreData. The app sweep after the Core Data batch
(PR 11) still counted about 145 errors in three apps for exactly these files. Re-exporting
WebCoreData from `SwiftUI` for every app would put Core Data into every bundle, Counter's
included. Counter sits about 250 bytes under its 3 MB brotli budget (decision 0006).

## Decision
- SwiftUIWeb declares a package trait, `CoreData`, which is off by default. When it is on, the
  `SwiftUI` target depends on WebCoreData on wasm and re-exports it (`#if CoreData`).
  Packages/Shadows declares the same trait, and with it the `Foundation` shadow re-exports
  WebCoreData. An app enables it on both dependencies:
  `.package(name: "SwiftUIWeb", path: ..., traits: ["CoreData"])`, and the same for Shadows.
- The re-export happens only on wasm. On macOS, Apple's Foundation already declares
  `NSPredicate`, `NSSet` and the rest, and a second declaration would make them ambiguous.
- `Tools/Traits/traits.py` decides whether an app needs the trait. It looks for a Core Data
  model in the app's tree, or a Core Data name in its Swift code (not in comments or string
  literals). The app sweep uses it to write `traits: ["CoreData"]` into its generated manifest.
  `scripts/build-wasm.sh` prints a warning, with the line to add, when a hand-written manifest
  leaves the trait off.
- `NSManagedObject` is `Identifiable` by identity, as on Apple platforms, so `ForEach(results)`
  needs no `id:`.

## Why a trait and not a build flag
Traits are SwiftPM's way to make a dependency edge conditional (`.when(traits:)`) and to set a
compilation condition, both decided by the package that depends on SwiftUIWeb. A `-D` flag
passed to the whole build can't add the WebCoreData dependency. And making `SwiftUI` always
depend on WebCoreData would link it into every bundle, because Swift's metadata records keep
the types alive. The SwiftPM command line enables traits only for the root package, so the
switch belongs in the app's manifest. A generator for app manifests, when one exists, would
write it from `traits.py` the way the sweep does.

## Evidence
`Examples/CoreDataNotes` is built and probed in Chromium in CI. Its view imports only SwiftUI,
its predicate file imports only Foundation, and the probe covers adds, a clear, and a reload
that keeps the notes. Counter's bundle is unchanged, since the trait is off for it.

## Later: `DecimalFormatting` (2026-11-01)
`Decimal.FormatStyle` lives in WebDecimalFormats (Packages/WebGraphics), because naming
`Decimal` links Foundation's Decimal and what it reaches (3.4 MB) into every bundle that links
the module that names it. Packages/Shadows declares a second trait, `DecimalFormatting`, with
which the `Foundation` shadow re-exports WebDecimalFormats. Only Shadows has it: Apple's SwiftUI
gets Decimal's formatting from Foundation too, and here `import SwiftUI` does not re-export the
Foundation shadow. `traits.py` asks for it when an app's code names `Decimal`, since such an
app already ships Decimal, and `scripts/build-wasm.sh` warns when the manifest leaves it off.
The app sweep enables each trait its apps need, and the surface build enables all of them
(`sweep.py prepare --all-traits`) so the coverage diff counts their keys. Counter enables
neither.

## Later: `FoundationFormats` (2026-11-01)
`DateComponentsFormatter`, `ByteCountFormatter`, `NSCalendar` and the list and duration styles
live in WebFoundationFormats, which the `Foundation` shadow always re-exports. Apple's SwiftUI
re-exports all of Foundation, so apps name them in files that import only SwiftUI (Swift Charts
Examples' accessibility helpers). SwiftUIWeb declares a third trait, `FoundationFormats`, with
which `import SwiftUI` re-exports WebFoundationFormats on wasm. `traits.py` asks for it when an
app's code names one of the module's types or styles. Counter still enables none of them.
