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
| `View.allowsTightening`, `minimumScaleFactor` | implemented (2026-10-03, approximate): a line that would be truncated first closes its letter spacing by what it needs up to a 72nd of the font size per character (else truncates with that tightening, holding one more character), then shrinks its fonts to the largest scale down to the minimum at which nothing is truncated, and truncates at the minimum (`text/fit`; Tier A exact through the recorded metrics, pixels within the loosened bound) |
| `kerning`, `tracking`, `baselineOffset`, `underline`, `strikethrough`, `Text.Case` | implemented (2026-09-04, `Docs/elements/TextStyle.md`: `textstyle/*`) |
| Markdown in literals: `**bold**`, `_italic_`, `***both***`, `` `code` ``, `~~struck~~`, `[text](url)`, backslash escapes | implemented (2026-10-03, `text/markdown`): a `LocalizedStringKey` literal is parsed by `_InlineMarkdown` (WebFoundation); bold is the bold weight, italic the trait, code the monospaced design, a link the accent colour and a press target; `Text(verbatim:)` and string values stay literal |
| `Text(AttributedString)`, `AttributeScopes.SwiftUIAttributes` (`font`, `foregroundColor`, `backgroundColor`, `underlineStyle`, `strikethroughStyle`, `baselineOffset`, `kern`, `tracking`), Foundation's `link` and `inlinePresentationIntent` | implemented (`text/attributed`): each run becomes a part with those modifiers; on wasm `WebFoundation` stands in for `AttributedString` (`init(markdown:)` included); `kern`/`tracking` on a run apply to the whole text; `backgroundColor` is read but not painted |
| `Text(Image)` | implemented (`text/inline-image`): a system image lays out as a glyph the symbol's width on the baseline (the line grows to the symbol's height); other images take no space |
| `Text(_ date: Date, style:)`, `Text.DateStyle` (`date`, `time`, `relative`, `offset`, `timer`) | implemented (`text/dates`): `date` and `time` in English in the environment's time zone ("May 28, 2026", "8:26 PM" with a narrow no-break space); the live styles re-resolve every second against now (approximate wording: "2 hours", "+2 hours", "1:23:45") |
| `Text(_:format:)` | implemented for any `FormatStyle` producing a string (numbers on wasm through `WebFoundation`; dates on Apple platforms through Foundation) |
| `Link` inside text | implemented: a link part paints in the accent colour, shows the hand and opens through `openURL` on press (the text takes presses only where it has links) |
| `Text(DateInterval)`, `Text(ClosedRange<Date>)`, `Text(_: Duration)`, `textSelection` | missing (`textSelection` is accepted; `Docs/elements/TextScale.md`) |

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

## Fitting (macOS 26.6, `text/fit`, 2026-10-03)

"The quick brown fox" (13 pt, 124 wide) in narrowing frames with `lineLimit(1)`.

| Modifier | Frame | Result | Reading |
|---|---|---|---|
| `minimumScaleFactor(0.5)` | 120 | 118.5 × 15, baseline 12 | shrunk to about 0.95: the fitted width stays a little under the frame, so the scale is found by a search rather than the ratio |
| | 100 | 100 × 13, baseline 10 | about 0.81 |
| | 80 | 78 × 9, baseline 7 | about 0.63 |
| | 60, 40 | 60 × 8, 38 × 8 | the minimum (6.5 pt, an 8 pt line), then truncated with an ellipsis |
| `minimumScaleFactor(0.8)` | 100 | 99 × 13 | the minimum (10.4 pt) fits |
| | 80, 60 | 77.5 × 13, 58 × 13 | truncated at the minimum |
| `minimumScaleFactor(0.5)`, no limit | 80 | 63 × 32 | wraps instead of shrinking (nothing is truncated) |
| `lineLimit(2)`, `minimumScaleFactor(0.5)` | 60 | 60 × 32 | two lines fit: no shrinking |
| `.title`, `minimumScaleFactor(0.5)` | 100 | 96 × 17 | truncated at about 0.63, not at the minimum: SwiftUI's search gives up above it (ours truncates at the minimum, 14 tall) |
| `allowsTightening(true)` | 116, 112, 108, 100 | 116, 108.5, 101, 91 (plain truncation: 111, 111, 103.5, 93.5) | never fits the whole text (it would need 0.42 pt per character): each line holds one more character than plain truncation and is 2.5 pt narrower, a tightening of about 0.18 pt (a 72nd of the size) per character |
| `allowsTightening`, `minimumScaleFactor(0.5)` | 100 | 100 × 13 | shrinking takes over once tightening cannot fit |
| paragraph, `lineLimit(2)`, `allowsTightening` | 150 | 149.5 × 32 | the truncated last line holds more ("…several li…" for "…this…") |

Implementation (`TextLayouter.layout`): the plain layout first; when it truncates and tightening
is allowed, the single-line case tries the exact tightening it needs (if ≤ 1/72 em per
character), else the maximum tightening is applied and the line truncates; then, with a
minimum scale below 1, a five-step bisection of the scale between the minimum and 1 keeps the
largest layout that is not truncated (the fonts of every run scaled, the metrics of the scaled
sizes), or the layout at the minimum, truncated. The layout carries `scale` and `tightening`
so the painter draws the scaled fonts with the closed-up letter spacing. The recorded engine
keys both options (`;m0.5`, `;tt`), so Tier A is exact; Tier B and C hold the fixture's frames
to 10 % and its pixels to the looser bound: CoreText and Canvas2D measure the sample at 119.5
where SwiftUI reports 124, so the fitted lines land a few points off (a tightened line holds
"f…" at 108 where SwiftUI's holds "…" at 101) and the title truncates at the minimum.

## Rich text (macOS 26.6, `text/markdown`, `text/attributed`, `text/dates`, `text/inline-image`, 2026-10-03)

| Behaviour | Value | Probe |
|---|---|---|
| Markdown runs | "bold" 29 wide in the bold weight, "italic" 28.5 in the italic trait, "both" 30.5 bold italic, "code" 32.5 in the monospaced design, "a link" 32 in the accent colour, "struck" 38 with a strikethrough; the mixed sentence 213.5 | `bold`, `italic`, `both`, `code`, `link`, `struck`, `mixed` |
| Verbatim and escapes | `Text(verbatim: "**not** markdown")` keeps its asterisks (110.5); `"Escaped \\*stars\\*"` shows the asterisks (97.5) | `verbatim`, `escaped` |
| Code in a title | "Mono `code` and plain" in `.title3`: 146 × 23, the monospaced design's line (23) over the style's 22 | `codeTitle` |
| Attributed runs | "Hello " + "world" (`.title`, red) + " under" (underlined) + " up" (baseline offset 4) + " link": 169.5 × 33, the raised 13 pt part staying within the title's line | `attributed` |
| Inline presentation intents | strongly emphasized → bold, emphasized → italic, code → monospaced, strikethrough: 202.5 × 16 | `intents` |
| Dates and formats at UTC | `.date` "May 28, 2026" (83.5), `.time` "8:26 PM" (49.5), `.number` 3.14159 and 1,234, `.percent` 25%, `.currency(code: "USD")` $12.50, `.dateTime.year().month().day()` "May 28, 2026" | `date`, `time`, `number`, `int`, `percent`, `currency`, `dateTime` |
| Inline symbols | `Text(Image(systemName: "star"))` 16.5 × 16 (the symbol's image size at 13 pt), with " Starred" 65, "Rate ★ now" 76, the title star 28.5 × 33, "› Next" 42; with `.bold()` the star row grows to 16.5 (the bold symbol's height) | `star`, `starText`, `between`, `starTitle`, `chevron`, `boldStar` |

Implementation: a `LocalizedStringKey` literal is parsed when the text's parts are resolved
(`Text.parts`), each markdown run adding to the part's modifiers (`bold`, `italic`,
`monospaced`, `strikethrough`, `link`). `Text(AttributedString)` reads each run's attributes
through the key types (`_SwiftUIFontAttribute` and the rest; the key paths of
`AttributeScopes.SwiftUIAttributes` alias them) and builds a concatenation. An image part is a
`StyledRun` one object-replacement character long with `inlineWidth`/`inlineHeight` from
`SystemSymbolMetrics` at the part's font; the layouter measures such runs by those instead of
the string and grows the line to the height, and the painter draws the symbol's path on the
baseline by its descent (`_SymbolPainter`). The recorded engine lays text with inline runs out
through the layouter over the text runs' own unconstrained recordings, so Tier A stays exact.
A date part resolves against the environment's time zone and calendar (`_TextContext`); a live
style makes the node invalidate itself every second. A text with a link part becomes
interactive (`_Interactive.isInteractive`, which the hit test honours so plain text never
takes a press from the control around it); a press on a link's fragment opens it through
`openURL`, and hovering it shows the hand.

## Open

- Rich text: `Text(DateInterval)` and ranges, `Duration`, per-run `kern`/`tracking` (applied to
  the whole text), `backgroundColor` attributes (not painted), non-system images in text, the
  live date wordings (SwiftUI's "in 2 hours"/"2 hours ago" forms and thresholds are unmeasured),
  `AttributedString` on wasm is a stand-in with runs, containers, ranges and markdown but none
  of Foundation's views and indices.
- The exact scale search (five bisection steps fit the three measured scales; the title case
  shows SwiftUI stopping above the minimum where ours reaches it) and the tightening maximum
  (a 72nd of the size per character fits the four widths within rounding).

- **`textScale`**: see `Docs/elements/TextScale.md`.
- **Height pressure with mixed fonts**: the kept-line count uses the first part's pitch; a concatenation mixing text styles under pressure is unverified.