# UIStackView

`Packages/UIKitWeb/Sources/UIKitWebCore/Controls/UIStackView.swift`. Fixture `uikit/stack/basic`:
a leading-aligned column of labels sized with `systemLayoutSizeFitting`, a row of two system
buttons filling 288 equally, a centre-aligned column.

## API

`init(arrangedSubviews:)`, `arrangedSubviews`, `addArrangedSubview`, `insertArrangedSubview`,
`removeArrangedSubview`, `axis`, `spacing`, `setCustomSpacing(_:after:)`, `distribution` (`fill`,
`fillEqually`, `fillProportionally`, `equalSpacing`, `equalCentering`), `alignment` (`fill`,
`leading`/`top`, `center`, `trailing`/`bottom`; the baseline alignments fall back to centre),
`isLayoutMarginsRelativeArrangement`, `layoutMargins`, `systemLayoutSizeFitting`,
`intrinsicContentSize`. Hidden arranged subviews take no room.

## Measured

- A vertical stack of three 17 pt labels with 8 pt spacing fits 89 × 77.5 (the widest label by
  20.5 + 8 + 20.5 + 8 + 20.5); leading alignment gives each label its own width.
- Two buttons filling 288 equally with 8 between: 140 each, the second at 148.
- Centre alignment places a 65.5-wide label in a 125-wide stack at 30, not 29.75: Auto Layout
  rounds the placement to the pixel grid in the stack's own coordinates (on Catalyst, where the
  stack sat at x 95.25, the rounded offset put the label at 126.25, off the absolute grid).

Open: the baseline alignments, `fillProportionally` against real UIKit, compression when the
content overflows, spacing after hidden views.
