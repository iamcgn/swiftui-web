# UIButton

`Packages/UIKitWeb/Sources/UIKitWebCore/Controls/UIButton.swift`. Fixture `uikit/button/basic`
(a system button, a disabled one, and the plain, gray, tinted and filled configurations, all
sized to fit); `uikit/stack/basic` shows two system buttons filling a row.

## API

`init(type:)`, `init(type:primaryAction:)`, `init(configuration:primaryAction:)`,
`setTitle(_:for:)`, `setTitleColor`, `setImage`, `title(for:)`, `currentTitle`, `titleLabel`,
`imageView`, `contentEdgeInsets`, `contentHorizontalAlignment`, `configuration` (`plain`, `gray`,
`tinted`, `filled`, and the `bordered*` names; `title`, `image`, `titleFont`, base colours,
`contentInsets`, `imagePadding`, `cornerStyle`), `isEnabled`, `isHighlighted`, `addAction`. A selector
cannot exist without an Objective-C runtime: `addTarget(_:action:for:)` takes a closure, and
apps use `UIAction`.

## Measured

| Button | Size | Inside |
|---|---|---|
| `UIButton(type: .system)`, "Tap" | 30 × 30 | a 15 pt title label (25 × 18) centred; 6 above and below the label; 30 is the minimum width ("Disabled" is 60 × 30, its label's width) |
| plain / gray / tinted / filled configuration, "Plain" | 60.5 × 40.5 | content insets 7 top and bottom, 12 leading and trailing; the title in the body style in a label without a line limit, 26.5 tall (the 24.5 body label plus its 1.7 pt leading, rounded up); the background's corner radius is drawn by `_UISystemBackgroundView`, not set on the layer, so it waits for the pixel pass (Catalyst put 17 on the layer) |
| in a 34 pt row | — | the label centred (8 down) |

The gray fill is `secondarySystemFill` (120, 120, 128 at 16 %). The same geometry held on Mac
Catalyst with its own text widths and a 31 pt system button (its 15 pt label is 19 tall there).

## Measured (iOS 26, `uikit/button/looks`, 2026-10-04)

| Button | Size | Inside |
|---|---|---|
| custom type, "Custom" | 63 × 34 | an 18 pt title (63 wide, 21.5 tall) in a button at least 34 tall; no padding sideways |
| gray, "Star" with a star image leading (`imagePadding` 6) | 89.5 × 40.5 | the medium 7 × 12 insets; the symbol in a 28 × 20 slot, its 23.5 × 22 glyph centred (overflowing the slot's height), then 6, then the body title (26.5 tall with its leading) |
| the same, image trailing / on top | 89.5 × 40.5 / 55.5 × 66.5 | trailing: title, 6, slot; top: slot, 6, title, each centred |
| filled, "Title" over "Subtitle" | 71 × 62.5 | the subtitle in the footnote (19 + 1 = 20 tall) 2 under the title, both left-aligned at the inset (the automatic alignment becomes leading with a subtitle); the width is the wider line plus 24 |
| gray, `buttonSize` mini / small / medium / large | 48.5 × 33 / 57.5 × 33 / 65.5 × 40.5 / 83.5 × 56.5 | mini and small: the subheadline (15 pt, 21 tall) in 6 × 10 insets; medium: the body (26.5) in 7 × 12; large: the body in 15 × 20 |
| system type, heart image + "Heart" | 65.5 × 23.5 | the symbol in a 22 × 23.5 slot 2 in (its 20.5 × 19 glyph centred), 3 to the 15 pt title; no padding above or below |
| filled, pressed (`isHighlighted`) | 86 × 40.5 | the fill at 75 % ((64, 166, 255)); the white title stays |
| filled and gray, disabled | 90.5 × 40.5 / 48.5 × 40.5 | the fill becomes the tertiary fill ((238, 238, 239)) under the tertiary label colour ((185, 185, 187) over it) |
| corners | — | iOS 26: the large size is a capsule; the other sizes round to 20 at most (a 40.5 pt button is nearly a capsule, a 62.5 pt one keeps 20); the gray fill is (233, 233, 234) with the label colour on it, not the tint |

`configurationUpdateHandler` runs on every state change (and `setNeedsUpdateConfiguration`),
`automaticallyUpdatesConfiguration` turns the automatic calls off, `updateConfiguration()` is
the overridable hook, `Configuration.updated(for:)` returns the configuration unchanged
(UIKit's state-dependent adjustments are what the handler is for here). Pixels: `uikit/button/looks`
within 3 % (text anti-aliasing and the symbols' strokes).

Open: `UIButton.Configuration` with `attributedTitle`, `showsActivityIndicator` (accepted),
`titleTextAttributesTransformer`, pointer interactions on buttons beyond the hand cursor. Menus
(`menu`, `showsMenuAsPrimaryAction`, `changesSelectionAsPrimaryAction`) landed 2026-10-04:
`Docs/elements/UIKit/Menus.md`.
