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

Open: custom-type buttons (their title font is unmeasured; 17 pt is assumed), images and
`imagePlacement`, subtitles, `buttonSize`, the pressed look, pointer interactions, menus.
