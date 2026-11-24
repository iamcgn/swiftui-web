# 0026 — WebGL2 draws the frames Canvas2D is slow at

Date: 2026-11-24
Status: accepted

## Context

Every view is drawn by PainterScript's Canvas2D decoder of the flat display list. A WebGL2
painter for the same list (`Packages/WebGraphics/Web/painter-gl.js`) was measured on an M1 Pro
(Playwright/webgl/RESULTS.md): busy screens paint 3-5x faster (Ember 38 → 8 ms, Buttoncraft
12 → 2.4 ms, Scrumdinger 6.6 → 2.1 ms), simple ones about 1 ms slower (Counter 0.9 → 2.5 ms),
and software WebGL (SwiftShader, which CI and GPU-less machines get) is many times slower than
Canvas2D. It matches Canvas2D on 724 of 725 gallery renders within Tier B's tolerance.
Counter's wasm had about 13 KB of its 3 MB budget left (decision 0006); the painter is 21.5 KB
brotli.

## Decision

- The painter ships beside the wasm: `scripts/build-wasm.sh` copies it to the bundle's
  `assets/painter-gl.js`, and `CanvasHost` loads it with a script tag when the browser has
  WebGL2. The wasm carries only the loader. Until it loads, and without the file or WebGL2,
  Canvas2D paints every frame, as before.
- Its default mode, `auto`, gives a frame to WebGL when Canvas2D's measured cost for a frame of
  that size passes 4 ms, and back to Canvas2D below 2 ms (one Canvas2D frame in 240 keeps the
  estimate current). Simple screens keep Canvas2D's lower fixed cost.
- `auto` refuses software WebGL (`failIfMajorPerformanceCaveat`, and the renderer's name), so CI
  and GPU-less machines paint with Canvas2D. `?webgl=overlay` forces WebGL for every frame
  (tests), `?webgl=off` keeps it out.
- CI checks the forced WebGL path against Canvas2D on Counter, the fallbacks (WebGL off, the
  query), and that `auto` switches on a slow frame (`Playwright/webgl-painter-probe.mjs`).

## Consequences

- One more request after start (92 KB, 25 KB gzip). Pages served without the bundle's assets
  folder paint with Canvas2D and log the missing file.
- SceneKit's mesh op is drawn by its own renderer either way; under the WebGL painter its frame
  is a texture in the WebGL frame.
