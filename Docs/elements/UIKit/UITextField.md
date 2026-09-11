# UITextField

`Packages/UIKitWeb/Sources/UIKitWebCore/Controls/UITextField.swift`. Fixture
`uikit/controls/basic`: rounded fields with text, a placeholder and secure entry, and a plain
field sized to fit.

## API

`text`, `placeholder`, `font` (17 pt system), `textColor`, `textAlignment`, `borderStyle` (`none`,
`line`, `bezel`, `roundedRect`), `isSecureTextEntry`, `keyboardType`, `returnKeyType`,
`clearButtonMode`, `delegate` (`textFieldShouldReturn`, `textFieldDidBeginEditing`, `…EndEditing`), `becomeFirstResponder`, `resignFirstResponder`, `editingChanged` and
`editingDidEnd` through `UIAction`. Editing goes through the substrate's text-input overlay
(`TextInputInfo`), as SwiftUI's fields do.

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

Open: the text's vertical position inside the 34 pt field against UIKit's pixels, the `line`
and `bezel` borders, the clear button, `leftView`/`rightView`, attributed placeholders.
