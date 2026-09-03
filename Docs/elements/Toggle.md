# Toggle

Apple docs: [Toggle](https://developer.apple.com/documentation/swiftui/toggle),
[ToggleStyle](https://developer.apple.com/documentation/swiftui/togglestyle),
[ToggleStyleConfiguration](https://developer.apple.com/documentation/swiftui/togglestyleconfiguration),
[labelsHidden()](https://developer.apple.com/documentation/swiftui/view/labelshidden()),
[disabled(_:)](https://developer.apple.com/documentation/swiftui/view/disabled(_:)).

## API surface

| API | Notes |
|---|---|
| `Toggle(isOn:label:)`, `Toggle(_ titleKey:isOn:)`, `Toggle(_ title: S, isOn:)`, `Toggle(_:image:isOn:)`, `Toggle(_:systemImage:isOn:)`, `Toggle(_ configuration:)` | implemented (`systemImage` draws the stub symbol) |
| `Toggle(sources:isOn:)`, `isMixed` | missing (`isMixed` is always false) |
| `ToggleStyle`, `ToggleStyleConfiguration` (`label`, `isOn`/`$isOn`, `isMixed`), `toggleStyle(_:)` | implemented; custom styles work through `Toggle(configuration)` |
| `.automatic` / `DefaultToggleStyle` (= checkbox on macOS), `.checkbox`, `.switch`, `.button` | implemented; the on/off look is measured, the pressed look is not |
| `labelsHidden()` | implemented (checkbox and switch drop the label and its spacing) |
| `disabled(_:)`, `EnvironmentValues.isEnabled` | implemented: no activation, dimmed control and label; buttons stop firing too |
| Keyboard (space), focus ring, hover, `controlSize`, `tint` | missing |

## Behaviour

`Toggle` is a composite: its body asks the environment's `ToggleStyle` for a body and wraps it in
`_ToggleHost`, the primitive that owns hit testing and activation: a press released inside the
toggle's frame (label included) flips the binding; the accessibility overlay exposes a
`checkbox` role with `aria-checked`, and `activate(semanticsIdentifier:)` flips it too.
`_CheckboxControl` (16 × 16) and `_SwitchControl` (54 × 24) are rigid leaves painted from the
constants below; the button style is the bordered button's body, prominent when on.

## Measured (macOS 26.2, `toggle/basic`, `toggle/styles`, `toggle/steps`, 2026-09-02)

| Property | Value | Probe |
|---|---|---|
| Checkbox control | 16 × 16 (`labelsHidden` leaves exactly that) | `toggle/basic` `hidden` |
| Checkbox to label | 5 pt | `custom` (16 + 5 + 17.5 = 38.5) |
| Checkbox label font | `.body`: 18.5 pt line, baseline 14 (the toggle is 18.5 tall, first baseline 14) | `on`, `customText`, `baselineRow` |
| Checkbox vertical position | centred on the label's cap height: baseline − capHeight/2 = 14 − 4.58 → box top at 1.42 (pixel-rounded 1.5 at 2×) | pixels of `on` |
| Checkbox look | continuous corners ≈ 5 pt; fill black at 36/255 on, 25/255 off; check mark stroked 2 pt, round caps, black at 222/255, from (4, 8.75) via (6.75, 11.5) to (11.75, 5) | pixels of `on`, `off` |
| Disabled | label at 30 % of its alpha (66/216), box 13/255 off, ≈ 18/255 on, check ≈ 66/255 | `disabled`, `disabledOff` |
| Switch control | 54 × 24 capsule, black at 36/255 on and 25/255 off; white knob 32 × 20 inset 2 pt at the on or off end (its soft shadow is not drawn) | `toggle/styles` `switchHidden`, pixels |
| Switch layout | label first, 8 pt, then the switch; 24 tall, label `.body` | `switchOn` (49 + 8 + 54 = 111) |
| Button style | the bordered button geometry (label + 24 wide, 24 tall, 6 pt circular corners); on = accent fill with a white label, off = black at 19/255 | `buttonOn`, `buttonOff` |
| In an `HStack` with a button | the checkbox (18.5) centres against the 24 pt button and switch | `row` |
| Activation | the binding flips on release inside; the label text follows (`On`/`Off`) | `toggle/steps` |

## Verification (2026-09-02)

Tier A: 3 fixtures exact (`toggle/steps` steps included). Tier B, frames exact: Chromium ≤ 0.44 %
pixels, WebKit ≤ 0.19 %, Firefox ≤ 0.42 %.

## Not yet covered

Pressed and hovered looks, focus ring, keyboard toggling, `controlSize`, `tint`, mixed state,
`Toggle(sources:)`, the switch knob's shadow, the accent-coloured (active window) checkbox.
