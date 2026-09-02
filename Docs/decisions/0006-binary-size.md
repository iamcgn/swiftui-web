# 0006. wasm size budget: never link `Foundation` on wasm; own CG geometry types

Date: 2026-09-01
Status: accepted

## Evidence
Spike 0.7 (`Spikes/CanvasSpike`, release, `-Osize`, wasm-opt via PackageToJS), 2026-09-01:

| Variant | raw wasm | brotli -q 11 |
|---|---|---|
| `import Foundation` (String(format:)) | 46.06 MB | 12.07 MB |
| `import FoundationEssentials` (UUID, Date) | 3.87 MB | 1.03 MB |
| no Foundation | 3.85 MB | 1.02 MB |

The Foundation build's data section alone is 35.7 MB: `lib_FoundationICU.a` (41.7 MB in the SDK)
is pulled in by `Foundation`'s re-export of `FoundationInternationalization`. Debug builds are
~60 MB regardless. On wasm, `CGFloat`/`CGRect` are declared in `Foundation` (swift-corelibs),
not in `FoundationEssentials`, so getting them from Foundation costs the full 12 MB.

## Decision
- `SwiftUIWebCore` never imports `Foundation`; it imports `FoundationEssentials` where available
  (`#if canImport(FoundationEssentials)`), else `Foundation` (Apple platforms, where it is free).
- On platforms without `CoreGraphics`, `SwiftUIWebCore` declares its own `CGFloat`, `CGPoint`,
  `CGSize`, `CGRect`, `CGVector`, `CGAffineTransform` with Apple's API surface (Tokamak did the
  same, Apache-2.0; ours will be written fresh from the documented API).
- The thin `SwiftUI` module re-exports `CoreGraphics` + `Foundation` on Apple platforms and
  `FoundationEssentials` on wasm/Linux. Apps that `import Foundation` themselves on wasm pay the
  ICU cost knowingly; a doc page explains it.
- Budget: the Phase 1 Counter release bundle must stay under **3 MB brotli**; CI reports size and
  fails on regressions above the budget.

## Open items
- Whether a user's explicit `import Foundation` next to `import SwiftUI` makes `CGRect` ambiguous
  on wasm (two modules declaring it). Test in Phase 1 step 1; if it does, evaluate a
  `SwiftUIWebCoreGraphics` module users can exclude, or upstream a split of the geometry types
  into FoundationEssentials.
- CanvasKit sizing (spike 0.13) not measured yet; the unpkg HEAD request did not return a
  content-length. Known from its docs to be ~7 MB uncompressed; measure before offering it.
