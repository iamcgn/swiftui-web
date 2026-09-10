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

- A rounded field sized to fit is 34 tall; its text and placeholder start 7 in (Catalyst's
  placeholder label sits at (7, 7, width − 14, 20), the text canvas at (7, 2) with a 22 pt line
  box 4 down). The background has 5 pt corners.
- A plain field sized to fit "Plain field" is 77 × 21.5: the text's width with no inset, and the
  17 pt ascender-plus-descender (20.02) rounded up to the pixel plus one. One measurement; other
  sizes are unverified.
- A field measures its text without a line limit (`font||text` in the recordings), the
  placeholder when the text is empty.

Open: the text's vertical position inside the 34 pt field against UIKit's pixels, the `line`
and `bezel` borders, the clear button, `leftView`/`rightView`, attributed placeholders.
