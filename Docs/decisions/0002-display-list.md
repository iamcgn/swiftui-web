# 0002. Painting goes through a flat display list, one JS call per frame

Date: 2026-09-01
Status: accepted

## Context
The browser backend is a Canvas painter (user decision). Every Canvas2D call crossing the
wasm/JS boundary individually is the known performance ceiling for wasm UI; a future native
painter (CoreGraphics/Skia) needs the same drawing commands.

## Decision
`SwiftUIWebCore.Display` defines a `DisplayList`: a flat encoding (opcodes + Float64 operands +
interned strings/paths) with ops `save/restore/concat/clipRect/clipRRect/clipPath/beginGroup/
endGroup/fillRect/fillRRect/fillPath/strokePath/drawText/drawImage`. Backends implement
`Painter` and consume the whole list per frame. The Canvas backend passes it to JS as one
`Float64Array` + string table and decodes it in a single loop. Groups with opacity/shadow/blend
use an `OffscreenCanvas`; a `needsOffscreen` bit keeps the plain case direct.

## Evidence
Spike 0.5 (`Spikes/CanvasSpike`), 2026-09-01, headless Chromium (Playwright 1.47) at DPR 2,
**debug** wasm build, 3,000 rounded rects (one 300-rect translucent group through an
`OffscreenCanvas`) + 500 `fillText` runs = 32,003 doubles per frame, averaged over 120 frames:

| Stage | ms/frame |
|---|---|
| build display list (wasm, debug) | 1.01 |
| `[Double]` → `JSTypedArray<Double>` | 0.07 |
| JS decode + Canvas2D paint | 1.05 |
| total | 2.16 |

`measureText` × 1,000 distinct strings: 41.6 ms (0.04 ms each). Conclusion: the one-call-per-frame
display list is far under the 4 ms budget even unoptimised; text measurement is the expensive
primitive and must be cached (Text/ line-layout cache keyed by string+font+width).
Caveat: headless Chromium may rasterise in software; re-measure in desktop Chrome/Safari when
the gallery exists. Click events arrive with `offsetX/Y` in CSS points as expected.

## Consequences
Layout, hit testing, scrolling, text line layout and accessibility are all owned by Swift.
Canvas and headless backends must produce byte-identical lists for the same tree (tested).
