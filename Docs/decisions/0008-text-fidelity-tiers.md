# 0008. Text fidelity: recorded metrics for Tier A, browser measurement with a measured table for Tier B

Date: 2026-09-02
Status: accepted

## Context
Layout depends on text measurement, and only Apple's SwiftUI knows its exact numbers. The
headless (native) tests must be exact; the browser cannot be bit-exact across engines.

## Decision
- **Tier A (blocking, exact)**: the harness records, with real SwiftUI, the size and baselines
  of every `(string, font, width)` fixtures use, plus each font's zero-width minimum and
  per-font spacing (`Fixtures/Goldens/text-metrics.json`). `RecordedTextEngine` replays them; an
  unrecorded request fails the test with its key. Fonts are keyed identically on both sides
  (`ResolvedFont.key` / `FixtureFont.key`).
- **Tier B (tolerance)**: `Canvas2DTextEngine` measures widths with `measureText`, rounds up to
  the half point, applies SwiftUI's wrapping rule (a line fits including its trailing space,
  which is also the width it reports) and takes line heights, baselines and spacing from
  `SystemFontMetrics`, the table measured from the goldens. Frames are compared with a 3 %
  width tolerance for text fixtures and pixels with a 3 % differing-pixel bound (9 % for the
  fixtures that hit browser font fallbacks: weights 300/900, rounded, serif, monospaced).

## Evidence
2026-09-02, headless Chromium on macOS (SF available to the browser): 36/36 fixtures with
frames within tolerance, 33 of them exact to the point; pure layout fixtures 0.00 % pixel
difference; text fixtures 0.1–1.3 %; system-font fallbacks 4.7 %; the borderless button 2.4 %
(Apple's ImageRenderer paints a placeholder for it).

Cross-browser (same date): WebKit 36/36 exact frames, all pixels within 3 %; Firefox 35/36
exact frames (one text fixture at 3.5 % pixels from glyph hinting, so Firefox gets a 5 % bound).
The Counter smoke test (first paint, click, keyboard activation) passes in all three engines.

## Consequences
- The Inter-family fixture set (bundled font on both sides) is the path to exact browser text;
  planned for Phase 2.
- Metrics for unmeasured point sizes are interpolated and flagged approximate.
