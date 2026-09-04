# LabeledContent

Apple docs: [LabeledContent](https://developer.apple.com/documentation/swiftui/labeledcontent),
[LabeledContentStyle](https://developer.apple.com/documentation/swiftui/labeledcontentstyle).

## API surface

| API | Notes |
|---|---|
| `LabeledContent(content:label:)`, `LabeledContent(_ title, content:)`, `LabeledContent(_ title, value: String)`, `LabeledContent(_ configuration:)` | implemented |
| `LabeledContentStyle`, `LabeledContentStyleConfiguration` (`label`, `content`), `.automatic`, `labeledContentStyle(_:)` | implemented |
| `labelsHidden()` | implemented: the content alone |
| `LabeledContent(_:value:format:)` (`FormatStyle` values) | missing |

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

## Not yet covered

`FormatStyle` values, the secondary colour of values in grouped forms (unmeasured), `Toggle`
and `Picker` inside `LabeledContent` in forms.
