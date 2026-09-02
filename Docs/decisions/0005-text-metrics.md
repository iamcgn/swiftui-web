# 0005. Text measurement: Canvas2D `measureText` widths match CoreText exactly on macOS

Date: 2026-09-01
Status: accepted

## Context
Layout fidelity depends on text measurement. The plan assumed CoreText (goldens) and Canvas2D
(browser) would disagree by up to ~0.5pt and designed two fidelity tiers around that.

## Evidence
Spike 0.11, 2026-09-01, headless Chromium 129 (Playwright 1.47) on macOS 26.2 vs CoreText via a
CLI tool, Inter 4.1 Regular (OFL, loaded from the same TTF through `FontFace`) and the system font:

| String | CoreText Inter 13 | Canvas Inter 13 | CoreText SF 13 | Canvas `-apple-system` 13 |
|---|---|---|---|---|
| "Hello, World" | 74.88330078125 | 74.88330078125 | 73.658203125 | 73.658203125 |
| "Count: 0" | 52.51416015625 | 52.51416015625 | 51.974609375 | 51.974609375 |
| pangram (43 chars) | 276.10400390625 | 276.10400390625 | 270.1181640625 | 270.1181640625 |
| "WWWW" | 52.1904296875 | 52.1904296875 | 50.01953125 | 50.01953125 |

Widths are bit-identical for every sample (Chromium on macOS shapes with CoreText). Vertical
metrics differ only by rounding: CoreText ascent 12.59 / descent 3.14 for Inter vs Canvas
`fontBoundingBoxAscent` 13 / `Descent` 3; a DOM span reports 74.89 × 16 (line box rounding).

## Decision
- Advances come from `measureText`; vertical metrics (ascent, descent, leading, line height) come
  from a per-font metrics table derived from the font file (hhea/OS2), not from
  `fontBoundingBox*`, so line heights match CoreText (Inter 13: 15.73; SF 13: 15.31).
- Tier A (exact, recorded metrics) stays the blocking gate so Linux/Windows browsers, which shape
  with HarfBuzz/FreeType, cannot break CI; Tier B on the macOS runner is expected to be exact for
  widths.
- Inter remains the bundled deterministic fixture font; `-apple-system` is used for the "SF"
  fixture family on Apple hosts.

## Consequences
Re-check on Linux Chromium and Firefox when the browser CI job exists; record deltas here.
