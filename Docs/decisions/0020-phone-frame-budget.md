# 0020 — The phone's frame budget is a layout budget; no GPU painter

Date: 2026-10-12
Status: accepted

## Context

The site felt choppy on a recent iPhone in Safari, and the question was whether a GPU painter
(WebGL or WebGPU instead of Canvas2D) would help. No measurement had ever been taken on a
phone: every "iPhone" number in `Docs/elements/ScrollView.md` was Playwright's device emulation
in headless Chromium on a laptop, where a scrolled frame took 4 ms.

`Playwright/device-perf.mjs` now drives Safari on the phone through safaridriver (Settings ›
Apps › Safari › Advanced › Remote Automation), with the host's scripted finger drag
(`__swiftuiwebDebug.drag`) and a frame split that separates the encode from the painter's own
Canvas2D loop (`framePhases().encode` / `.paint`) and records the gap between animation
frames. On an iPhone 17 the painter took 0–2 ms of a frame at DPR 3. The first frame took
5.8 s, a lazy grid scrolling in 2.8 s, and a plain scrolled frame 40–49 ms, all of it layout
and the display-list walk in wasm (`Docs/elements/Performance.md`, "On the device").

Two multiplications hid on the laptop:

- A stack's plan (its children's sizes and alignment guides for a proposal) was computed to
  size the stack, again to place it, and once more for every alignment guide its own container
  asked for; a guide query plans the child's subtree in turn. Only `sizeThatFits` was memoised,
  so the work grew with the nesting, and the landing page nests eight deep.
- A lazy element created inside a layout pass bumped the runtime's layout generation, which
  forgets every size memo on the page; `materializeLazyContent` does up to three passes.

The measuring session's engine runs a plain loop 25 times slower than this Mac's WebKit, in
JavaScript as in wasm (`__swiftuiwebDebug.bench`, the `?perf` HUD's last line), which is a
JavaScriptCore without its JIT. Whether that is the WebDriver session or the device's own
state is open until a by-hand tab reports its line; the proportions above do not depend on it.

## Decision

- No GPU painter. Safari rasterises Canvas2D fills, text and compositing on the GPU already;
  the painter is not where the phone's frame goes. The display list stays backend-neutral; a
  WebGPU painter is justified only if, on a device, the rAF gaps exceed one vsync while the CPU
  phases are under budget, or the painter's own loop exceeds 6 ms on plain fills and text.
- Layout memos are local: a stack's plan is memoised on its container per proposal, next to
  the size memo and cleared with it (`ViewNode.memoisedPlan`); a materialised lazy element
  forgets its own, its placeholders' and its ancestors' memos (`invalidateSizeMemosUpward`),
  never the generation. A text node keeps its parts and styled runs until its next update; a
  scroll view finds its lazy `ForEach`es once per layout; a gradient's subdivided stops are
  memoised by their resolved stops.
- Every performance claim about a phone comes from `device-perf.mjs` or the `?perf` HUD on the
  device, recorded in `Performance.md` with the engine-speed line beside it.

## Consequences

On the phone, through the same session: first frame 2.9 s, a grid scrolling in 0.33–0.45 s,
a scrolled frame 18–20 ms (layout 1, render 8–10, paint 0–1). On the laptop, a grid
scrolling in 130 → 25 ms, the first frame's layout 440 → 255 ms.

What remains is the display-list walk on scrolled frames (render), which a retained scroll
content layer would skip (the plan's step 2: `beginLayer` / `endLayer` ops, the host sending
only the layer's offset on a scroll-only frame), and the first frame's full-page layout.
Painter work from the plan (bounded offscreens for groups, backdrop blur without readbacks,
cached gradient text and tinted images) stays worthwhile for pages with materials and opacity
groups, but it is no longer the phone's problem.

A stored property added to `ViewNode` (`planCache`) or `TextNode` needs clean builds of the
root package and of each example's wasm scratch, as decision 0018 notes: a stale subclass
layout segfaults in the tests.
