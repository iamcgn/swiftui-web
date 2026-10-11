# LabeledContent

Apple docs: [LabeledContent](https://developer.apple.com/documentation/swiftui/labeledcontent),
[LabeledContentStyle](https://developer.apple.com/documentation/swiftui/labeledcontentstyle).

## API surface

| API | Notes |
|---|---|
| `LabeledContent(content:label:)`, `LabeledContent(_ title, content:)`, `LabeledContent(_ title, value: String)`, `LabeledContent(_ configuration:)` | implemented |
| `LabeledContentStyle`, `LabeledContentStyleConfiguration` (`label`, `content`), `.automatic`, `labeledContentStyle(_:)` | implemented |
| `labelsHidden()` | implemented: the content alone |
| `LabeledContent(_:value:format:)` (`FormatStyle` values) | implemented 2026-10-11 through `Text(_:format:)` (`label/corners` `number`, `percent`) |

## Behaviour

`AutomaticLabeledContentStyle` puts the label through `_ControlLabel` (the body font, dimmed
when disabled) 8 before the content, both centred vertically in an `HStack`; the pair is as wide
as the two, so a wider frame centres it. Inside a columns `Form` the pair is a `_FormLabeledRow`
(the label right-aligned in the label column, the content 8 after the column), inside a grouped
form the label leads and the content trails.

## Measured (macOS 26.2, `labeledcontent/basic`, `labeledcontent/form`, 2026-09-04)

| Property | Value | Probe |
|---|---|---|
| Row | label (body, 18.5 line) + 8 + content; the content centred in the 18.5 line (a 16 pt text 1.25 down) | `value` (79.5 × 18.5), `count`, `countContent` |
| Custom label | any view (a 24 pt `Label` makes a 24 pt row) | `custom`, `customLabel`, `customContent` |
| `labelsHidden` | the content alone (41 × 16) | `hidden` |
| Width | a `frame(width: 160)` centres the pair (label at 37.25) | `narrow`, `narrowLabel`, `narrowContent` |
| Columns form | the label right-aligned in the label column, the content at the column + 8, 16 tall rows, 0 between two rows, 8.15 above a text field | `labeledcontent/form` `value`, `count`, `field` |

## Verification (2026-09-04)

Tier A: both fixtures exact. Tier B: ≤ 0.43 % Chromium, ≤ 0.18 % WebKit, ≤ 0.51 % Firefox; Tier C ≤ 0.18 %. `LabeledContentTests` cover
the row, the value initializer, hidden labels, widths, a custom style and the form column.

## Grouped forms (`label/corners`, macOS 27, 2026-10-11)

In a grouped form a labeled row is the body-styled label (an 18.5 line) with its content at
the trailing edge on the label's first text baseline (`_FormRowMode.groupedBaseline`): a text
value in the secondary colour, a `Toggle` or `Picker` as the bare control (not a form row of its
own; the 16 pt checkbox 1 down, the 24 pt pop-up 2.75 up and the row 21.25 tall to its bottom).
The form's content sits on the window's half-point grid and each of these rows 0.125 lower in
its cell than other rows (`_formRowTop`; Docs/elements/Label.md). The 2026-10-11 measurement
first came from a harness drawn with macOS's pre-26 controls (decision 0019); the golden was
regenerated and the model corrected the same day.

## Not yet covered

Nothing known.
