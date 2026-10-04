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
| `Toggle(sources:isOn:label:)`, `Toggle(_:sources:isOn:)`, `isMixed` | implemented (2026-10-04): on when every source is on, mixed (a dash in the checkbox) when they disagree; a flip writes to every source, a mixed toggle turning on |
| `ToggleStyle`, `ToggleStyleConfiguration` (`label`, `isOn`/`$isOn`, `isMixed`), `toggleStyle(_:)` | implemented; custom styles work through `Toggle(configuration)` |
| `.automatic` / `DefaultToggleStyle` (= checkbox on macOS), `.checkbox`, `.switch`, `.button` | implemented; the on/off look is measured, the pressed look is not |
| `labelsHidden()` | implemented (checkbox and switch drop the label and its spacing) |
| `disabled(_:)`, `EnvironmentValues.isEnabled` | implemented: no activation, dimmed control and label; buttons stop firing too |
| Space, Return | implemented: the focused toggle flips (the runtime's generic activation) |
| Focus ring | implemented, approximate: the accent ring around the checkbox or switch, not the label (`_FocusRingProviding`) |
| Hover | no change, as on macOS |
| `controlSize` | implemented, approximate: 12 / 14 / 16 / 18 pt checkboxes for mini / small / regular / large with 9 / 11 / 13 / 13 pt labels, 36 × 16 and 45 × 20 mini and small switches (from macOS 26.6's differences, "macOS 26.6" below); iOS keeps its one switch |
| `tint` | implemented: the iOS switch's on track; on macOS the checkbox and switch of an active window (`Runtime.windowIsActive`, off by default as the goldens are inactive windows: the accent fill with a white mark, approximate) |
| Switch knob shadow | implemented: two 1 pt rings of black at 4.5 % around the knob (toggle/styles pixels: the track reads 51/255 next to the knob, 44 two points away, over its 36) |

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

## Verification (2026-09-02; 2026-10-04 for the looks)

Tier A: 3 fixtures exact (`toggle/steps` steps included). Tier B, frames exact: Chromium ≤ 0.44 %
pixels, WebKit ≤ 0.19 %, Firefox ≤ 0.42 %. With the knob shadow (2026-10-04) Tier C reads
`toggle/styles` at 0.19 %; `ToggleLooksTests` cover the sources, the mixed dash and its flip,
Space, the ring on the control, the control sizes, the tint, the knob shadow and the
active-window accent.

## macOS 26.6 (`toggle/looks`, out of the golden set, 2026-10-04)

A 26.6 inactive window draws a 14 pt checkbox in a white bezel with a hairline (mini 10, small
12, large 16; labels 9 / 11 / 13 / 13 pt), a 2 pt dash across the middle for the mixed state,
and a 22 pt switch with a round 20 pt knob (mini 15 with a 13 pt knob, small 18 with 16; large
is the regular); a tint shows nothing in an inactive window. The runtime keeps the 26.2
goldens' 16 pt checkbox and 54 × 24 switch and shifts the other sizes by 26.6's differences;
`ToggleLooksTests` hold the behaviour.

## Not yet covered

The pressed look, the macOS control sizes, tint and active-window accent against an active
26.2 window, a mixed switch (iOS has none), `ToggleStyle` for the mixed state in custom styles.

2026-09-04 (`groupbox/basic` `content`): a checkbox directly under a text sits 6 below it, its own
spacing replacing the text's 8.15, so the toggle declares that value in the text-to-text category
(where the lower neighbour's value applies); a text field under a text keeps the text's 8.15.
