# Label

Apple docs: [Label](https://developer.apple.com/documentation/swiftui/label),
[LabelStyle](https://developer.apple.com/documentation/swiftui/labelstyle),
[labelStyle(_:)](https://developer.apple.com/documentation/swiftui/view/labelstyle(_:)).

## API surface

| API | Notes |
|---|---|
| `Label(title:icon:)`, `Label(_ titleKey:image:)`, `Label(_ title: S, image:)` | implemented (images from the asset catalog, decision 0011; the harness shadows `Label(_:image:)` like `Image(_:)`) |
| `Label(_:systemImage:)` | stub icon: `Image(systemName:)` has no size until the icon table lands |
| `LabelStyle`, `LabelStyleConfiguration` (`title`, `icon`), `labelStyle(_:)` | implemented |
| `.automatic` / `DefaultLabelStyle` (= title and icon), `.titleAndIcon`, `.iconOnly`, `.titleOnly` | implemented |
| Context-dependent automatic style (icon only in toolbars, etc.) | missing: always title and icon |

## Measured layout rules (macOS 26.2, `label/basic`, 2026-09-02)

| Rule | Probe |
|---|---|
| Icon, 8 pt, title: a 24 pt image + 8 + "Title" (26.5) = 58.5; the label is as tall as the taller of the two (24, or 16 for a 12 pt icon) | `label`, `custom`, `tall` |
| The icon's vertical centre sits half a cap height above the title's first baseline (4.58 pt for the 13 pt font: `NSFont.capHeight` 9.16, now recorded per font in `text-metrics.json`): a 12 pt icon starts 2.42 below the top of a 16 pt title, a 40 pt icon puts the title 11.58 below its top | `customIcon`, `tallTitle` |
| The label's first text baseline is the title's, so a label in a baseline-aligned row sits on its text | `row`, `rowText` |
| `titleOnly` is the title alone (26.5 × 16), `iconOnly` the icon alone (24 × 24), `titleAndIcon` the automatic layout | `titleOnly`, `iconOnly`, `titleAndIcon` |
| Inside a bordered button the label keeps its layout and the button grows to 32: 4 pt above and below any label (`Docs/elements/Button.md`) | `button`, `buttonLabel` |

The same guide (`VerticalAlignment._iconCenter`) positions a checkbox against its label.

## Verification (2026-09-02)

Tier A exact; Tier B frames exact, pixels ≤ 0.08 % in all three browsers.

## Not yet covered

SF Symbols, the automatic style's context sensitivity, `Label` in `List`/`Menu`/toolbars,
multi-line titles (the guide uses the first line), `Text`-only icons.
