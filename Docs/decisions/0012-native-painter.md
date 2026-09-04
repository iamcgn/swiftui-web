# 0012 — Native painter: CoreText engine, CoreGraphics painter, AppKit host, Tier C

Status: accepted (2026-09-04)

## Context

Phase 4 asks for native executables on the same runtime. Decision 0002 made the display list
the seam between layout and painting, 0005 showed Canvas2D advances equal CoreText's, and 0008
set the fidelity tiers: A (recorded metrics, exact frames) and B (browsers, pixels within a
tolerance). The WKWebView shell (`Tools/Host`) already runs the wasm bundle natively, but it is
still the browser painter. A true native painter needs a text engine that measures real fonts,
a painter for the display list, a window with input, and a way to prove it matches Apple.

## Decision

- `SwiftUIWebNative` is a target of the root package (it must see `SwiftUIWebCore`), with all
  sources under `#if canImport(AppKit)` so the target is empty on other platforms. The thin
  `SwiftUI` module depends on it on macOS the way it depends on `SwiftUIWebCanvas` on wasm, and
  `App.main()` launches `NativeHost` there: an unmodified `@main struct CounterApp: App` runs
  natively with `swift run`.
- `CoreTextEngine` is `Canvas2DTextEngine` with `CTLineGetTypographicBounds` in place of
  `measureText`: advances from CoreText, line heights, baselines and spacing from the measured
  macOS table, line breaking from `TextLayouter`. Fonts map through `NSFont.systemFont(ofSize:
  weight:)` with the rounded/serif/monospaced designs and the italic trait.
- `CoreGraphicsPainter` consumes the display list in its own coordinate system (points, origin
  top left, y down): a flipped `NSView`'s context, or a bitmap context the caller flips. Groups
  are transparency layers, gradients `CGGradient`s (angular ones 256 wedges), text is CoreText
  flipped about its baseline (gradient text through the clip text-drawing mode), images decode
  with ImageIO from the asset base directory with nine-part, tiling and tint handled in the
  painter.
- `NativeHost` runs the frame loop in `draw(_:)` of a flipped `NSView` (layout, render at the
  window's backing scale, paint), reschedules while the runtime animates, and forwards mouse,
  right-click, scroll and key events in the runtime's own coordinates. Environment variables
  (`SWIFTUIWEB_SCREENSHOT`, `SWIFTUIWEB_TIMEOUT`, `SWIFTUIWEB_ASSETS`, `SWIFTUIWEB_SIZE`) let
  scripts run an app headlessly and capture its first frame.
- **Tier C** (`Tests/NativeFidelityTests`): every enabled fixture is laid out with the CoreText
  engine (frames exact, text fixtures within Tier B's half-point width rule) and painted into a
  2x bitmap that is compared with the golden PNG by Tier B's rule (over white, a pixel differs
  when a channel is more than 32 off, at most 3 % may differ; symbol fixtures frames only).
  Steps run their animations out before comparing. It runs with `swift test` on macOS.

## Consequences

- One display list, three painters (Canvas2D, CoreGraphics, and the recorded/headless path)
  and three fidelity tiers, all against the same goldens; a painter bug shows up as a Tier C
  pixel number, a layout bug in every tier.
- The view is the text field editor (`NSTextInputClient`: typing appends, delete, Return
  submits, Escape and arrows go to the runtime; no selection or marked text yet) and the
  accessibility container (one `NSAccessibilityElement` per semantics node with press and
  increment actions), the AppKit counterparts of the browser's hidden `<input>` and DOM overlay.
  Only the first `WindowGroup` opens.
- CoreText reproduces Apple's text pixels far better than browsers do, so Tier C's numbers are
  the ones to watch for painter regressions; the browsers' numbers stay bounded by their text
  rasterisation.
