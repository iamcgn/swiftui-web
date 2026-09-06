# Architecture

The full roadmap with rationale is in `ROADMAP.md`; this file is the short, current description.

## One idea

Unmodified SwiftUI source compiles against **our** module named `SwiftUI`. The stock Swift
compiler handles `@ViewBuilder`, `@State`, `@Observable`. We provide the API surface, a runtime,
a layout engine implementing the documented SwiftUI semantics, and painter backends that
consume a display list.

```
App source ── import SwiftUI ──▶ SwiftUI (thin re-export) ──▶ SwiftUIWebCore ──▶ WebGraphics (Packages/WebGraphics)
                                                                │  Painter / TextEngine / SemanticsHost / TextInputHost
                        ┌───────────────────────────────────────┼─────────────────────────────┐
              SwiftUIWebCanvas (wasm)                 SwiftUIWebHeadless (any OS)        SwiftUIWebNative (macOS)
              Canvas2D painter, overlay, IME          recorder for tests                 CoreGraphics, AppKit window
```

## Modules

- `SwiftUI`: `@_exported import SwiftUIWebCore`, `Foundation`, `Observation`. Exists so tests can
  fall back to importing `SwiftUIWebCore` directly if `SwiftUI` ever resolves to Apple's framework
  on macOS (decision 0001).
- `WebGraphics` (`Packages/WebGraphics`, decision 0014): the graphics substrate SwiftUIWeb and
  UIKitWeb share. `Geometry/` (`CGRect` and friends on wasm, `Angle`, `EdgeInsets`, trigonometry),
  `Shapes/` (`Path`, its geometry and boolean algebra, `StrokeStyle`), `Display/` (`DisplayList`
  and its flat encoding, `PaintContext`, gradients, filters, `AssetCatalog`, `ColorScheme`),
  `Text/` (`TextEngine`, `TextLayouter`, `ResolvedFont`, the measured font and symbol tables),
  `Input/` (`SemanticsNode`, `TextInputInfo`, keys and pointer types hosts deliver). No runtime.
- `SwiftUIWebCore`: `API/` (public surface mirroring Apple's docs), `Runtime/` (type-structured
  `ViewNode` tree, `DynamicProperty` installation by key path, `withObservationTracking` per body,
  depth-ordered coalesced flush), `Layout/` (`ProposedViewSize`, `Layout` protocol, stacks),
  `Text/` (`Font` and its resolution), `Shapes/` (the `Shape` protocol and the built-in shapes),
  `Display/` (the render pass), `Platform/` (`PlatformProfile`: metrics and system colours per
  platform). Re-exports `WebGraphics`. Internal boundaries use `package` access.
- `SwiftUIWebCanvas` (wasm only): Canvas2D painter decoding the display list in one JS call per
  frame, DPR handling, rAF loop, root input listeners, DOM semantics overlay, hidden input for IME.
- `SwiftUIWebHeadless`: records display lists and replays recorded text metrics; powers the fast
  native fidelity tests.
- `Harness/` (separate package, macOS): renders `Fixtures/Sources` with **Apple's** SwiftUI and
  writes `Fixtures/Goldens`.

## Runtime invariants

1. The node tree mirrors the type tree. Only `ForEach` reconciles by key; branches, `AnyView`
   type changes and `.id` changes tear down state exactly as SwiftUI documents.
2. View lists flatten: `Group`, `ForEach`, `TupleView`, `Optional`, `_ConditionalContent`,
   `Section` contribute their children to the enclosing layout.
3. Layout rounds frames to `1 / displayScale` at placement.
4. Painting is a pure function of the node tree: canvas and headless display lists are identical.
5. Every inferred constant is backed by a fixture and recorded in `Docs/elements/`.
6. `Int` is 32-bit on wasm32: core code uses `Int64`/`UInt64`/`Double` wherever a value can exceed 2^31.

## Fidelity tiers

- Tier A (blocking, exact): headless renderer with recorded text metrics vs golden frames.
- Tier B (tolerance): browser frames via a debug bridge and perceptual pixel diff vs golden PNGs.
