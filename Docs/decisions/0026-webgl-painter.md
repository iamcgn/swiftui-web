# 0026 — WebGL2 draws the frames Canvas2D is slow at

Date: 2026-11-24
Status: accepted

## Context

Every view is drawn by PainterScript's Canvas2D decoder of the flat display list. A WebGL2
painter for the same list (now `PainterGLScript.swift` in WebGraphicsCanvas) was measured on an M1 Pro
(Playwright/webgl/RESULTS.md): busy screens paint 3-5x faster (Ember 38 → 8 ms, Buttoncraft
12 → 2.4 ms, Scrumdinger 6.6 → 2.1 ms), simple ones about 1 ms slower (Counter 0.9 → 2.5 ms),
and software WebGL (SwiftShader, which CI and GPU-less machines get) is many times slower than
Canvas2D. It matches Canvas2D on 724 of 725 gallery renders within Tier B's tolerance.
Counter's wasm had about 13 KB of its 3 MiB budget left (decision 0006); the painter is about
21 KB brotli, so Corey raised the budget to 4 MiB.

## Decision

- The painter is a Swift string like PainterScript (`PainterGLScript.swift` in
  WebGraphicsCanvas), so an app still needs nothing but its wasm bundle. `CanvasHost` installs it
  after PainterScript when the browser has WebGL2; without WebGL2, Canvas2D paints every frame,
  as before.
- Its default mode, `auto`, gives a frame to WebGL when Canvas2D's measured cost for a frame of
  that size passes 4 ms, and back to Canvas2D below 2 ms (one Canvas2D frame in 240 keeps the
  estimate current). Simple screens keep Canvas2D's lower fixed cost.
- `auto` refuses software WebGL (`failIfMajorPerformanceCaveat`, and the renderer's name), so CI
  and GPU-less machines paint with Canvas2D. `?webgl=overlay` forces WebGL for every frame
  (tests), `?webgl=off` keeps it out.
- CI checks the forced WebGL path against Canvas2D on Counter, the fallbacks (WebGL off, the
  query), and that `auto` switches on a slow frame (`Playwright/webgl-painter-probe.mjs`).

## Consequences

- Every app's wasm grows by about 21 KB brotli (Counter's budget is 4 MiB since this decision).
- SceneKit's mesh op is drawn by its own renderer either way; under the WebGL painter its frame
  is a texture in the WebGL frame.
