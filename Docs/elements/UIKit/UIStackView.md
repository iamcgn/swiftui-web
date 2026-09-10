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

- A vertical stack of three 17 pt labels with 8 pt spacing fits 92.5 × 76 (the widest label by
  20 + 8 + 20 + 8 + 20); leading alignment gives each label its own width.
- Two buttons filling 288 equally with 8 between: 140 each, the second at 148.
- Centre alignment places a 68-wide label in a 129.5-wide stack at 31, not 30.75: Auto Layout
  rounds the placement to the pixel grid in the stack's own coordinates (the stack itself sat at
  x 95.25, so the label's absolute x is 126.25, off the grid).

Open: the baseline alignments, `fillProportionally` against real UIKit, compression when the
content overflows, spacing after hidden views.
