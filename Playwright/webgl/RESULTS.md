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
