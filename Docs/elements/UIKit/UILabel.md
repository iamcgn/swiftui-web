# UILabel

Baseline anchors (Auto Layout, SwiftUI alignment): the ascender rounded to the pixel below the text rect's rounded top (`uikit/autolayout/baseline`; `Docs/elements/UIKit/AutoLayout.md`).

`Packages/UIKitWeb/Sources/UIKitWebCore/Controls/UILabel.swift`. Fixtures `uikit/label/basic`
(sized to fit at the system and text-style fonts, weights, a centred label in a fixed frame) and
`uikit/label/wrapping` (wrapped at 200 without a limit and at two lines, truncated in a
one-line frame), exact in Tier A against UIKit on an iPhone simulator.

## API

`text`, `font` (17 pt system by default), `textColor` (`.label`), `textAlignment`, `lineBreakMode`
(tail, head and middle truncation), `numberOfLines` (0 wraps freely), `isEnabled` (tertiary label
colour when off), `preferredMaxLayoutWidth`, `sizeThatFits`, `intrinsicContentSize`,
`textRect(forBounds:limitedToNumberOfLines:)`. Since 2026-10-04: `attributedText` (per-range
`.font` and `.foregroundColor`, a paragraph style's alignment and line break mode; `text` and
`font` follow the string and its first run), `adjustsFontSizeToFitWidth` with
`minimumScaleFactor`, `allowsDefaultTighteningForTruncation`. On wasm `NSAttributedString` and
`NSMutableAttributedString` are stand-ins with per-range attributes (`append`, `addAttribute(s)`,
`setAttributes`, `removeAttribute`, `replaceCharacters`, `enumerateAttributes`,
`attributedSubstring`). Held but not applied: `highlightedTextColor`, `shadowColor`.

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

Under Auto Layout a wrapping label takes the width it is solved to and reports its wrapped
height plus a point (`Docs/elements/UIKit/AutoLayout.md`, 2026-09-11).

## Attributed text and fitting (iOS 26, `uikit/label/fitting`, 2026-10-04)

- Attributed runs draw in their own fonts and colours on one baseline, the tallest run's: "Plain
  bold red big" (17, 17 semibold, 17 red, 24) is 142 × 29 sized to fit (the runs' widths, the
  24 pt label height), each run starting where the previous ended. The recorded metrics hold the
  whole string as one `rich:` entry (`UIKitTextRequest(runs:)`), as the text engine keys it.
- `adjustsFontSizeToFitWidth` scales the text continuously to the width (not in steps): 17 pt
  text 159 wide in a 120 pt one-line label draws at 120/159 of its size (12.83 pt, 117.5 of ink);
  a `minimumScaleFactor` the width needs more than (0.9 → 15.3 pt) leaves it truncated at that
  size. The label's own size (`sizeThatFits`) never scales. `allowsDefaultTighteningForTruncation`
  lets the engine close letters up a little before truncating; "Tightened before truncating"
  (213 wide) in 200 still truncates, exactly as without it.
- The ink of a text-style line sits where the simulator puts it: the title, headline, body,
  footnote and 13–20 pt lines of `uikit/label/basic` match row for row (the title 0.5 pt high,
  within the anti-aliasing); `uikit/label/basic` 2.8 % of pixels, `uikit/label/fitting` within the
  approximate bound (glyph scaling and the attributed runs' rendering).

Open: `highlightedTextColor`, `shadowColor`, attributed paragraph styles beyond alignment and
line breaks (spacing, indents), underline and strikethrough attributes in labels, the exact
tightening UIKit applies before truncation.
