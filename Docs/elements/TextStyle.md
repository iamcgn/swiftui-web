# underline, strikethrough, textCase, baselineOffset, kerning, tracking

Apple docs: [underline(_:pattern:color:)](https://developer.apple.com/documentation/swiftui/text/underline(_:pattern:color:)),
[strikethrough(_:pattern:color:)](https://developer.apple.com/documentation/swiftui/text/strikethrough(_:pattern:color:)),
[Text.LineStyle](https://developer.apple.com/documentation/swiftui/text/linestyle),
[textCase(_:)](https://developer.apple.com/documentation/swiftui/view/textcase(_:)),
[baselineOffset(_:)](https://developer.apple.com/documentation/swiftui/text/baselineoffset(_:)),
[kerning(_:)](https://developer.apple.com/documentation/swiftui/text/kerning(_:)),
[tracking(_:)](https://developer.apple.com/documentation/swiftui/text/tracking(_:)).

## API surface

| API | Notes |
|---|---|
| `Text.underline(_:pattern:color:)`, `Text.strikethrough(_:pattern:color:)` | implemented; a `false` on a text overrides the view modifier |
| `View.underline(_:pattern:color:)`, `View.strikethrough(_:pattern:color:)` | implemented (environment) |
| `Text.LineStyle`, `.single`, `Pattern` (`solid`, `dot`, `dash`, `dashDot`, `dashDotDot`) | implemented |
| `Text.Case` (`uppercase`, `lowercase`), `View.textCase(_:)`, `EnvironmentValues.textCase` | implemented (applied before layout and measurement) |
| `Text.baselineOffset(_:)`, `View.baselineOffset(_:)` | implemented (layout and painting) |
| `Text.kerning(_:)`, `Text.tracking(_:)`, `View.kerning(_:)`, `View.tracking(_:)` | implemented (the text's own value wins over the environment's; tracking wins over kerning) |
| `textSelection`, `textScale`, `monospacedDigit`, `speechAdjustedPitch`… | missing |

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

### Kerning and tracking (measured 2026-09-04, `textstyle/kerning`)

Both add their value after **every** character, spaces and the last character included:
"Hello" (13 pt) 31 → 41 at 2 pt, 56 at 5 pt, 26 at −1 pt; "Kerned text" 70 → 92 at 2 pt; the
title-sized "Hello" 49 → 59. Tracking measures exactly like kerning at the same value, and a
wrapped kerned paragraph breaks on the spread widths ("Wrapped kerned words fill the line" at
160 pt keeps two lines, the longer 140.5 pt). `TextLayoutOptions.kerning`/`.tracking` are part of
the layout options (and of the recorded-metrics key: `;k2.0`, `;tr2.0`); `TextLayouter` wraps its
measurer to add `spacing × characters` and lays the text out with the options' spacing taken
out, so the browser's canvas and CoreText measure plain advances. Painting sets the spacing on
the `DisplayFont` (`letterSpacing`): the CSS font string carries it after a `|`, the canvas painter
sets `letterSpacing` where the context has it (Chromium) and otherwise draws character by
character at the measured advance plus the spacing (WebKit, Firefox), CoreText draws with the
kern attribute.

A related SwiftUI behaviour surfaced while measuring: in a window too short for its stack, a
`Text` under height pressure drops to one truncated line (the fixture was made taller); that
pressure rule is still open.

## Verification (2026-09-04)

Tier A: 6 fixtures exact. Tier C: underline 0.10 %, strikethrough 0.01 %, patterns, case,
baseline and kerning 0.00 %. `TextStyleTests` cover the snapping arithmetic, patterns, colours, the
view-level opt-out, `textCase` widths and baseline offsets in a baseline-aligned row;
`KerningTests` the per-character rule, tracking over kerning, wrapping on spread widths, the
metrics key and the display font's spacing. Tier B: `textstyle/kerning` exact frames in Chromium
(0.6 %) and WebKit (1.7 %, drawn character by character); Firefox measures "Kerned text" and
"Tracked text" 0.5 pt wider (its known hinting class).

## Not yet covered

text under height pressure (fewer lines and truncation, seen with the kerned paragraph),
`textSelection`, `textScale`, decorations on `TextField`/`TextEditor` text, the one-pixel
placement residue on some weights, the underline of a `Link` (drawn separately).
