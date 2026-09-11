# UILabel

`Packages/UIKitWeb/Sources/UIKitWebCore/Controls/UILabel.swift`. Fixtures `uikit/label/basic`
(sized to fit at the system and text-style fonts, weights, a centred label in a fixed frame) and
`uikit/label/wrapping` (wrapped at 200 without a limit and at two lines, truncated in a
one-line frame), exact in Tier A against UIKit on an iPhone simulator.

## API

`text`, `font` (17 pt system by default), `textColor` (`.label`), `textAlignment`, `lineBreakMode`
(tail, head and middle truncation), `numberOfLines` (0 wraps freely), `isEnabled` (tertiary label
colour when off), `preferredMaxLayoutWidth`, `sizeThatFits`, `intrinsicContentSize`,
`textRect(forBounds:limitedToNumberOfLines:)`. Held but not applied: `adjustsFontSizeToFitWidth`,
`minimumScaleFactor`, `highlightedTextColor`, `shadowColor`.

## Measured

- A label sized to fit is the text's width rounded up to the pixel by the font's label height
  (`Docs/elements/UIKit/UIFont.md`): "Hello, UIKit" 84.5 × 20.5 at 17 pt, "Title" 52 × 41.5,
  "Headline" 70.5 × 24.5, "Body" 39.5 × 24.5, "Footnote" 54.5 × 19, "Bold 13" 47 × 16 (SF
  Semibold: that is what `boldSystemFont` is on iOS), "Semibold 20" 116 × 24.
- Wrapping at 200: the widest line's width (181 for the fox), 41 tall for two 17 pt lines (two
  unrounded line heights, rounded up once); a two-line limit gives the same. A one-line label
  reports its whole width whatever the proposal (339 for the fox at 120).
- The text block is centred vertically in a taller frame; a line's baseline sits at the font's
  ascender from the top of its line box.
- Text is measured by the scene's text engine; in Tier A the recorded `UILabel` measurements
  (`Fixtures/Goldens/uikit/text-metrics.json`, keyed as the label asks: `font|width;l<lines>|text`).

Open: the ink position of a text-style line (its 24.5 box holds a 24.29 line; unverified until
UIKit pixels are compared), attributed text, font scaling to fit, letter-form adjustments.
