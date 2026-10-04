# Button

Apple docs: [Button](https://developer.apple.com/documentation/swiftui/button),
[ButtonStyle](https://developer.apple.com/documentation/swiftui/buttonstyle),
[PrimitiveButtonStyle](https://developer.apple.com/documentation/swiftui/primitivebuttonstyle).

## API (2026-10-04, sw-button-looks)

| API | Status |
|---|---|
| `PrimitiveButtonStyle`, `PrimitiveButtonStyleConfiguration` (`label`, `role`, `trigger()`), `buttonStyle(_: PrimitiveButtonStyle)` | implemented: the style's body replaces the button host, so the style decides when `trigger` runs (a `ButtonStyle` set later takes over again) |
| `controlSize` on buttons | implemented: iOS from `ios/button/looks` (below); macOS approximate: mini 17 / small 20 / regular 24 / large 32 pt bezels with 10 / 11 / 13 / 15 pt labels and 8 / 10 / 12 / 12 pt side padding (shifted from macOS 26.6's 13 / 16 / 20 / 28); `.extraLarge` is the regular on macOS |
| Destructive role | implemented: iOS measured (a red label in the bordered and borderless styles, a red capsule with a white label in the prominent one); macOS the same, unverified (an inactive window shows no tint) |
| Disabled look | implemented: iOS measured (a prominent button wears the bordered fill with its label at 17 %, a plain one its label at 50 %; the bordered label at 24 % from `ios/button/basic`); macOS the label at 30 % (button/looks, 26.6) and the plain one at 50 %, the bezel's fill halved (unverified) |
| Pressed look | unverified: the bordered fill darkened to 50/255, the prominent and bordered capsules at 80 / 70 %, borderless and plain labels dimmed |
| Hover | no change, as on macOS |
| Keyboard focus | the runtime's accent ring around the focused button (approximate, `KeyboardNodes.swift`) |

## Measured (macOS 26.2, `button/basic`, `button/styles`; frames from a hosted window since decision 0010)

| Property | Value |
|---|---|
| Bordered (default) height | 24 pt: the label plus 4 pt above and below, at least 24 (a 24 pt `Label` makes a 32 pt button, `label/basic`) |
| Bordered horizontal padding | 12 pt each side: width = label width + 24 |
| Bordered label font | the default 13 pt system font (16 pt line, baseline 13); the same font plain text gets in a window (decision 0010) |
| Bordered corner radius | 6 pt (from the anti-aliasing ramp at 2×) |
| Bordered fill | black at 19/255 ≈ 7.5 % (sampled from the earlier ImageRenderer goldens; the window golden reads 20/255) |
| Prominent | same geometry; fill accent blue (0, 136, 255); white label |
| Plain | label only, default-font metrics (16 pt line) |
| Borderless | label only (65 pt for "Borderless"), default-font metrics; look **approximate** (accent-coloured label) |
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

`disabled(_:)` stops activation (and the pressed state); the dimmed look is not drawn yet.

## iOS (iPhone SE simulator, iOS 26, `ios/button/looks`, 2026-10-04)

| Property | Value |
|---|---|
| Mini, small | a 31 pt capsule: the 15 pt subheadline label (a 21 pt line) 10 in and 5 above and below; the two sizes are the same |
| Regular | 38.5: the body label 12 in and 7 above and below (`ios/button/basic`) |
| Large, extra large | a 54.5 pt capsule: the body label 20 in and 15 above and below; the two sizes are the same on iPhone |
| Prominent | the same capsules in the accent colour with a white label (large 118 wide for "Prominent", mini 48.5 for "Mini") |
| Destructive | the label (255, 56, 60) in the bordered and borderless styles; the prominent capsule in that red with a white label |
| Disabled prominent | the bordered fill (233, 233, 234) with the label at (194, 194, 196): black at 17 % |
| Disabled plain | the label at (127): 50 % |

## macOS 26.6 (`button/looks`, out of the golden set, 2026-10-04)

A 26.6 inactive window draws every bordered button in a white 20 pt bezel with a hairline (mini
13, small 16, large 28; extra large is the regular), the same for prominent and destructive ones
(no accent in an inactive window: the label (38) everywhere, the borderless destructive label
grey), the disabled labels at (191) (30 % of the label over white) and a disabled plain label at
(147) (50 %). The runtime keeps the 26.2 goldens' 24 pt bordered geometry and shifts the other
sizes by 26.6's differences; `ButtonLooksTests` hold the behaviour.

## Not yet covered

Keyboard shortcuts, `Label(_:systemImage:)` labels, the pressed look, the macOS control sizes
and role colours against an active 26.2 window, `ButtonRepeatBehavior`, the glass styles.
