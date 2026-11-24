# WebGL painter experiment: results (Nov 24, 2026)

A WebGL2 painter (`painter-gl.js`) that draws every display-list op, injected beside the bundle
(the wasm is unchanged), compared with today's Canvas2D painter. CI runs Chromium on Linux,
where WebGL is SwiftShader (software Vulkan through ANGLE) and Canvas2D is software raster too,
so the timings below say nothing about a real GPU.

- Correctness: 724 of 725 gallery renders within 3% of Canvas2D (Tier B tolerance); worst
  effects/shadow-profile 3.2%. Against the goldens both painters land 277-278 of 754.
- Apps (probe screenshots, GL vs 2D): Buttoncraft, Charts, SimpleScores, SimpleToDo pass with
  every screen within 3%; Ember's 15 screens within 0.2% (its live feed timed out in both modes);
  Scrumdinger's probe timed out in both modes.
- Text: drawn with Canvas2D into textures, so glyphs match (text-heavy screens differ 0.01-0.2%).
- Fallback: WebGL off or unavailable falls back to Canvas2D on the first frame.
- Size: painter-gl.js 92,147 bytes, 21,519 brotli, beside the bundle.
- Speed on SwiftShader, same frame x30: Canvas2D 0.1-5 ms for most screens, WebGL 28 ms-2.2 s;
  Ember 190 ms vs 4.8 s. Needs a real GPU to judge.

## On a real GPU (Corey's M1 Pro Mac, Nov 24, run 45323269954)

Headless Chromium 129, WebGL2 on ANGLE (Apple M1 Pro). Same frame drawn 30 times, median:

| screen | ops | Canvas2D | WebGL |
| --- | --- | --- | --- |
| Ember (live feed) | 19,300 | 38.3 ms | 8.0 ms |
| Buttoncraft | 2,459 | 11.6 ms | 2.4 ms |
| SimpleScores / SimpleToDo | ~650 | 9.7 ms | 2.1-2.2 ms |
| Scrumdinger | 295 | 6.6 ms | 2.1 ms |
| Swift Charts Examples | 11,526 | 3.7 ms | 3.9 ms |
| Counter | 56 | 0.9 ms | 2.5 ms |
| small gallery fixtures | 100-1,000 | 0.1-0.3 ms | 0.7-1.3 ms |

- Scrolling, whole frame median: Ember 109 -> 82 ms, Buttoncraft 19 -> 11 ms, Charts 13 -> 16 ms.
- WebGL wins on busy screens and costs about 1 ms of fixed overhead on simple ones.
- Caveat: headless Canvas2D may not be GPU-rasterized, so Canvas2D could be faster in a
  normal Chrome window; worth one headed check before adopting.
