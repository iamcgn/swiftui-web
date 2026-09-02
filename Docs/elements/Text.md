# Text (static), Font, text spacing

Apple docs: [Text](https://developer.apple.com/documentation/swiftui/text),
[Font](https://developer.apple.com/documentation/swiftui/font),
[LocalizedStringKey](https://developer.apple.com/documentation/swiftui/localizedstringkey).

## How Tier A stays exact

Text sizes are not computed on the headless side: `Fixtures/Goldens/text-metrics.json` records,
for every `(string, font, width)` in `Fixtures/Sources/TextMetrics/TextMetricsRequests.swift`,
the size and baselines Apple's SwiftUI produced, plus per-font spacing values. The
`RecordedTextEngine` replays them; a request that was never recorded fails the test with its key.
Fonts are keyed as `style:<name>[:w<weight>][:<design>][:italic]` or
`system:<size>:<weight>:<design>[:italic]` on both sides (`ResolvedFont.key`, `FixtureFont.key`).

## Measured behaviours (macOS 26.2, SwiftUI 7.2.5, goldens 2026-09-02)

| Behaviour | Value | Fixture |
|---|---|---|
| Default font (nothing set) | the 13 pt system font: 16 pt line, baseline 13 — **not** `.body` (decision 0010) | `text/hello`, every default-font fixture |
| `.body` line height | 18.5 pt (13 pt SF); `.system(size: 13)` is 16 pt: text styles carry their own leading | `text/styles`, `text/system-fonts` |
| Text-style sizes (macOS) | largeTitle 26, title 22, title2 17, title3 15, headline 13 bold, subheadline 11, body 13, callout 12, footnote 10, caption 10, caption2 10 medium | `text/styles` |
| `Text.bold()` / `Font.bold()` | a bold *trait* resolved per font: point-size and default font → bold (w700); `.body`, `.callout`, `.footnote`, `.subheadline`, `.title3`, `.caption2` → semibold (w600); `.largeTitle`, `.title`, `.title2` → bold; `.headline` → heavy (w800); `.caption` → medium (w500). `fontWeight(_:)` always wins | `text/modifiers`, `text/bold-trait` |
| Wrapped text width | the widest line **including its trailing space** (133.5 + 3.5 = 137 in a 150 frame); a line fits only if that width is within the proposal | `text/wrapped` |
| Multi-line pitch | 19 pt for `.body` (line height 18.5 rounded up) | `text/wrapped` |
| Minimum width (zero proposal) | widest word; recorded as the `|0.0|` entry | `text/hstack-baseline` |
| Horizontal spacing text↔text, text↔view | 8 pt (default category) | `text/hstack-spacing` |
| Vertical text→view spacing (body) | 11.1509 pt (`spacingBelow`, font-derived) | `text/vstack-spacing` |
| Vertical view→text spacing (body) | 6.2241 pt (`spacingAbove`) | `text/vstack-spacing` |
| Vertical text→text spacing | the **lower** run's `textToText` value: body 1.0, largeTitle 1.5, caption2 1.5, 20 pt monospaced 0 | `text/vstack-spacing`, `text/vstack-spacing-mixed` |
| Baseline of non-text views | bottom edge | `text/hstack-baseline` |

Spacing model (`ViewSpacing`): plain views declare the default category at 8 on all edges and
zero for `edgeBelowText` (top) / `edgeAboveText` (bottom); text declares `edgeBelowText` (bottom),
`edgeAboveText` (top) and `textToText` (top only) from its font, and the default category only
horizontally. Distance = max over categories both neighbours declare, 0 if none.

## Not yet covered

`lineLimit`, `multilineTextAlignment`, `truncationMode`, `lineSpacing`, `kerning`/`tracking`,
custom fonts, localization tables, `Text` concatenation with mixed styles, attributed strings,
`foregroundStyle` painting (step 7), browser measurement (step 10).
