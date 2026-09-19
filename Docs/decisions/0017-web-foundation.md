# 0017 — WebFoundation: Foundation's heavy value types stand in on wasm

Date: 2026-09-18
Status: accepted (Phase 8 step 6, `uk-size`)

## Context

`uk-size` asked for 300 KB of headroom under the 3 MB Counter budget (decision 0006) and
blamed the substrate's symbol and font tables. Measured with a linker map
(`-Xlinker --Map=`, aggregated by `scripts/wasm-size-map.py`), the tables are 60 KB brotli in
total (the Lucide outlines 44 KB, the symbol names 9 KB, the symbol metrics 6 KB); the 11.8 MB
raw Counter bundle was 4.3 MB of the Swift standard library, 4.8 MB of FoundationEssentials and
FoundationCollections, 1.4 MB of `_StringProcessing` and `_RegexParser`, and 4.6 MB of this
project's own modules.

The Foundation share is one piece. `wasm-ld` extracts an archive member whole, and
FoundationEssentials is compiled with whole-module optimisation, so a member holds generic
specialisations for unrelated files: `IndexPath.swift.obj` references `AttributedString`'s
descriptors, `URL.swift.obj` references `URLComponents`, which references `_StringProcessing`,
which references the whole Regex parser; `Data.swift.obj` references the string comparison
tables (`BuiltInUnicodeScalarSet`, 444 KB) and the property list codecs. A static closure over
the archives' undefined symbols (`llvm-nm`) from the symbols this project references shows
that any one of `Calendar`, `Data`, `URL` or `Locale` extracts 279 of the 578 members, 6.3 MB of
the map, and that only `Date` stands alone. There is no partial trim: every FoundationEssentials
value type but `Date` costs the whole library. Four direct references (`String.contains(String)`
in a colour space name, `JSONEncoder` in `CodableRepresentation`, `Data(base64Encoded:)`,
`IndexPath`) were the first extractors, and removing them changed nothing because `Calendar`
and `Data` follow the same chains.

Swift's name shadowing settles where stand-ins can live: a declaration shadows one of the same
name from another module only when its own module re-exports that module. A `public struct
IndexPath` in `UIKitWebCore` (which imports FoundationEssentials without re-exporting it) is
ambiguous in every file that sees both, and a typealias in the thin `UIKit` module does not
help because the lookup resolves it to the same two declarations. `CGGradient` (decision 0014)
worked because CoreGraphics is a C module, which Swift declarations shadow outright.

## Decision

- A `WebFoundation` module, the lowest target of `Packages/WebGraphics`, is the Foundation
  every module of this project imports. On Apple platforms and Linux it re-exports `Foundation`.
  On wasm it re-exports `FoundationEssentials` and declares `Data`, `URL`, `Calendar`,
  `TimeZone`, `Locale`, `DateComponents`, `IndexPath`, `ComparisonResult`, `SortOrder`,
  `SortComparator`, `ComparableComparator` and `sorted(using:)`; because it re-exports
  FoundationEssentials, its declarations shadow FoundationEssentials' for every importer,
  including app code that imports `SwiftUI` or `UIKit` (both thin modules re-export it).
- No file of this project imports `FoundationEssentials` directly; `import WebFoundation`
  replaces it (an explicit `import FoundationEssentials` in a file would make the shadowed
  names ambiguous there). `Date` stays FoundationEssentials', as do the types nobody here
  touches (`UUID`, `ProcessInfo`); an app that names one pays its members.
- The stand-ins keep Foundation's API for what the frameworks and ordinary apps call, with
  platform-neutral cores held to Foundation by tests on macOS
  (`Packages/WebGraphics/Tests/WebFoundationTests`): `_CalendarMath` (Hinnant's civil-date
  arithmetic, weeks under `firstWeekday` and `minimumDaysInFirstWeek`, clamped month steps,
  differences), `_URLParts` (RFC 3986 parsing and relative resolution) and `_Base64`.
  Differences from Foundation, recorded as `pf-web-foundation-gaps`: a `Data` slice is a fresh
  value indexed from zero; `URL` has no international host names, `URLComponents` or file
  system checks; the calendar is proleptic Gregorian whatever the identifier, with
  fixed-offset time zones (named zones are nil; `TimeZone.current` is the browser's offset,
  reported by the canvas host) and English symbols; `Locale` is an identifier; there is no
  `String.Encoding`, `String(data:encoding:)`, `DateFormatter` or `FormatStyle`.
- `CodableRepresentation` encodes with the project's own JSON coder
  (`SwiftUIWebCore/API/TransferJSON.swift`, `_TransferJSONEncoder` / `_TransferJSONDecoder`),
  tested against Foundation's coders on macOS.
- The 3 MB budget and the gate stay as they are; the symbol and font tables stay whole.

## Evidence (2026-09-18, `-Osize`, wasm-opt, brotli -q 11)

| Bundle | before | after |
|---|---|---|
| Counter (clean scratch build) | 3,046,910 (11,822,198 raw) | 2,076,672 (7,991,519 raw) |
| UIKitCounter | 2.24 MB (decision 0014) | 1,460,084 (5,537,540 raw) |
| UIKitSettings | — | 1,483,850 (5,548,099 raw) |
| Gallery (release, `/gallery/`) | 3.53 MB | 2,769,461 (11,219,571 raw) |
| Progress (`/progress/`) | 3.09 MB | 2,326,123 (9,001,009 raw) |

After the change the link holds no FoundationEssentials, FoundationCollections,
`_StringProcessing` or `_RegexParser` member; `WebFoundation` is 205 KB raw. The headroom under
the 3 MB budget is 1,069,056 bytes. Native tests: 367 (root), 73 (UIKitWeb), 8 (WebFoundation)
pass; Tier B: 513 of 513 renders within tolerance across 406 fixtures in Chromium, the date
pickers on WebFoundation's calendar among them.

## Consequences

- The wasm size story is now the standard library (4.3 MB raw, retained through its protocol
  conformance records) plus this project's own code. The next trims are in SwiftUIWebCore's
  2.9 MB (`ViewNode.swift` 264 KB, `Text.swift` 122 KB, the generated metrics accessors 150 KB).
- Every new use of a FoundationEssentials type on wasm is a size decision: check the map
  (`scripts/wasm-size-map.py`) before accepting one.
- The stand-ins are API a user's iOS code may reach; the gaps list is the place to grow them.
