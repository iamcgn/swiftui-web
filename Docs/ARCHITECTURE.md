# Architecture

The full roadmap with rationale is in `ROADMAP.md`; this file is the short, current description.

## One idea

Unmodified SwiftUI source compiles against **our** module named `SwiftUI`. The stock Swift
compiler handles `@ViewBuilder`, `@State`, `@Observable`. We provide the API surface, a runtime,
a layout engine implementing the documented SwiftUI semantics, and painter backends that
consume a display list.

```
App source ── import SwiftUI ──▶ SwiftUI (thin re-export) ──▶ SwiftUIWebCore ──▶ WebGraphics (Packages/WebGraphics)
                                        │                       │  Painter / TextEngine / SemanticsHost / TextInputHost
                                        ├──▶ SwiftUIWebUIKit ──▶ UIKit (Packages/UIKitWeb) ──▶ WebGraphics
                                        │    UIViewRepresentable, UIViewControllerRepresentable
                        ┌───────────────────────────────────────┼─────────────────────────────┐
              SwiftUIWebCanvas (wasm)                 SwiftUIWebHeadless (any OS)        SwiftUIWebNative (macOS)
              Canvas2D painter, overlay, IME          recorder for tests                 CoreGraphics, AppKit window
```

## Modules

- `SwiftUI`: `@_exported import SwiftUIWebCore`, `SwiftUIWebUIKit`, `UIKit` (UIKitWeb's, as
  Apple's SwiftUI re-exports UIKit on iOS), `Foundation`, `Observation`. Exists so tests can
  fall back to importing `SwiftUIWebCore` directly if `SwiftUI` ever resolves to Apple's framework
  on macOS (decision 0001).
- `SwiftUIWebUIKit` (decision 0014, Phase 2): `UIViewRepresentable`, `UIViewControllerRepresentable`
  and the UIKit value bridges (`Color(uiColor:)`, `Image(uiImage:)`, `Font(_:)`). A representable
  is a `_PlatformViewHostNode` in `SwiftUIWebCore` over a `UIKitHostedTree` in `UIKitWebCore`: UIKit
  views paint into the same display list and join the same semantics tree
  (`Docs/elements/Representable.md`).
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
- `WebGraphicsCanvas`, `WebGraphicsNative`, `WebGraphicsHeadless` (in `Packages/WebGraphics`):
  the hosts, written against `HostedScene` (what a host drives: install the text engine and
  assets, ask for frames, forward pointer and key input, mirror the semantics tree). The canvas
  host paints the display list in one JS call per frame with DPR handling and a rAF loop, keeps
  a DOM semantics overlay and real inputs for IME; the native host does the same in a flipped
  `NSView` with CoreText and CoreGraphics; the headless module replays recorded text metrics.
- `SwiftUIWebCanvas`, `SwiftUIWebNative`, `SwiftUIWebHeadless`: the `Runtime` (a `HostedScene`)
  in each host, plus what is SwiftUI's to decide: the window background and chrome, the platform
  look from the page's pointer, links and share sheets, and `App.main()`'s launch.
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
