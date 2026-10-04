# UITextView

`Packages/UIKitWeb/Sources/UIKitWebCore/Controls/UITextView.swift`. Fixtures
`uikit/textview/basic` (a scrolling body, a `sizeToFit` view, a padded and a centred growing view,
a read-only footnote), `uikit/textview/heights` (one-line views at 11 … 28 pt) and
`uikit/textview/looks` (attributed runs with a link, detected links, text around an exclusion
path, the default font, a selection after the "edit" step), measured on the iPhone SE simulator
(iOS 26).

## API

`text`, `attributedText` (runs with `.font`, `.foregroundColor` and `.link`), `font` (nil is
UIKit's default, Helvetica 12, with its iOS metrics), `textColor`, `textAlignment`, `isEditable`,
`isSelectable`, `dataDetectorTypes` (`.link`), `linkTextAttributes` (a `.foregroundColor`),
`selectedRange`, `textContainerInset` (8 above and below), `textContainer.lineFragmentPadding`
(5), `maximumNumberOfLines` and `exclusionPaths`, `isScrollEnabled` and the scroll view API,
`keyboardType`, `returnKeyType`, `autocapitalizationType`, `autocorrectionType`,
`textContentType`, `delegate` (`UITextViewDelegate` refines `UIScrollViewDelegate`:
`textViewShouldBeginEditing`, `DidBeginEditing`, `ShouldEndEditing`, `DidEndEditing`,
`textViewDidChange`, `DidChangeSelection`, `textView(_:shouldInteractWith:in:interaction:)`),
`sizeThatFits`, `intrinsicContentSize`, `becomeFirstResponder`, `resignFirstResponder`. Editing
goes through the substrate's multi-line text input (`TextInputInfo.isMultiline`), as SwiftUI's
`TextEditor` does; the keyboard attributes reach the input element.

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

## Attributed text, links, selection, exclusion paths (2026-10-04)

Measured on `uikit/textview/looks`:

- Attributed runs draw in their own fonts and colours on one baseline per line, the lines on
  the tallest run's pitch (a 15 pt run beside 17 pt ones sits on the 17 pt baseline). A
  two-line paragraph wraps greedily: "…red end, a" stays on the first line (268 wide in 278)
  where SwiftUI's text would move "a" down to balance the lines
  (`TextLayoutOptions.balancesTwoLines`). `boldSystemFont` is the semibold face.
- Links (`.link` runs, and URLs starting `http://`, `https://` or `www.` detected in a
  non-editable view with `dataDetectorTypes` containing `.link`) draw in iOS 26's link blue
  (0/136/255) with no underline; the simulator's capture shows detected links untinted,
  which UIKitWeb does not copy. A tap on a link asks the delegate and opens the URL through
  the scene; an editable view detects nothing.
- The selection paints while the view is editing: a highlight from a point above the line
  band to its bottom (347–368.5 for the band at 348, 21.5 tall), 194/210/231 over
  systemGray6 (a darkening of the ground; UIKitWeb fills 204/221/238), with 2 pt bars in
  20/111/225 at both ends and 10 pt knobs, the start's above and the end's below. The
  highlight's edges come from the widths of the line's text up to the selection (recorded
  as `Select ` and `Select some`). The browser's own selection is not mirrored into
  `selectedRange`.
- Exclusion paths: a line whose 20.5 pt band a path's bounds cross starts after the path
  (its right edge plus the 5 pt padding) when the path lies in the left half, ends before it
  in the right half; "Wraps around / the box on / the left side" start 85 in beside an
  80 × 50 box, the lines below start at 5. Lines are laid out paragraph by paragraph (the
  recorded engine needs each paragraph's lines recorded).
- The default font is Helvetica 12 with iOS's metrics (ascender 11.04, descender −2.76,
  13.8 pt lines, cap height 8.61): a one-line view is 30 tall. The browser draws Helvetica
  where it has it (`UIFont.installedFonts`).
- The scroll indicator shows while a drag scrolls the text and fades after (`UIScrollView`).

Tier C within 4.6 % (approximate: the detected links' tint, the handle shapes, glyph
anti-aliasing). Open: `selectedTextRange` and the browser's selection, data detectors other
than links, `UITextView.textLayoutManager`, exclusion paths in the middle of a line.
