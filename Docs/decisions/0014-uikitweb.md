# 0014 — UIKitWeb: a shared graphics substrate, a UIKit reimplementation, and the representables

Status: accepted (2026-09-06); Phase 0 done

## Context

`UIViewRepresentable` and `UIViewControllerRepresentable` are the last large piece of the iOS
API surface an unmodified app source can hit. Supporting them means a `UIView` to represent:
a UIKit reimplementation that runs where SwiftUIWeb runs (wasm, macOS native, Linux headless),
built the way SwiftUIWeb was (decision 0001: an app-facing module with Apple's name; 0002: the
display list as the seam; 0010/0013: goldens from Apple's own frameworks). The user asked for
UIKitWeb as its own package that works independently, so a UIKit-only app can use it without
SwiftUI.

## Constraints that shape the layout

- **One `CGRect`.** On wasm there is no CoreGraphics: `Geometry/CGTypes.swift` defines `CGFloat`,
  `CGRect`, `CGAffineTransform` and friends. A UIKitWeb with its own copies would give an app
  that imports both frameworks two incompatible `CGRect` types, and a representable's `frame`
  would not type-check. The geometry has to live below both frameworks.
- **The package graph has one legal direction.** Apps get `UIViewRepresentable` from
  `import SwiftUI`, so the `SwiftUI` module depends on the `UIKit` module. SwiftPM forbids
  cycles, so UIKitWeb can never depend on the SwiftUIWeb package: everything both need
  (geometry, paths, the display list, text measuring and the measured tables, the hosts) must
  sit in a package below both.
- **`package` access stops at a package boundary.** What moves down becomes `public`; the
  substrate is a real API, the one UIKitWeb is written against.
- A module named `UIKit` shadows nothing on macOS, wasm or Linux: the macOS SDK the swiftly
  toolchain uses has no top-level `UIKit.framework` (Catalyst's lives under `iOSSupport` and is
  only visible with the flags `scripts/gen-goldens-ios.sh` adds). The Harness never depends on
  the root, so `import UIKit` there is always Apple's.

## Decision

Three packages in this repository:

```
SwiftUIWeb (root)          SwiftUI ─┬─ SwiftUIWebCore (+ _PlatformViewHostNode)
                                    └─ SwiftUIWebUIKit (UIViewRepresentable, UIViewControllerRepresentable)   [Phase 2]
        │ depends on
Packages/UIKitWeb          UIKit (thin) ── UIKitWebCore (UIView/CALayer trees, responders, controls,
        │ depends on                       UIViewController, UIWindow, UIApplication; a HostedScene)          [Phase 1]
Packages/WebGraphics       WebGraphics (geometry, Path, DisplayList + encoder, TextEngine + TextLayouter,
                           font and symbol tables, AssetCatalog, SemanticsNode, TextInputInfo, keys)          [Phase 0]
                           WebGraphicsCanvas / WebGraphicsNative / WebGraphicsHeadless (the hosts over
                           a `HostedScene` protocol)                                                          [Phase 0]
```

- SwiftUIWeb depends on UIKitWeb the way Apple's SwiftUI depends on UIKit; on wasm and Linux
  `import SwiftUI` re-exports `UIKit` as iOS does. Whether that stays unconditional is decided
  by the size gate after Phase 2.
- UIKit views paint into the same `DisplayList` as SwiftUI views, not into DOM elements. A
  representable is an ordinary painted leaf, so clipping, opacity, transforms, overlays and
  scroll views compose correctly; Tier A/C tests work unchanged; the macOS host paints UIKit
  views for free. The cost is painting UIKit's control looks by hand, mitigated by the iOS
  switch, slider, stepper, segmented and text field geometry already measured from Catalyst,
  which is UIKit's own. Text input keeps the overlay `<input>` mechanism through `TextInputInfo`.
- Goldens for UIKit fixtures come from real UIKit in the Catalyst window decision 0013 opened,
  plus a UIKit text-metrics recorder: UIKit measures text 1.5 to 2.5 pt narrower than
  SwiftUI's `Text` for the same string (`Docs/elements/iOS.md`).
- Phases: 0 extracts the substrate with no behaviour change; 1 makes UIKitWeb run alone
  (`Examples/UIKitCounter`); 2 adds the representables with sizing pinned by Catalyst goldens;
  3 adds Auto Layout (an in-house Cassowary solver, first), `draw(_:)`, `UIView.animate`,
  `UIHostingController` and the larger UIKit classes.

## Phase 0 log

- Step 1 (2026-09-06): `Packages/WebGraphics` with the `WebGraphics` module. Moved out of
  `SwiftUIWebCore`: `Geometry/` (with `EdgeInsets`), `Display/` (`DisplayList`, encoder,
  `PaintContext`, `AssetCatalog` and `ColorScheme`, `DisplayGradient`, `BlendMode`, the image
  loading protocol, pixel filters), `Shapes/` (`Path`, path geometry and boolean algebra, rounded
  corners, `StrokeStyle`), `Text/` (`TextEngine`, `TextLayouter`, `ResolvedFont`, the font and
  symbol tables), and the host value types (`SemanticsNode`, `TextInputInfo`, `KeyEquivalent`,
  `EventModifiers`, `KeyEvent`, `PointerType`). SwiftUI's nested names stay as typealiases
  (`Font.Weight = FontWeight`, `Font.TextStyle = FontTextStyle`, `Text.TruncationMode`,
  `Text.Scale`); conformances to SwiftUI protocols (`Animatable`, `Shape`) stay in Core
  (`Shapes/GeometryConformances.swift`). The measured tables hang off
  `SystemFontMetricsTables` (the generators in `scripts/` write there); `PlatformProfile`
  forwards. `SwiftUIWebCore` re-exports the substrate. 338 native tests pass unchanged; the
  wasm canvas target builds.
- Step 2 (2026-09-06): `HostedScene` (`WebGraphics/Input/HostedScene.swift`) is the list of
  calls the hosts made on `Runtime`: install text engine, assets, image loader, appearance and
  clipboard; `needsFrame`, `advanceFrame(elapsed:)`, `layout(in:)`, `render(scale:)`; pointer,
  wheel and key input plus the cursor; the semantics tree with activate, adjust, set value,
  focus and blur; the text-field callbacks. `Runtime` conforms in
  `SwiftUIWebCore/Runtime/HostedScene.swift`. The hosts moved: `CanvasSceneHost`
  (`WebGraphicsCanvas`, with `PainterScript` and `Canvas2DTextEngine`), `NativeSceneHost`
  (`WebGraphicsNative`, with `CoreTextEngine`, `CoreGraphicsPainter`, `RuntimeView` and the
  accessibility elements), `RecordedTextEngine` and the manifest reader (`WebGraphicsHeadless`).
  What stayed in SwiftUIWeb is SwiftUI's to decide and lives in thin wrappers named as before
  (`CanvasHost`, `NativeHost`, `HeadlessRenderer`): the window background and chrome flags, the
  platform look from the page's pointer (`requestedPlatform`, `hasCoarsePointer`), the
  `OpenURLAction` and `ShareAction` handlers over the hosts' `openURL` and `share`, and mounting
  the root. The page-facing names (`window.__swiftuiweb`, `__swiftuiwebAssets`,
  `__swiftuiwebDebug`, the `swiftuiwebready` event) are unchanged, so the Playwright scripts are too.
