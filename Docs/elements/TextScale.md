# textScale, textSelection

Apple docs: [textScale(_:isEnabled:)](https://developer.apple.com/documentation/swiftui/view/textscale(_:isenabled:)),
[Text.Scale](https://developer.apple.com/documentation/swiftui/text/scale),
[textSelection(_:)](https://developer.apple.com/documentation/swiftui/view/textselection(_:)),
[TextSelectability](https://developer.apple.com/documentation/swiftui/textselectability).

## API surface

| API | Notes |
|---|---|
| `textScale(_:isEnabled:)`, `Text.Scale` (`default`, `secondary`) | implemented (measured) |
| `textSelection(_:)`, `TextSelectability` (`enabled`, `disabled`) | implemented: the environment value and an I-beam pointer over selectable text; no selection, copy or drag yet |

## Measured (2026-09-05, macOS 26)

The secondary scale was read off SwiftUI's own layout with a `TextRenderer` (the run's
`CTFont` and `CTTracking` attribute), then checked against goldens.

- **Line height stays the base font's.** `Hello` at `.body` is 18.5 high at both scales; the
  wrapped paragraph keeps its 16 pt lines and drops from four to three (`textscale/wrapped`).
- **Point size** = base × f, with `t = clamp((base − 17) / 53, 0, 1)` and
  `f = f₁₇ − (f₁₇ − f₇₀) t`: constant up to 17 pt, linear to 70 pt, constant beyond.
  `(f₁₇, f₇₀)` per weight: ultraLight, thin, light, regular (0.8, 0.46); medium (0.8, 0.48);
  semibold (0.84, 0.49); bold (0.85, 0.5); heavy (0.85, 0.52); black (0.87, 0.55). So body 13 → 10.4,
  title 22 → 16.89, largeTitle 26 → 19.3, 40 pt → 26.1, 80 pt → 36.8; a bold 13 → 11.05.
- **Tracking** (`CTTracking`, points after every glyph) = t₁₇ × (1 − t): regular 0.25,
  light 0.1854, thin 0.15, ultraLight 0.16, medium 0.4147, semibold 0, bold −0.05, heavy 0.2,
  black 0.35; the rounded design 0.03. (Thin and black drift off the line above 20 pt; not modelled.)
- **Weight axis**: the scaled face is heavier (`wght` ≈ 510 for regular, more for bold), so its
  glyphs run about 2.4 % wider than the plain system font at the scaled size (3.3 % in the
  display optical size, 1.7 % medium, 3.4 % bold and heavier). The paragraph at every style,
  one line: default vs secondary widths largeTitle 801.5 → 649, title 683.5 → 579, title2
  551 → 486.5, title3 496.5 → 439, headline 469.5 → 418, body 439.5 → 390, callout 411 → 364.5,
  subheadline 381.5 → 339, footnote/caption 351 → 313.5, caption2 359.5 → 330, 20 pt
  631.5 → 545, 40 pt 1220 → 845.5.
- **Not scaled**: the serif and monospaced designs and custom fonts keep their size and get no
  tracking. `isEnabled: false` leaves the text alone (`textscale/wrapped`).
- **Selection** changes nothing in layout (`textscale/selection`).

## Implementation

`textScale` sets the environment's `_textScale`; `TextLayoutOptions.textScale` carries it into
the metrics key (`;sc2`), so the recorded engine returns SwiftUI's own layouts (Tier A exact on
`textscale/styles`, `wrapped`, `selection`). `ResolvedFont.secondaryScaled` gives the scaled font
and the spacing to add after every glyph: the measured tracking plus half the weight gain times
the size (0.5 × 0.024 × 10.4 ≈ 0.12 pt for body, which reproduces the paragraph widths within a
point). The layouter measures the scaled font with that spacing; painting draws it with the
scaled `DisplayFont` and the spacing as letter spacing (canvas `letterSpacing` or per-character
drawing, CoreText kerning). Line metrics (height, baseline, spacing categories) are the base
font's, since the scale never reaches `systemFontMetrics(for:)`.

Tier C reproduces the goldens exactly; browsers measure the plain font at the scaled size, so
frames match in Chromium and WebKit (Firefox measures the 8 pt scaled caption 0.5 pt narrower) and pixels differ by the weight the browser cannot apply.

## Open

- The weight bump is spread as spacing; a browser cannot set `wght` on a canvas font, so
  scaled glyphs are thinner than SwiftUI's.
- Thin and black tracking above 20 pt, rounded designs at other weights: unmeasured.
- Text selection itself (highlight, copy, drag) is not implemented.
