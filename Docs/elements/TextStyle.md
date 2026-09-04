# underline, strikethrough, textCase, baselineOffset

Apple docs: [underline(_:pattern:color:)](https://developer.apple.com/documentation/swiftui/text/underline(_:pattern:color:)),
[strikethrough(_:pattern:color:)](https://developer.apple.com/documentation/swiftui/text/strikethrough(_:pattern:color:)),
[Text.LineStyle](https://developer.apple.com/documentation/swiftui/text/linestyle),
[textCase(_:)](https://developer.apple.com/documentation/swiftui/view/textcase(_:)),
[baselineOffset(_:)](https://developer.apple.com/documentation/swiftui/text/baselineoffset(_:)).

## API surface

| API | Notes |
|---|---|
| `Text.underline(_:pattern:color:)`, `Text.strikethrough(_:pattern:color:)` | implemented; a `false` on a text overrides the view modifier |
| `View.underline(_:pattern:color:)`, `View.strikethrough(_:pattern:color:)` | implemented (environment) |
| `Text.LineStyle`, `.single`, `Pattern` (`solid`, `dot`, `dash`, `dashDot`, `dashDotDot`) | implemented |
| `Text.Case` (`uppercase`, `lowercase`), `View.textCase(_:)`, `EnvironmentValues.textCase` | implemented (applied before layout and measurement) |
| `Text.baselineOffset(_:)`, `View.baselineOffset(_:)` | implemented (layout and painting) |
| `kerning`, `tracking`, `textSelection`, `textScale`, `monospacedDigit`, `speechAdjustedPitch`… | missing |

## Behaviour

`Text.Modifiers` carries `underline`/`strikethrough` as `LineStyle??` (unset inherits the enclosing
text, then the environment; `.some(nil)` is an explicit off) and `baselineOffset`. `TextNode.paintSelf`
draws each fragment's line after its glyphs (`paintDecoration`): a `fillRect` for solid lines, a
`strokePath` with a dash array for patterns, in the style's colour or the fragment's text colour.
`textCase` transforms the run strings (`TextNode.cased`) so the recorded metrics of the cased string
are used. Baseline offsets change the layout (below).

## Measured (macOS 26.2, 2026-09-04)

Decoration metrics come from CoreText through the harness (`NSFont.underlinePosition`,
`underlineThickness`, `xHeight` per measured font in `text-metrics.json`, now in
`SystemFontMetrics` as `underlineOffset`, `underlineThickness`, `xHeight`). The offset and
thickness are proportional to the point size for every SF size (0.15137 and 0.05859 per point) and
scale with weight by fixed ratios (`PlatformProfile.textDecorationMetrics`: thickness ×1.214 medium,
×1.369 semibold, ×1.583 bold, ×1.894 heavy, ×2.167 black; offset ×0.9645 … ×0.8065; measured at 13
and 20 pt), and differ per design (serif ×0.76/×0.74, monospaced ×0.65/×0.83 at 20 pt).

| Property | Rule | Fixture |
|---|---|---|
| Underline | centre at `baseline + underlineOffset`; drawn as whole device pixels: thickness `ceil(thickness × scale)` px, top `round(centre × scale − px/2)`; ends rounded inwards to the pixel grid | `textstyle/underline` (13 pt: 1 pt line at 14.5 of 16; title: 1.5 pt at 27.5 of 33; caption: 1 pt at 12 of 15) |
| Strikethrough | centre at `baseline − xHeight/2`, same snapping and thickness | `textstyle/strikethrough` (13 pt: 1 pt at 9; title: 1.5 pt at 18.5; largeTitle: 2 pt at 21.5) |
| Weights | the rule matches 21 of 24 measured size/weight faces exactly; SF 11 pt regular and 13 pt bold/heavy draw one pixel off (a throwaway grid, not kept) | `textstyle/underline` `bold` (0.10 % pixels) |
| Patterns | in units of the snapped thickness `t`: dot `[3t, 3t]`, dash `[10t, 5t]`, dashDot `[10t, 3t, 3t, 3t]`, dashDotDot `[10t, 3t, 3t, 3t, 3t, 3t]`; the pattern starts "on" at the text's left edge | `textstyle/patterns` (dots 3 pt at 13 pt, 4.5 pt in the title font) |
| Colour | the text colour (primary label at 85 %) unless the style has one | `colored`, `dashStrike` |
| Partial and view-level | a concatenation decorates only the parts that ask; `.underline()` on a view reaches every text below it and `Text.underline(false)` opts one out | `partial`, `viewLevel` |
| `textCase` | the transformed string is laid out (`MIXED CASE` is wider than `mixed Case`); `nil` restores the source text; the environment reaches nested texts | `textstyle/case` |
| `baselineOffset(b)` | the text grows by `|b|`: a raise keeps the glyphs where they were and adds `b` below the baseline *guide* (so `firstTextBaseline` alignment moves the raised text up by `b`), a drop moves the glyphs down by `|b|` and adds that below; 16-high text becomes 22 with 6 and 20 with −4 | `textstyle/baseline` |

## Verification (2026-09-04)

Tier A: 5 fixtures exact. Tier C: underline 0.10 %, strikethrough 0.01 %, patterns, case and
baseline 0.00 %. `TextStyleTests` cover the snapping arithmetic, patterns, colours, the view-level
opt-out, `textCase` widths and baseline offsets in a baseline-aligned row.

## Not yet covered

`kerning`/`tracking` (they change widths, so they need recorded metrics per tracking value),
`textSelection`, `textScale`, decorations on `TextField`/`TextEditor` text, the one-pixel
placement residue on some weights, the underline of a `Link` (drawn separately).
