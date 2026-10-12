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

## Open

Releasing lazy elements scrolled far away (Apple does), damage rects and content layer
caching for content in the thousands of rows, a smaller substrate (the text engine's tables
and the symbol metrics are the largest fixed costs), the first frame's full-page layout
(measuring only what the first viewport shows).
