# UITextField

`Packages/UIKitWeb/Sources/UIKitWebCore/Controls/UITextField.swift`. Fixtures
`uikit/controls/basic`: rounded fields with text, a placeholder and secure entry, and a plain
field sized to fit; `uikit/textfield/looks`: the line and bezel borders, clear buttons, left and
right views, an attributed placeholder, centred text, with an "edit" step that focuses a field.

## API

`text`, `attributedText` (one font and colour), `placeholder`, `attributedPlaceholder`, `font`
(17 pt system), `textColor`, `textAlignment`, `borderStyle` (`none`, `line`, `bezel`,
`roundedRect`), `isSecureTextEntry`, `keyboardType`, `returnKeyType`, `autocapitalizationType`,
`autocorrectionType`, `textContentType`, `clearButtonMode`, `leftView`/`rightView` with their
modes, `textRect(forBounds:)`, `clearButtonRect(forBounds:)`, `leftViewRect(forBounds:)`,
`rightViewRect(forBounds:)`, `delegate` (`textFieldShouldReturn`, `textFieldDidBeginEditing`,
`…EndEditing`, `textFieldShouldClear`), `becomeFirstResponder`, `resignFirstResponder`,
`editingChanged` and `editingDidEnd` through `UIAction`. Editing goes through the substrate's
text-input overlay (`TextInputInfo`), as SwiftUI's fields do.

## Measured

- A rounded field sized to fit is 34 tall; its text and placeholder start 7 in (the placeholder
  label sits at (7, 7, width − 14, 20), the text canvas at (7, 2) with a 22 pt line box 4 down,
  measured on Catalyst). The background has 5 pt corners.
- A plain field sized to fit "Plain field" is 74 × 22 on the iPhone: the text's width (73.5)
  rounded up to the point with no inset, and the 17 pt line height plus 1.5 (21.79) rounded up to
  the pixel. Catalyst gave 77 × 21.5 by the same rule with its own metrics. Two measurements;
  other sizes are unverified.
- A field measures its text without a line limit (`font||text` in the recordings), the
  placeholder when the text is empty.
- A rounded field's intrinsic size is its text plus 14 each side by 34 (`uikit/controls/intrinsic`:
  67 × 34 for the 39 pt "Hello"), twice the inset the text is drawn at; the intrinsic width is
  real (not `noIntrinsicMetric`), and the priorities are UIKit's defaults (hugging 250).
- The simulator's snapshot of a secure field is blank: iOS redacts secure text in
  `drawHierarchy` captures, so `uikit/controls/basic` pins the secure field's frame only.

## Borders, the clear button and side views (2026-10-04)

Measured on `uikit/textfield/looks` (iOS 26 simulator, light):

- The text line box is centred in the field on the pixel-rounded line height (20.5 at 17 pt)
  and the baseline lands on the pixel grid: 37 in the 30 pt line field (16 + 4.75 + 16.19 =
  36.94), 259 in the rounded field at 236, 297 in the 22 pt plain field at 280. The bezel's
  text sits 1.5 lower (baseline 83.5 in the field at 60).
- `line`: 1 pt stroke in the label colour at the frame's edge, no fill; 30 tall, text 2 in,
  sized to the text plus 4 each side (95 for the 87 pt "Line border").
- `bezel`: 1 pt black 50 % at the edge with an inner 1 pt black 33 % line along the top and
  left, no fill; 32 tall, text 7 in, sized to the text plus 14 each side (125 for 97).
- `roundedRect`: as before (34 tall, 4 pt corners, 0.5 pt 20 % border, text 7 in).
- The clear button is a 17 pt `xmark.circle.fill` at 80 % white (204) centred 15 from the
  right edge and half a point below the middle (ink 152.5–169.5 × 113–130 in a field at
  (16, 104, 160, 34)); the text rect ends 11 before it ("Center" centred in a 120 pt field
  moves from 219 to 205 when the button shows). The simulator paints clear buttons only after a
  field has been edited, so the fixture sets the `.always` and `.unlessEditing` modes in its
  step; UIKitWeb shows them whenever their mode says so. Tapping it (4 pt wider, 8 taller
  than the disc) clears the text through `textFieldShouldClear` and sends `editingChanged`.
  The dark look (92/92/97 with a 28/28/30 cross) is unverified.
- `leftView`/`rightView` are subviews laid out flush to the field's edges and centred
  vertically (a 20 pt view at y 7, a 12 pt one at 11 in a 34 pt field); the text starts the
  border inset (7) after the left view and ends it before the right one. Their modes hide them.
- An attributed placeholder draws in its first run's font and colour, centred on its own line
  height (15 pt systemRed "Attributed": baseline 214.5 in a field at 192); its string is the
  `placeholder`.
- The keyboard reaches the host's input element as attributes: `keyboardType` → `inputmode`
  and `type` (email, url, tel, search; password for secure entry), `returnKeyType` →
  `enterkeyhint`, `autocapitalizationType` → `autocapitalize`, `textContentType` →
  `autocomplete`, `autocorrectionType` → `autocorrect` (`UITextView` sends the same).

Tier C within 2.3 % (glyph anti-aliasing, the simulator's caret). Open: `attributedText` with
several runs, `adjustsFontSizeToFitWidth`, the dark clear button, truncated centred text.
