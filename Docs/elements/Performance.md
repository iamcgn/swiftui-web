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
(the worst frame of a burst, a direction reversal, up to 130 ms); 500 rows scrolled in
8.3 ms median (`Playwright/scroll-probe.mjs`, 2026-09-05). The gate asks for a 40 ms median.

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
