# Text, Font, text spacing, wrapping, line limit, truncation, alignment

Apple docs: [Text](https://developer.apple.com/documentation/swiftui/text),
[Font](https://developer.apple.com/documentation/swiftui/font),
[LocalizedStringKey](https://developer.apple.com/documentation/swiftui/localizedstringkey),
[lineLimit](https://developer.apple.com/documentation/swiftui/view/linelimit(_:)-513mb),
[lineLimit(_:reservesSpace:)](https://developer.apple.com/documentation/swiftui/view/linelimit(_:reservesspace:)),
[multilineTextAlignment](https://developer.apple.com/documentation/swiftui/view/multilinetextalignment(_:)),
[truncationMode](https://developer.apple.com/documentation/swiftui/view/truncationmode(_:)),
[lineSpacing](https://developer.apple.com/documentation/swiftui/view/linespacing(_:)),
[Text.TruncationMode](https://developer.apple.com/documentation/swiftui/text/truncationmode),
[TextAlignment](https://developer.apple.com/documentation/swiftui/textalignment).

## API surface

| API | Notes |
|---|---|
| `Text(verbatim:)`, `Text(_: StringProtocol)`, `Text(_: LocalizedStringKey)` with interpolation | implemented; localization is identity |
| `Text` modifiers `font`, `fontWeight`, `bold`, `italic`, `foregroundColor`, `foregroundStyle` | implemented; `foregroundStyle` accepts colours only |
| `Text + Text` | implemented: parts keep their own font, weight, traits and colour; the whole text's modifiers and the environment fill in what a part does not set (`text/concatenation`) |
| `View.lineLimit(Int?)`, `lineLimit(...n)`, `lineLimit(n...)`, `lineLimit(a...b)`, `lineLimit(_:reservesSpace:)` | implemented; environment `lineLimit` plus a package `minimumLines` (reserved lines) |
| `View.multilineTextAlignment(_:)`, `TextAlignment` | implemented (painting only; sizes do not change) |
| `View.truncationMode(_:)`, `Text.TruncationMode` | implemented: head, middle, tail |
| `View.lineSpacing(_:)` | implemented |
| `View.allowsTightening`, `minimumScaleFactor` | environment values stored, not applied |
| `kerning`, `tracking`, `baselineOffset`, `underline`, `strikethrough`, `Text.Case`, `AttributedString`, `Text(Date…)`, `Text(Image)`, `textSelection` | missing |

## How Tier A stays exact

Text sizes are not computed on the headless side: `Fixtures/Goldens/text-metrics.json` records,
for every request in `Fixtures/Sources/TextMetrics/TextMetricsRequests.swift`, the size and
baselines Apple's SwiftUI produced, plus per-font spacing values. The `RecordedTextEngine` replays
them; a request that was never recorded fails the test with its key. Keys are
`<font>|<width>[;l<lineLimit>][;r<minimumLines>][;s<lineSpacing>][;t<head|middle>]|<string>`
(`TextMetricsKey` / `TextMetricRequest.key`), where `<font>` is
`style:<name>[:w<weight>][:<design>][:italic]` or `system:<size>:<weight>:<design>[:italic]`
for one font and `rich:<font>=<count>,…` for a concatenation with several fonts (parts in the
same font are merged; colours do not affect measurement). Rich requests also record each part
alone, which is how the headless engine positions the parts when it paints.

The browser engine (`Canvas2DTextEngine`) measures advances with `measureText` and applies the
rules below through `TextLayouter`, which native tests cover with a synthetic measurer
(`TextLayoutTests`).

## Measured behaviours (macOS 26.2, SwiftUI 7.2.5, hosted-window goldens 2026-09-02)

| Behaviour | Value | Fixture |
|---|---|---|
| Default font (nothing set) | the 13 pt system font: 16 pt line, baseline 13 — **not** `.body` (decision 0010) | `text/hello`, every default-font fixture |
| `.body` line height | 18.5 pt (13 pt SF); `.system(size: 13)` is 16 pt: text styles carry their own leading | `text/styles`, `text/system-fonts` |
| Text-style sizes (macOS) | largeTitle 26, title 22, title2 17, title3 15, headline 13 bold, subheadline 11, body 13, callout 12, footnote 10, caption 10, caption2 10 medium | `text/styles` |
| `Text.bold()` / `Font.bold()` | a bold *trait* resolved per font: point-size and default font → bold (w700); `.body`, `.callout`, `.footnote`, `.subheadline`, `.title3`, `.caption2` → semibold (w600); `.largeTitle`, `.title`, `.title2` → bold; `.headline` → heavy (w800); `.caption` → medium (w500). `fontWeight(_:)` always wins | `text/modifiers`, `text/bold-trait` |
| Line breaking | greedy, after spaces; a line fits if its **drawn** width is within the proposal, its trailing space hangs (133.5 keeps "Layout must wrap this", 133.34 drawn, on one line; 133 wraps it). Probed with a hosted `NSHostingView` sweep at 0.5 pt steps, 60–445 pt | `text/paragraphs` (`hanging`), `text/wrapped` |
| Two-line paragraphs never end in a lone word | when a paragraph wraps to exactly two lines and the second holds one word, the first line's last word moves down **if that makes the two widths more even and still fits**: "Layout must wrap" at 75–107 pt is "Layout" / "must wrap" (not "Layout must" / "wrap"); the paragraph at 397–439 pt is "…inside a" / "narrow frame." (355.5 wide, not 400); but "Layout wrap sentence" at 89–129 pt keeps "sentence" alone (pushing "wrap" would make 40.6 / 89 less even than 74 / 55.5). Three or more lines are plain greedy ("frame." stays alone at 100 and 201 pt); each `"\n"` paragraph is balanced on its own | `text/wrapped` (`free`), `text/paragraphs` (`twoWrapped`), sweep 2026-09-02 |
| Reported width of a wrapped line | drawn width **plus the trailing space**, capped at the proposal: 137 in a 150 frame, 134 in a 134 frame | `text/wrapped`, `text/paragraphs` |
| Paragraph at 100 / 120 / 150 / 200 / 300 (default font) | 6 / 4 / 4 / 3 / 2 lines, 95.5 / 118 / 137 / 196.5 / 274 wide | `text/paragraphs`, `text/wrapped` |
| Word wider than the proposal | wraps by character: "Supercalifragilistic" (112) in 60 → 2 lines, 56.5 wide; a zero proposal gives one character per line and reports width 0 | `text/paragraphs` (`longWord`), `|0.0|` recordings |
| Multi-line pitch | per font, recorded as `linePitch` (13 lines of "Hg"): 16 for the default font, 19 for `.body` (single line 18.5), 33 `.title`, **39** `.largeTitle` (single line 38), **27** `.title2` (25.5), 18 `.callout`, 24 for 20 pt; point-size fonts have pitch = line height | `text/wrapped`, `text/paragraphs` (`titleWrap`), `fonts` in text-metrics.json |
| `lineSpacing(s)` | pitch = `max(linePitch, unroundedLineHeight + s)`, where the unrounded height is the font's own (16 default, 18.333 `.body`, 32.917 `.title`, 37.625 `.largeTitle`, 25 `.title2`, 17.125 `.callout`, 24 for 20 pt): default 4 lines 64 → 76 (`s = 4`) → 94 (`s = 10`); `.body` 75.5 → 85.5 (`s = 4`, pitch 22.333) but unchanged for `s ≤ 0.5`; `.largeTitle` unchanged for `s ≤ 1`; a single line is unchanged | `text/line-spacing`, spacing sweep 2026-09-02 |
| `"\n"` | forces a break; the text is as wide as its widest line ("Left\nRight side" 60.5 × 32) | `text/alignment` (`newline`), `text/paragraphs` (`two*`) |
| `lineLimit(n)` | at most `n` lines; the last permitted line is truncated with "…" at **character** granularity ("lines inside a narrow fr…" is 147 wide); spaces next to the ellipsis are dropped ("Layout must wrap this…" is 144, not 147.5); a limit above the line count changes nothing | `text/line-limit` |
| `lineLimit(...n)` | the upper bound only, as `lineLimit(n)` | `text/line-limit` (`upTo2`) |
| `lineLimit(a...b)`, `lineLimit(a...)`, `lineLimit(n, reservesSpace: true)` | the lower bound / `n` reserves lines: "Hello" is 32 tall with `2...4` or `2, reservesSpace: true`, 48 with `3...`; the **last baseline stays on the real last line** (13) | `text/line-limit` (`reserved2`, `range2to4`, `atLeast3`) |
| `truncationMode` | `.head` "…inside a narrow frame." (145), `.middle` "Layout mus…rrow frame." (150), `.tail` "Layout must wrap this…" (144) in a 150 frame with `lineLimit(1)`; with `lineLimit(2)` only the second line is truncated | `text/truncation` |
| `multilineTextAlignment` | sizes and frames are identical for leading / center / trailing; lines are shifted within the text's own width by their drawn width (trailing spaces hang); single-line text is unaffected | `text/alignment` (Tier B pixels) |
| Concatenation with mixed fonts | one paragraph: "Big " (`.largeTitle`) + "small" is 74 × 38 with baseline 29 — the line takes the tallest run's line height and baseline; parts wrap across lines as one text (142.5 × 64 at 150) | `text/concatenation` |
| Concatenation inheritance | `(Text("Env ") + Text("bold").bold())` under `.font(.title)`: both parts title, the second w700; `(Text("Title ") + Text("italic").italic()).font(.title)` 90 wide | `text/concatenation` (`envBold`, `titleItalic`) |
| Baselines of wrapped text | `firstTextBaseline` = first line's, `lastTextBaseline` = last line's (61 for 4 default-font lines); a `.frame` forwards them | `text/baseline-wrapped`, `text/hstack-baseline` |
| Minimum width (zero proposal) | recorded as the `|0.0|` entry (one character per line) | `text/hstack-baseline` |
| Horizontal spacing text↔text, text↔view | 8 pt (default category) | `text/hstack-spacing` |
| Vertical text→view spacing (body) | 11.1509 pt (`spacingBelow`, font-derived) | `text/vstack-spacing` |
| Vertical view→text spacing (body) | 6.2241 pt (`spacingAbove`) | `text/vstack-spacing` |
| Vertical text→text spacing | the **lower** run's `textToText` value: body 1.0, largeTitle 1.5, caption2 1.5, default font 0 | `text/vstack-spacing`, `text/vstack-spacing-mixed` |
| Baseline of non-text views | bottom edge | `text/hstack-baseline` |

Spacing model (`ViewSpacing`): plain views declare the default category at 8 on all edges and
zero for `edgeBelowText` (top) / `edgeAboveText` (bottom); text declares `edgeBelowText` (bottom),
`edgeAboveText` (top) and `textToText` (top only) from its font, and the default category only
horizontally. Distance = max over categories both neighbours declare, 0 if none. A concatenation
uses its first part's font for spacing (unverified for mixed fonts).

## Height pressure (measured 2026-09-04, applied 2026-09-05)

A `Text` proposed less height than its lines need keeps `floor(height / line pitch)` lines, at
least one, and tail-truncates the last: the paragraph at 110 pt (five lines, 80 pt) keeps one
line in an 8 or 20 pt frame, two at 32 and 40, three at 48, four at 70 (`pressure/heights`); a
stack taller than its window squeezes its text the same way (`pressure/overflow`: the window's
120 pt leave 24 for the text, one line; `pressure/alone25` and `alone45` keep one and two lines).
`TextNode.textLayout(width:height:)` applies the rule to `sizeThatFits`, `dimensions(in:)` and
painting; a zero-height proposal (a stack's minimum-size probe) yields one line by trimming the
natural layout arithmetically, so the recorded engine sees no extra keys, while positive proposals
lay the kept lines out for real with the ellipsis (keys carry `;lN`).

Honouring height proposals exposed how stacks share height with texts, measured on the
`pressure/*` stack fixtures (Docs/elements/Layout.md): a `Spacer` stands aside with its minimum
reserved while the other children take equal shares in flexibility order, then the spacers split
what is left (`pressure/stack-spacer-*`, `spacer-min0/min30/roomy`); two texts of different
flexibility give the less flexible one its share first (`two-texts`, `two-texts-swapped`); equal
texts split evenly (`three-texts`: 32/32/32 in 100 pt); a row squeezes the same way
(`row-tight`). 15 fixtures exact in Tier A and Tier C.

## Open

- **`textScale`**: see `Docs/elements/TextScale.md`.
- **Height pressure with mixed fonts**: the kept-line count uses the first part's pitch; a concatenation mixing text styles under pressure is unverified.