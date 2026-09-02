# 0007. Browser backend: raw JavaScriptKit, injected Canvas2D decoder, DOM button overlay

Date: 2026-09-02
Status: accepted (verified in headless Chromium; Safari/Firefox pending)

## Context
Decision 0002 fixed the display list and the one-call-per-frame painter but left open whether
the applier uses BridgeJS typed glue or raw JavaScriptKit, where the JS decoder lives, and how
text is measured and made accessible.

## Decision
- **Raw JavaScriptKit** (`JSObject`, `JSClosure`, `JSTypedArray<Double>`): the bridge surface is
  three functions (`paint`, `measure`, and the debug getters), too small to justify BridgeJS's
  code generation step in every app build.
- The Canvas2D decoder is a JavaScript string inside the Swift module (`PainterScript.swift`)
  that `CanvasHost` injects as a `<script>` once. An app's page only imports the PackageToJS
  bundle; no separate JS asset to ship or version.
- `DisplayListEncoder` (core, platform-neutral, unit-tested natively) produces the flat
  `[Double]` + string table; the decoder in JS mirrors `DisplayOp`/`DisplayPathOp`.
- Text: `Canvas2DTextEngine` measures widths with `measureText` (cached, rounded up to the half
  point like SwiftUI) and takes line heights, baselines and stack spacing from the macOS table
  measured by the harness (`SystemFontMetrics`). Line breaking is greedy on spaces for now.
- Accessibility: a `pointer-events: none` overlay of invisible `<button>` elements positioned
  from `Runtime.semanticsTree()`, so screen readers and Tab/Enter reach every button while the
  canvas keeps receiving pointer events. Clicks on the overlay activate through
  `Runtime.activate(semanticsIdentifier:)`.
- `window.__swiftuiwebDebug` exposes probe frames, the last display list and the frame count;
  `Playwright/tier-b.mjs` compares frames exactly and pixels with a tolerance against goldens.

## Consequences
- Canvas and headless produce the same display list for the same tree and text metrics; Tier B
  measures only the browser's text widths and rasterisation.
- Fonts other than the system font, DOM-assisted line breaking and IME arrive in Phase 2/3.
