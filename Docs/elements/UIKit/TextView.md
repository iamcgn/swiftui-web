# UITextView

`Packages/UIKitWeb/Sources/UIKitWebCore/Controls/UITextView.swift`. Fixtures
`uikit/textview/basic` (a scrolling body, a `sizeToFit` view, a padded and a centred growing view,
a read-only footnote) and `uikit/textview/heights` (one-line views at 11 … 28 pt), measured on the
iPhone SE simulator (iOS 26).

## API

`text`, `font` (nil draws the 12 pt system font; UIKit's default is Helvetica 12, which the web
has no metrics for), `textColor`, `textAlignment`, `isEditable`, `isSelectable`,
`textContainerInset` (8 above and below), `textContainer.lineFragmentPadding` (5) and
`maximumNumberOfLines`, `isScrollEnabled` and the scroll view API, `keyboardType`,
`returnKeyType`, `autocapitalizationType`, `delegate` (`UITextViewDelegate` refines
`UIScrollViewDelegate`: `textViewShouldBeginEditing`, `DidBeginEditing`, `ShouldEndEditing`,
`DidEndEditing`, `textViewDidChange`, `DidChangeSelection`), `sizeThatFits`,
`intrinsicContentSize`, `becomeFirstResponder`, `resignFirstResponder`. Editing goes through the
substrate's multi-line text input (`TextInputInfo.isMultiline`), as SwiftUI's `TextEditor` does.

## Measured

- Lines start `textContainerInset.left + lineFragmentPadding` in (5.5 for the T of the body
  text), and the first baseline is the top inset plus the ascender rounded up to the pixel
  (24.5 for 17 pt under the 8 pt inset). The pitch between lines is the font's line height
  rounded up to the pixel (20.5 for 17 pt, 15.5 for 13 pt): TextKit's line fragments sit on
  the pixel grid.
- `sizeThatFits(size)` lays the text out in `size.width` less the insets and twice the padding,
  and answers the text's used width plus the horizontal insets (not the padding) by the label
  height for the lines (`UIFont.labelHeight`: 13.5, 14.5, 16, 17, 18, 19.5, 20.5, 24, 29, 33.5
  for 11 … 28 pt) plus the vertical insets. `uikit/textview/heights` pins the ten heights;
  "Padded" at 15 pt in 12 pt insets is 42 tall.
- `sizeToFit` therefore narrows the view to the text and keeps the height of the wider layout:
  "Two lines of / text" at 17 pt proposed 200 wide becomes 90.5 × 57, re-wraps to three lines
  in the narrower width and shows two (`fitted`). A text view that does not scroll lays out
  only the lines its container holds (41 pt holds two 20.5 pt lines); a scrolling one lays
  out every line and its content height is the label height for them plus the insets.
- A non-editable text view paints the same; the simulator's capture of a scrolling text view
  shows no indicators (they are hidden until a scroll).
- Pixels: `uikit/textview/basic` 2.85 % and `heights` 2.26 % off the simulator's capture, the
  band every text-only fixture sits in (`uikit/label/basic` 2.82 %): glyph rasterisation, not
  placement.

## Open

`attributedText`, selection and `selectedRange`, data detectors, links, placeholder text (UIKit
has none either), `textContainer` exclusion paths, `UITextView.textLayoutManager`, scroll
indicators after a scroll, the Helvetica default font.
