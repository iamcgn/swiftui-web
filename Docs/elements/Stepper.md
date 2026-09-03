# Stepper

Apple docs: [Stepper](https://developer.apple.com/documentation/swiftui/stepper).

## API surface

| API | Notes |
|---|---|
| `Stepper(_ title:value:step:onEditingChanged:)`, `Stepper(_ title:value:in:step:…)`, `Stepper(value:step:label:…)`, `Stepper(value:in:step:label:…)` | implemented (`V: Strideable`; the bounded forms clamp) |
| `Stepper(_ title:onIncrement:onDecrement:onEditingChanged:)`, `Stepper(onIncrement:onDecrement:onEditingChanged:label:)` | implemented (`nil` closures do nothing) |
| `onEditingChanged` | implemented: `true` then `false` around each press |
| `labelsHidden()`, `disabled(_:)` | implemented |
| Press-and-hold repeat, keyboard control, `formatter`/`format` forms | missing |

## Behaviour

`Stepper` is a composite: the label (`_ControlLabel`, body font, dimmed when disabled) and the
`_StepperControl` primitive 8 pt apart in an `HStack`, each `_pixelAligned`. The stepper is its
natural size (a `frame(width: 200)` centres it). `StepperControlNode` is a 20 × 26 leaf that
paints the button pair and, on a press released inside, runs the increment action for the top
half and the decrement action for the bottom half.

## Measured (macOS 26.2, `stepper/basic`, `stepper/steps`, 2026-09-02)

| Property | Value | Probe |
|---|---|---|
| Size | label + 8 + 20 × 26: "Count" (body, 36.5) makes 64.5 × 26; hidden labels leave the 20 × 26 control | `basic`, `hidden` |
| Control | fill black 20/255 with 5 pt corners; up chevron from (4.5, 9.25) to (10, 4.25) to (15.5, 9.25), down chevron from (4.5, 17.25) to (10, 22.25) to (15.5, 17.25), 1.5 pt round strokes at black 137/255; a 1 pt divider at 43/255 across the middle, 3 pt in from each side | pixels of `basic` |
| Disabled | fill 10/255, chevrons 132/255, label dimmed | `disabled` |
| Label | body font, vertically centred (at +3.75, pixel-aligned to +4: "Count" baseline at row + 18) | pixels of `basic` |
| Custom label | a `Label` keeps its layout: 24 + 8 + 36.5 + 8 + 20 = 96.5 | `labelStepper` |
| In a row | centred with a text and a button; the button (24) sits 1 pt lower than the 26 pt control | `row`, `rowButton` (y + 1) |
| Value changes | the control looks the same; the echo text re-lays out the row | `stepper/steps` steps |

## Verification (2026-09-02)

Tier A: 2 fixtures exact (`stepper/steps` steps included). Tier B, frames exact in all three
browsers: Chromium ≤ 0.50 % pixels, WebKit ≤ 0.38 %, Firefox ≤ 0.63 %. wasm js tests pass.

## Not yet covered

Press-and-hold repeat, the pressed look of a half, keyboard control, formatted value forms.
