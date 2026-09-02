# Button

Apple docs: [Button](https://developer.apple.com/documentation/swiftui/button),
[ButtonStyle](https://developer.apple.com/documentation/swiftui/buttonstyle),
[PrimitiveButtonStyle](https://developer.apple.com/documentation/swiftui/primitivebuttonstyle) (not yet).

## Measured (macOS 26.2, `button/basic`, `button/styles`, pixels sampled from goldens)

| Property | Value |
|---|---|
| Bordered (default) height | 24 pt (`frame(minHeight:)`) |
| Bordered horizontal padding | 12 pt each side: width = label width + 24 |
| Bordered label font | 13 pt point-size system font (16 pt line, baseline 13), **not** `.body` (18.5 pt line) |
| Bordered corner radius | 6 pt (from the anti-aliasing ramp at 2×) |
| Bordered fill | black at 19/255 ≈ 7.5 % (ImageRenderer draws a flat fill, no gradient or border) |
| Prominent | same geometry; fill accent blue (0, 136, 255); white label |
| Plain | label only, `.body` metrics |
| Borderless | label only (65 pt for "Borderless"), `.body` metrics; ImageRenderer draws an "unsupported" placeholder, so its look is **approximate** (accent-coloured label) |
| Spacing between buttons | 8 pt default |
| Pressed appearance | unverified (fill darkened to 50/255) |

## Behaviour

`Button` is a composite: its body reads the `buttonStyle` environment, calls `makeBody(configuration:)`
and wraps the result in `_ButtonHost`, the primitive that owns hit testing, press state (a
`@State` inside `Button`, exposed through `ButtonStyleConfiguration.isPressed`) and activation.
The runtime's `pointerDown/pointerUp` find the deepest interactive node under the pointer; the
action fires only when the release is inside the pressed node. `semanticsTree()` lists buttons
with their labels for the accessibility overlay; `activate(semanticsIdentifier:)` is the keyboard
path.

Runtime note: stdlib key-path reflection refuses structs with plain closure fields, which is why
dynamic-property installation uses `_forEachField` offsets (`DynamicPropertyFields.swift`).

## Not yet covered

`PrimitiveButtonStyle`, `role` appearance, `disabled`, keyboard shortcuts, `controlSize`,
`Label(_:systemImage:)` labels, hover, focus ring.
