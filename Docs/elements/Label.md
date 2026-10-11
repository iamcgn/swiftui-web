# Label

Apple docs: [Label](https://developer.apple.com/documentation/swiftui/label),
[LabelStyle](https://developer.apple.com/documentation/swiftui/labelstyle),
[labelStyle(_:)](https://developer.apple.com/documentation/swiftui/view/labelstyle(_:)).

## API surface

| API | Notes |
|---|---|
| `Label(title:icon:)`, `Label(_ titleKey:image:)`, `Label(_ title: S, image:)` | implemented (images from the asset catalog, decision 0011; the harness shadows `Label(_:image:)` like `Image(_:)`) |
| `Label(_:systemImage:)` | implemented: the symbol's measured size, centred half a cap height (to the half point) above its baseline, drawn with a stand-in glyph (`Docs/elements/Image.md`) |
| `LabelStyle`, `LabelStyleConfiguration` (`title`, `icon`), `labelStyle(_:)` | implemented |
| `.automatic` / `DefaultLabelStyle` (= title and icon), `.titleAndIcon`, `.iconOnly`, `.titleOnly` | implemented |
| Context-dependent automatic style | implemented 2026-10-11: a label in a toolbar item shows its icon alone with the title as its help (`_AutomaticLabelContext.toolbar`, set by the toolbar chrome node; Apple's documented rule, the chrome lies outside the goldens); everywhere else title and icon |

## Measured layout rules (macOS 26.2, `label/basic`, 2026-09-02)

| Rule | Probe |
|---|---|
| Icon, 8 pt, title: a 24 pt image + 8 + "Title" (26.5) = 58.5; the label is as tall as the taller of the two (24, or 16 for a 12 pt icon) | `label`, `custom`, `tall` |
| The icon's vertical centre sits half a cap height above the title's first baseline (4.58 pt for the 13 pt font: `NSFont.capHeight` 9.16, now recorded per font in `text-metrics.json`): a 12 pt icon starts 2.42 below the top of a 16 pt title, a 40 pt icon puts the title 11.58 below its top | `customIcon`, `tallTitle` |
| The label's first text baseline is the title's, so a label in a baseline-aligned row sits on its text | `row`, `rowText` |
| `titleOnly` is the title alone (26.5 × 16), `iconOnly` the icon alone (24 × 24), `titleAndIcon` the automatic layout | `titleOnly`, `iconOnly`, `titleAndIcon` |
| Inside a bordered button the label keeps its layout and the button grows to 32: 4 pt above and below any label (`Docs/elements/Button.md`) | `button`, `buttonLabel` |

Inside a `List` row (`list/basic` `label`, 48.5 × 24) the icon gets a 16 pt slot it is centred in
(a 24 pt icon overflows 4 pt each side), 6 pt to the title, and the accent tint; the container sets
this through the `_labelIconLayout` environment (`Docs/elements/List.md`).

The same guide (`VerticalAlignment._iconCenter`) positions a checkbox against its label. A symbol
icon supplies its own guide (its baseline less half the font's cap height rounded to the half
point), so `Label("Star label", systemImage: "star")` is 16.08 tall at 13 pt (`symbol/basic` `label`).

## Verification (2026-09-02)

Tier A exact; Tier B frames exact, pixels ≤ 0.08 % in all three browsers.

## Corners (sw-label-forms, macOS 27, `label/corners`, 2026-10-11)

| Rule | Probe |
|---|---|
| A two-line title in a 180 pt label: the text wraps at 155.5 (180 − 16.5 − 8) to 148.5 wide, the pair (16.5 + 8 + 148.5 = 173) centres in the 180, the icon's centre half a cap above the first line's baseline | `wrapped`, `wrappedIcon`, `wrappedTitle` |
| A `Text` icon ("→", 12 × 16) sits at the same top as its title (its own baseline less half a cap aligns with the title's), 8 pt before the title: 56 × 16 | `textIcon`, `textIconTitle`, `textIconLabel` |
| `LabeledContent("Price", value: 12.5, format: .number)` in a grouped form: an 18.5 row, "12.5" in the secondary colour at the trailing edge; `.percent` gives "25%" | `number`, `percent` |
| A `Toggle` or `Picker` as the content stays a bare control at the trailing edge on the label's first text baseline: the 16 pt checkbox 1 below the row's top, the 24 pt pop-up 2.75 above it (the row 21.25 tall, from the label's top to the pop-up's bottom) | `toggle`, `toggleContent`, `picker`, `pickerContent` |
| The grouped form's content sits on the window's half-point grid and every `LabeledContent` row 0.125 lower in its cell (a form at y 106.04 has its first row at 136.125; probed at twelve offsets: round to the half point, then + 0.125) | `form`, `number`, `percent` |

Tier A exact (the control sizes aside), Tier B 1.0 %, Tier C within tolerance; `ToolbarTests`
check the toolbar's icon-only label.

## Not yet covered

SF Symbol glyphs (stand-ins), `Label` in `Menu` items (title and icon, unmeasured), macOS 27's
smaller controls inside grouped forms.
