# Form

Apple docs: [Form](https://developer.apple.com/documentation/swiftui/form),
[FormStyle](https://developer.apple.com/documentation/swiftui/formstyle),
[formStyle(_:)](https://developer.apple.com/documentation/swiftui/view/formstyle(_:)).

## API surface

| API | Notes |
|---|---|
| `Form(content:)` | implemented |
| `FormStyle`: `.automatic` (= columns on macOS in a hosted window), `.columns`, `.grouped`; `formStyle(_:)` | implemented; custom styles are not (Apple's protocol is closed) |
| `Section` in a form | columns: transparent (header and footer are plain rows); grouped: one card per section, header above and footer below (spacing unverified) |
| Controls as rows: `TextField`, `Toggle`, `Picker`, `Slider`, `Stepper`, `Button`, `Text` | implemented (see the measured table); other views sit in the control column |
| `LabeledContent`, `DisclosureGroup`, `GroupBox`, `formStyle` on nested forms, `scrollContentBackground`, `Form` scrolling indicators | missing (grouped forms scroll through `ScrollView`) |

## Behaviour

`Form` is a composite. `.columns` is a `_FormColumnsLayout` (a `Layout`) over the content: each
row's `HorizontalAlignment._formControlColumn` guide is where its control starts (its label's
width plus 8, the leading edge for rows without a label); the widest guide is the control column;
each row is proposed its own guide plus the control column's width and placed so the guides
meet, so a flexible control fills to the trailing edge while a fixed one keeps its width; rows
are spaced by the default stack spacing (`StackLayoutEngine.spacings`) and the layout is its
content's size, centred by its parent. Controls read the `_formStyle` environment the form sets
on its content and lay out as `_FormLabeledRow`s: label, 8, control (`FormLabeledRowNode`, which
reports the guide and takes its stack spacing from the control). `.grouped` is a `ScrollView`
around `_FormGroupedContent` (`FormGroupedNode`), which walks sections into cards and lays their
rows out with padding and separators; rows there are `.grouped` labelled rows, label leading and
control trailing, as tall as their label.

## Measured (macOS 26.2, `form/basic`, `form/sections`, `form/styles`, `form/steps`, 2026-09-02)

| Property | Value | Probe |
|---|---|---|
| Columns layout | labels right-aligned to the widest label ("Volume" 45), controls at 53; the form is 360 wide because the field and slider fill, 193.29 tall, centred in 320 | `form`, `field` (9.5…360), `picker` (17, 128.5 wide), `stepper` (8.5), `toggle`/`button`/`text` at 53 |
| Row spacing (default stack spacing) | text field ↔ toggle 6, toggle ↔ pop-up 6, pop-up → slider 8.15, slider → stepper 4.74, stepper → button 8.15, button → text 4.74, text → text 0, text → field 8.15, toggle → text 6, text → segmented 8.15, segmented → text 4.74: a checkbox toggle and a text field declare 6, a pop-up and a stepper the 13 pt text's 4.74 above / 8.15 below, a slider and a segmented control 4.74, a button the plain 8 (the text's distance next to text) | `form/basic`, `form/sections` |
| Text field row | label (body font, hidden by `labelsHidden`) on the field's 17 pt baseline: 24 tall, the field proposed the control column (307) | `field` |
| Slider row | 23 tall: the label in the 13 pt font (16 line) 7 pt down, the track 1 pt down and 307 wide | `slider` |
| Stepper, picker rows | the controls' own layout (label + 8 + control), placed so the control starts at the column | `stepper` (64.5 × 26), `picker` (128.5 × 24) |
| Toggle, button, text rows | in the control column (no label column part): checkbox toggle 70 × 18.5, bordered button 53.5 × 24, text 29.5 × 16 | `toggle`, `button`, `text` |
| Section headers and footers (columns) | plain default-font text in the control column, spaced like text | `optionsHeader` (43.5, 176.88), `optionsFooter` |
| A form without labels | its content's size: a lone toggle is 70 wide, centred by a `frame(width: 200)` | `narrowToggle` (145, 288.75) |
| Grouped card | fills its frame; a card inset 20 from every edge (20…340 in 360), black 8/255 with 10 pt corners (approximate); rows 300 wide at x = 30, 10 pt above and below the label's 18.5, 1 pt separators at 20/255 between rows (x 30…330); card height 78 for two rows | `grouped`, `groupedField` (30, 37, 300 × 18.5), `groupedToggle` (30, 76.5), pixels |
| Grouped text field | borderless, sized to its text and right-aligned at 330 ("Hello" at 297) | pixels of `form/styles` |
| Grouped toggle | a small 36 × 16 switch (approximate) with its trailing edge at 330, centred on the 18.5 row (overflowing it) | pixels of `form/styles` |
| Model changes | the toggle follows the model; an inserted text row re-lays the form out (48.5 → 72.65 tall) | `form/steps` steps |

## Verification (2026-09-02)

Tier A: 4 fixtures exact (`form/steps` steps included). Tier B, frames exact: Chromium ≤ 0.66 %
pixels, WebKit ≤ 0.45 %; Firefox 4/6 with the two failures the 0.5 pt narrower "Fruit" on the
picker rows (the known hinting class), pixels ≤ 0.75 %. wasm js tests pass.

## Not yet covered

Grouped section headers, footers and section spacing (unverified constants), the grouped
picker/slider/stepper/button rows (laid out by rule, no golden), `LabeledContent`,
`DisclosureGroup`, `GroupBox`, the grouped card's exact corner radius and the small switch's
exact size, forms in windows with a toolbar, keyboard focus order between rows.
