# Performance (pf-perf, 2026-10-12)

What the bundles cost to load and to scroll, measured where the numbers come from, and the
gate that keeps the landing page within budget. Earlier notes on frame phases, the loading
screen and the size trials are in the roadmap (Phase 7, 2026-09-05) and decision 0017.

## Bundles (release wasm, 2026-10-12, Swift 6.3.3)

| Bundle | raw | gzip (what Pages serves) | brotli |
|---|---|---|---|
| Examples/Landing | 11.19 MB | 4.03 MB | 2.86 MB |
| Examples/Progress | 11.19 MB | 4.02 MB | 2.86 MB |
| Examples/Counter | — | — | 2.84 MB (gate 3 MB, decision 0006) |
| Examples/Gallery | 14.3 MB | — | 3.53 MB (gate 4 MB) |

A 1.6 Mbps connection (a slow mobile link) spends about 21 s on the landing page's gzip
download; the loading bar in `index.html` tracks it against `data-wasm-bytes`. The size is
the substrate's code (decision 0017 took FoundationEssentials out; LTO is not available to the
wasm SDK), so the first frame on a slow connection is a download problem, not a frame one.

## First frame

Once the resources are in, the landing page's first frame takes about 550 ms on a laptop
(the wasm's instantiation and the first layout and paint, 450 ms of it the frame: the whole
page is laid out, every heading and paragraph measured), the progress page about 850 ms. The
gate asks for 3 s (a CI runner is several times slower).

## Scrolling

A wheel burst over the landing page lays out and paints a frame in 7 ms median on a laptop
(the worst frame of a burst, a direction reversal, up to 130 ms — the lazy grids scrolling in,
25 ms since 2026-10-12); 500 rows scrolled in 8.3 ms median (`Playwright/scroll-probe.mjs`,
2026-09-05). The gate asks for a 40 ms median.

## On the device (iPhone 17, iOS 27.0, Safari through safaridriver, 2026-10-12)

The first numbers from a phone, `Playwright/device-perf.mjs` over the landing page at
402 × 714 pt, DPR 3 (a 1206 × 2142 canvas). The measuring session is a WebDriver one, and
on it the engine runs the same loop about 25 times slower than this Mac's WebKit in both
JavaScript and wasm (200 ms against 7 ms for `__swiftuiwebDebug.bench`'s 5 M iterations): a
JavaScriptCore without its JIT. A tab opened by hand on the same phone runs the loop in 8 ms
(wasm 8 ms), so the session's absolute times are 25 times the real ones; the proportions
hold, and the script prints the engine line so a JIT-less session is never mistaken for the
device. By hand, after the fixes below: a scrolled frame 4 ms median, 7 ms p90, 8 ms worst,
none over 16 ms, no animation-frame gap over 25 ms (the `?perf` HUD, 120 frames).

| | first frame | a lazy grid scrolling in (full layout) | scrolled frame (p50) | of which layout / render / paint |
|---|---|---|---|---|
| before | 5.8 s | 2.8 s | 40–49 ms | 10 / 17–28 / 0–2 |
| stack plans memoised, lazy elements invalidate locally (`9661ef3`) | 3.8 s | 0.44–0.59 s | 38–49 ms | 10 / 17–28 / 0–2 |
| text parts, lazy providers and gradient stops cached (`2513c75`) | 2.9 s | 0.33–0.45 s | 18–20 ms | 1 / 8–10 / 0–1 |

What the phone said that the laptop had not: the painter costs 0–2 ms of a frame at DPR 3,
and the time is layout and the display-list walk, in wasm. Two layout costs were multiplied
by the page's nesting: a stack planned its subtree once to size, once to place and once more
for every alignment guide its container asked for, and a lazy grid scrolling in bumped the
layout generation, re-measuring the whole page three passes over. `?perf` on any page shows
the frame-time HUD with the engine-speed line; `performance.mark` phases appear in Safari's
timeline when the inspector is attached.

The same drags on this Mac (Playwright, iPhone 14 emulation, release): a scrolled frame
4 ms in Chromium and WebKit; the first frame's layout 440 → 255 ms; a grid scrolling in
130 → 25 ms.

## Laziness

`LazyVStack`, `LazyHStack` and the lazy grids create a `ForEach`'s elements as they come
within a viewport of the visible region (`Docs/elements/Lazy.md`, 2026-09-19). `List` rows are
lazy the same way since 2026-10-12: a `ForEach` in a list creates rows a viewport ahead and
keeps placeholders sized by the created rows for the rest (a thousand-row list in a 100 pt
viewport creates about ten; `scrollTo` creates its target where its placeholder sits;
`ListLooksTests.rowsAreCreatedLazily`). Rows are kept once created. UIKit's `UITableView` and
`UICollectionView` recycle their cells as UIKit does. Static children and `ForEach` outside
scroll views stay eager.

## The gate (`scripts/frame-budget.sh`, CI's browser job)

Builds Examples/Landing in release, serves it and runs `Playwright/frame-budget.mjs`: the
first frame within 3 s of the resources arriving (`FIRST_FRAME_MS`), scroll frames at a 40 ms
median (`FRAME_MS`); it prints the gzip size and what a 1.6 Mbps connection would add.
`Playwright/landing-perf.mjs` keeps the CPU profile for digging.

## A real app's frames (Ember, 2026-10-25)

Ember (decision 0021) at a phone viewport in the installed Chrome on this Mac, release build,
`?platform=ios`, every frame's phases read in the page as `frameCount()` advances
(`Playwright/ember-perf.mjs`; the numbers are the host's `framePhases()`, which now also say
why the frame laid out — `reason` — with the pass's `measures` and `computes`). Before: a scrolled
frame of the feed was 80 ms, of a comment thread 125 ms; a lazy row materialising in the
thread took 190–390 ms, a full layout of it 1.5 s. After: 18 and 13–18 ms, 45 ms, 112 ms.
What it was, in order of size:

- **Every scrolled frame was a full layout with every memo dropped.** Ember's "loading more"
  footer spinner subscribed to frames and called `setNeedsDisplay()` each tick — a layout
  request that invalidates every memoised size. A spinner's tick is a repaint
  (`requestRepaint`); so are a text selection change, a new frame subscriber and an animation
  in flight (the tweens are read when painting). With that, scroll frames take the
  move-content path (`reason: moved`) at render + paint cost.
- **A lazy stack distributed its height.** `LazyVStack` was a `VStack` in a frame; placed by
  `.frame(maxWidth:)` at its own ideal height, the `VStack` handed each row a share of what its
  siblings left — a different fractional height per row, per pass and per change of a
  sibling's size, which no memo matches, and a short row stretched to its share. Every
  materialised row measured its whole subtree again for the new number: 244 000
  recomputations a pass, one leaf computed for 1 113 distinct proposals. A lazy stack proposes
  nothing along its axis (`fixedSize`), as SwiftUI's does (a `Spacer` in one takes its
  minimum). The same share problem is cut off in every stack: a child of one size (zero and
  infinite answers equal) or a bounded one offered at least its maximum takes the infinite
  probe's answer without a probe for the share (`StackLayout.distribute`).
- **Any update dropped every memo.** The layout generation moved on with every pending
  update, so a favicon arriving in one row re-measured the screen. Now an updated node
  forgets its own sizes and its ancestors' as its view or environment is assigned, and the
  bump is kept for what no view value shows (a resize, an animation beginning, an image,
  catalog or symbol table arriving). Ember's updates re-evaluate whole screens whose view
  values hold closures, so they still re-measure that screen (60–100 ms); a member-by-member
  comparison that would tell equal closures apart cost more in reflection than it saved.
- **Paint: full-canvas blurs and shadows.** A material bar's backdrop blur copied, blurred
  and read back the whole canvas (two bars, 30 ms a frame at DPR 2); it works on the strip
  under its path now. Shadows, opacity, blend and mask groups drew a canvas-sized offscreen
  back whole, so a shadow's blur was computed over 780 × 1688 pixels; the painter tracks the
  device box each group's ops painted and composites that. Thread paint 28 → 6 ms.

What remains there: a full layout of a screen costs ~10 µs a measurement (the thread's
8 300 recomputations are 112 ms; the feed's 5 000, 60–70 ms), which an update of a whole
screen pays; the onboarding's shimmer (masked, blended gradients every frame) paints at
~55 ms; and the navigation transition's frames paint both screens.

### Safari: the blur without a canvas filter (2026-10-28)

The numbers above are Chromium's, and on the phone Ember was still seconds a frame
(Corey's recording: the onboarding's page transition sat at one offset for whole seconds).
The same frames in WebKit (`ENGINE=webkit`, Playwright's build; `Playwright/ember-perf.mjs`
takes the engine from that variable) painted at a flat **430 ms**, whatever they drew, and
no canvas call accounted for it: the painter's JavaScript Gaussian did. WebKit's 2D context
has no `filter` — not an attribute that does nothing, no attribute at all; the probe that
assigned `blur(1px)` and read it back was fooled by its own expando, which is why the HUD
said `filter yes` — so every blur ran the per-pixel kernel: 2 (6σ + 1) taps a pixel, σ 40
over a 780 × 342 strip at DPR 2 for each material bar, 210 ms a bar; σ 60 over 1 206 wide
on the phone at DPR 3, two thousand million multiplies a bar, two bars a frame.

The fallback now draws the box down by k = ⌊σ / 4⌋ (at most 8), blurs the small image by
three box passes each way (a running sum a pixel, whatever the σ; Kovesi's box widths), and
draws it back up smoothed into a fresh offscreen, as the native path does. A mean 1–4/255
from Chrome's native filter over a feed's strip, 6 ms for the strip at any σ (30 ms at σ 2,
where nothing is drawn down). The probe draws a dot through the filter and reads a
neighbour. WebKit's Ember paint: 420 → 7–11 ms a frame, the same as Chrome's; the frames
Corey saw are the HUD's business now, not the painter's.

## Open

Releasing lazy elements scrolled far away (Apple does), damage rects and content layer
caching for content in the thousands of rows, a smaller substrate (the text engine's tables
and the symbol metrics are the largest fixed costs), the first frame's full-page layout
(measuring only what the first viewport shows), the cost of one measurement (a release
profile with names: the release wasm has no name section and its DWARF no addresses).
