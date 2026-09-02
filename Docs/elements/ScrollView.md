# ScrollView, ScrollViewReader, scroll modifiers, onChange

Apple docs: [ScrollView](https://developer.apple.com/documentation/swiftui/scrollview),
[ScrollViewReader](https://developer.apple.com/documentation/swiftui/scrollviewreader),
[ScrollViewProxy](https://developer.apple.com/documentation/swiftui/scrollviewproxy),
[scrollIndicators](https://developer.apple.com/documentation/swiftui/view/scrollindicators(_:axes:)),
[scrollDisabled](https://developer.apple.com/documentation/swiftui/view/scrolldisabled(_:)),
[scrollBounceBehavior](https://developer.apple.com/documentation/swiftui/view/scrollbouncebehavior(_:axes:)),
[scrollClipDisabled](https://developer.apple.com/documentation/swiftui/view/scrollclipdisabled(_:)),
[defaultScrollAnchor](https://developer.apple.com/documentation/swiftui/view/defaultscrollanchor(_:)),
[onChange](https://developer.apple.com/documentation/swiftui/view/onchange(of:initial:_:)-4psgg).

## API surface

| API | Notes |
|---|---|
| `ScrollView(_ axes: Axis.Set = .vertical, showsIndicators: Bool = true, content:)`, `axes`, `showsIndicators`, `content` | implemented |
| `ScrollViewReader { proxy in … }`, `ScrollViewProxy.scrollTo(_:anchor:)` | implemented; targets are `View.id(_:)` descendants of the scroll views under the reader, resolved at the next layout; never animated |
| `View.scrollIndicators(_:axes:)`, `ScrollIndicatorVisibility` (`automatic`, `visible`, `hidden`, `never`), environment `horizontal/verticalScrollIndicatorVisibility` | implemented: `hidden`/`never` suppress the overlay indicator; `visible` behaves like `automatic` (overlay only while scrolling) |
| `View.scrollDisabled(_:)`, environment `isScrollEnabled` | implemented (wheel, pan and momentum ignore the view; `scrollTo` still works) |
| `View.scrollBounceBehavior(_:axes:)`, `ScrollBounceBehavior` | stored in the environment, no effect: there is no rubber band yet |
| `View.scrollClipDisabled(_:)` | implemented |
| `View.defaultScrollAnchor(_:)` | implemented for the initial offset only (the `for:` role overload is missing) |
| `View.onChange(of:initial:_:)` (two-argument and zero-argument actions), deprecated `onChange(of:perform:)` | implemented: actions run after the update pass that changed the value, from the scheduler's action queue |
| `scrollPosition`, `scrollTargetLayout`, `scrollTargetBehavior` (paging, view-aligned), `contentMargins`, `scrollContentBackground`, `onScrollGeometryChange`, `onScrollPhaseChange`, `scrollIndicatorsFlash`, `scrollDismissesKeyboard`, `ScrollViewReader` inside `List` | missing |

## Runtime

`ScrollNode` (`Runtime/ScrollNodes.swift`) wraps the builder content in an implicit
`VStack` (the goldens show that arrangement for every axis set) and places it at
`-contentOffset`. Along a scroll axis the node proposes nothing to the content and takes the
proposal itself; across it the proposal passes through and the node is exactly as large as its
content. The offset is clamped to `[0, content − viewport]` at every layout, so content that
shrinks pulls the offset back. `scrollTo` records a target; the next layout places the content,
reads the target's fresh frame, computes the offset and places the content again when it moved.

Input is entirely in Swift (decision 0002). `Runtime.scrollWheel(by:at:)` walks the scroll views
on the hit path innermost first and lets each consume what it can along its axes; the remainder
chains outward. Desktop wheel deltas already carry the OS momentum, so none is added. A touch
pointer becomes a pan after `panSlop` (10 pt); a pan cancels the pending press and follows the
finger, and lifting hands the smoothed velocity to the innermost scroll view, which decelerates
at UIScrollView's normal rate (× 0.998 per millisecond) and stops at the edges. The host
(`CanvasHost`) normalises `deltaMode` (lines × 16, pages × viewport), consumes the wheel event so
the page does not scroll, and calls `advanceScrollAnimations` once per frame for momentum and
the indicator fade. Every scroll runs a full layout pass; there is no offset-only fast path yet
(see the frame-time measurement below).

Overlay scrollers are painted by the node while `indicatorOpacity > 0`: a knob on the trailing
edge whose length is the viewport's share of the content, held 0.6 s after the last scroll and
faded over 0.25 s. The goldens never show one (macOS renders overlay scrollers only while
scrolling), so the geometry is approximate and marked unverified in `PlatformMetrics`.

## Measured behaviours (macOS 26.2, SwiftUI 7.2.5, hosted-window goldens 2026-09-02)

| Behaviour | Value | Fixture |
|---|---|---|
| Size along a scroll axis | the proposal: 200 tall in a 300 × 200 window (vertical), 300 wide (horizontal), 300 × 200 for both axes | `scroll/vertical`, `scroll/horizontal`, `scroll/both` |
| Size across the scroll axis | **exactly the content's size**, never the proposal: 120 for 120 pt rows (centred at x 90 by the window), 100 inside a 250 × 150 frame (x 100), **400** for 400 pt content in a 300 pt proposal (x −50, overflowing the window), 274 for a wrapped paragraph, 152 for padded rows, 40 tall for a horizontal row of 40 pt cells | `scroll/narrow-content`, `scroll/wide-content`, `scroll/text`, `scroll/padding`, `scroll/horizontal` |
| Proposal to the content | across: the scroll view's proposal (the paragraph wraps at 300 → 274 × 32); along: nothing (ideal length: 552, 808, 400) | `scroll/text`, `scroll/vertical-overflow`, `scroll/horizontal`, `scroll/both` |
| Content placement | top-leading at offset 0; content shorter than the viewport is not centred (3 rows at y 0 in a 200 pt viewport) | `scroll/vertical`, `scroll/horizontal` |
| Several views in the builder | an implicit `VStack` with default spacing and centre alignment for **both** vertical and horizontal scroll views: `Text` / 60 × 30 `Color` / `Text` stack at y 0, 24.15, 58.89 (default-font text-to-colour spacing 8.15 and 4.74), texts centred over the 60 pt colour (x 18.75); the horizontal scroll view is 74.89 tall | `scroll/children` |
| In a stack | flexible like `Color`: `VStack(spacing: 0) { Text; ScrollView; Text }` in 200 pt gives 16 / 168 / 16 | `scroll/in-stack` |
| Padding inside | part of the content size (152 × 432 for 120 × 400 rows) | `scroll/padding` |
| `defaultScrollAnchor(.bottom)` | initial offset = content − viewport (content at y −200 for 400 in 200) | `scroll/anchor-bottom` |
| `scrollTo` without an anchor | the smallest offset change that shows the whole target: a row below the fold ends up bottom-aligned (row 15 at y 180, offset 120); a row above the top ends up at y 0 | `scroll/scroll-to` (`row15`, `row0`) |
| `scrollTo` with an anchor | the target's anchor point meets the viewport's: `.top` puts row 3 at y 0 (offset 60); `.center` puts row 10 (200–220) at y 90 (offset 110) | `scroll/scroll-to` (`row3-top`, `row10-center`) |
| `showsIndicators: false`, `scrollIndicators(.hidden)`, `scrollDisabled(true)` | no effect on layout (80 × 200 either way) | `scroll/modifiers` |
| Indicators at rest | none painted in any golden, including right after a programmatic scroll (overlay scroller style) | every scroll fixture's `image@2x.png` |

## Scrolling frame time (Chromium, `Playwright/scroll-probe.mjs`, 2026-09-02)

Every scrolled frame runs a full layout pass and repaints everything, measured by the host's
own clock (`__swiftuiwebDebug.frameMillis()`) while 40 px wheel ticks arrive once per frame:

| Content | Build | Layout + paint per frame |
|---|---|---|
| `scroll/long`, 500 rows | release (`-Osize`) | median 8.3 ms, p90 8.7 ms, max 10.3 ms |
| `scroll/long`, 500 rows | debug | median 23.8 ms, p90 24.9 ms |
| `scroll/vertical-overflow`, 20 rows | debug | median 3.5 ms, p90 5.0 ms |

About 15 µs per row in release, so a few hundred simple rows stay inside a 60 Hz frame and a
few thousand do not; that is the trigger for an offset-only repaint path and content layer
caching (open below). The probe also checks that a real wheel event is consumed by the canvas
(the page does not scroll), that the offset clamps at 0 and that the indicator has faded 1.2 s
after the last tick. Note that headless Chromium delivers `mouse.wheel(0, 40)` as `deltaY: 20`
at device scale factor 2.

## Fidelity

Tier A: all 14 fixtures exact, including the 4 `scroll/scroll-to` steps. Tier B: Chromium 17/17
renders (frames exact, pixels ≤ 0.63 %), WebKit 17/17 (≤ 0.2 %), Firefox 17/17 (worst 1.09 % on
`scroll/text`, the usual glyph-hinting class).

## Open

- Rubber band / bounce and `scrollBounceBehavior`; keyboard scrolling (arrows, page, home/end);
  hover-expanding legacy scroller; indicator geometry verified against a screen recording.
- `scrollPosition`, `scrollTargetLayout` / `scrollTargetBehavior` (paging, view-aligned),
  `contentMargins`, `onScrollGeometryChange`, `onScrollPhaseChange`, animated `scrollTo`.
- Which scroll view a nested `scrollTo` should pick (structural order today, outermost first).
- Lazy stacks; an offset-only repaint path, damage rects and content layer caching once a
  measurement shows the full layout pass per scrolled frame is the bottleneck.
