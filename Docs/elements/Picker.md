# Picker

Apple docs: [Picker](https://developer.apple.com/documentation/swiftui/picker),
[PickerStyle](https://developer.apple.com/documentation/swiftui/pickerstyle),
[pickerStyle(_:)](https://developer.apple.com/documentation/swiftui/view/pickerstyle(_:)),
[tag(_:)](https://developer.apple.com/documentation/swiftui/view/tag(_:)).

## API surface

| API | Notes |
|---|---|
| `Picker(_ titleKey:selection:content:)`, `Picker(_ title: S, selection:content:)`, `Picker(selection:content:label:)` | implemented |
| `Picker(sources:selection:…)`, `tag(_:includeOptional:)` | missing |
| `tag(_:)` | implemented as a layout value; a `ForEach` option without a tag uses its id |
| `PickerStyle`: `.automatic` (= pop-up on macOS), `.menu`, `.segmented`, `.radioGroup`, `.inline` (= radio group on macOS), `.palette` (= menu); `pickerStyle(_:)` | implemented; custom styles are not (Apple's protocol is closed) |
| Opening the pop-up menu | implemented through the presentation layer (`Docs/elements/Presentation.md`): a menu of the options below the button, the selected row checked; a row press selects and closes, a press outside closes (look approximate) |
| Segmented and radio selection by press | implemented |
| `labelsHidden()`, `disabled(_:)` | implemented (hidden: control only; disabled: lighter fill, dimmed titles, presses ignored) |
| Option images, `Label` options, `Divider` in menus, `Section` in menus, keyboard navigation | missing (options contribute their text only in the pop-up and segmented styles) |

## Behaviour

`Picker` is a composite whose body reads the selection (so observation tracks it) and the
`PickerStyle` environment, then hands `_PickerHost` the label, the content and a setter.
`PickerNode` mounts the label (body font, dimmed when disabled) and the content, and walks the
content's layout leaves through `ForEach` entries and unary-modifier proxies (`_collectOptions`)
to find the options and their tags. For the pop-up and segmented styles it never lays the option
views out: like `NSPopUpButton` and `NSSegmentedControl` it shows each option's text (the joined
`Text` descendants) in its own title nodes, so probes inside such options are not recorded, as
with Apple. The radio group lays the option views out on rows. A press on a segment or a radio
row calls the setter; a press on the pop-up presents a `_MenuList` of the titles as a menu.

## Measured (macOS 26.2, `picker/basic`, `picker/forms`, `picker/steps`, 2026-09-02)

| Property | Value | Probe |
|---|---|---|
| Label | body font (18.5 line), 8 pt before the control, centred on the pop-up and segmented control, on the first row's baseline for the radio group; the whole picker is its natural size (a `frame(width: 200)` centres it) | `menu` 128.5 wide, `fixed`, pixels |
| Pop-up button | 24 pt tall, width = 12 + widest option + 47.5 (92.5 for "Banana"), fill black 20/255, 6 pt corners, the selected title 12 pt in in the 13 pt point font on the 4 pt line, up/down chevrons 7 wide 10.5 pt before the trailing edge (feet 1 pt above/below the centre line, 3.5 rise, 1.5 stroke, black 216/255); the width follows the widest option, not the selection | `menu`, `menuHidden` (92.5 × 24), `picker/steps` |
| Pop-up disabled | fill black 10/255, title and chevrons at 73/255 | `disabled` |
| Segmented control | 24 pt tall, equal segments of the widest option + 21 (66 for "Banana": 198 for three, 132 for two), fill 20/255 with 6 pt corners, selected segment a 6 pt pill at 50/255, titles centred in the 13 pt point font at black 137/255 (selected 152/255), 1 pt dividers at 43/255 between unselected neighbours (extent approximate) | `segmented` 234 wide, `fixedSegmented`, `picker/steps` |
| Radio group, inline | rows of a 16 pt circle (fill 25/255, selected 36/255 with a 5 pt dot at 216/255) 5 pt before the body-font option, rows 6 pt apart; group width 102 = label 28 + 8 + 16 + 5 + 45, height 3 × 18.5 + 2 × 6 = 67.5 | `radio`, `radioApple` (100, 152.75), `inline` |
| Custom label | a `Label` keeps its own layout (24 icon + 8 + text) and the row grows to 24 | `labelPicker` 160.5 × 24 |
| In a row | centred with a text and a button: pop-up 92.5 wide next to "Row" and "OK" | `row`, `rowPicker`, `rowButton` |
| Selection change | the pop-up title, the selected segment and the radio dot follow the model | `picker/steps` steps |

## Verification (2026-09-02)

Tier A: 3 fixtures exact (`picker/steps` steps included). Tier B, frames exact: Chromium
≤ 0.92 % pixels, WebKit ≤ 0.49 %; Firefox 0/5 with every mismatch the 0.5 pt narrower "Fruit"
(x 43.25 vs 43, widths 128 vs 128.5: the `Vegetables` glyph-hinting class), pixels ≤ 1.46 %.
wasm js tests pass.

## Not yet covered

The real menu look (highlighted rows, separators), the focused (accent) look of segmented and radio
controls (goldens come from an unfocused window: grey), image and `Label` options, menu
sections and dividers, keyboard navigation, `palette` icons, `Picker(sources:)`.
