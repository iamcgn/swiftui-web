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

Under constraints and on baselines (2026-09-11, `uikit/autolayout/stacks`): a stack placed
by constraints takes the solved frame and lays its arranged subviews out itself (the solver
sizes them but never places them, as UIKit's stack owns their constraints); an arranged view
with constraints of its own (a 40 pt box) is as big as they say. A horizontal stack's
`firstBaseline` / `lastBaseline` alignment meets the views' baselines: each sits so its first
(or last) baseline is at the row's deepest ascent (or its bottom less the deepest descent), and
the row is that ascent plus descent tall (a 28, 13 and 17 pt label row is 33.5 tall with the
13 pt label 14 down and the 17 pt one 10.5). A filled column pinned to the edges stretches its
labels to the width; a centred row centres a box beside a label. Frames exact, pixels 2.2 %.

Distributions measured (2026-10-09, `uikit/stack/distribution`, frames exact, pixels 4.6 %
of a text-dense page, approximate): `fillProportionally` gives each view its natural length
over the sum of the natural lengths *and the spacing* times the stack's length, rounded to
the pixel, and the last visible view what is left (labels 11.5, 61.5 and 123 wide with 8
between in 288 are 15.5, 83.5 and 173; a 60 pt column of 33.5, 20.5 and 14.5 pt labels with 4
between is 26.5, 16 and 9.5; a 112 pt one 49, 30 and 25). Too little room under `fill`,
`equalSpacing` and `equalCentering` keeps the spacing and shrinks the view with the lowest
compression resistance, the first among equals (126, 151 and 39.5 in 288 become 81.5, 151 and
39.5; at 749 the second becomes 106.5); room to spare under `fill` stretches the first among
equal huggers. A hidden arranged view takes no room and loses the spacing after it, the custom
spacing after the view before it stays (24 between "Before" and "After" with the hidden one
between); UIKit leaves the hidden view zero-length at the midpoint of that gap (at the
content's end when it is last), full across. Open: baseline alignments in vertical stacks
(UIKit ignores them), `UIStackView.sizeThatFits` (UIKit's is `UIView`'s: the bounds).

`systemLayoutSizeFitting` (2026-09-18): a stack's fitting size is its arranged content's
intrinsic total (a required target keeps its length), so a representable sized by it is 70 tall
for a 40 pt hosting view over a 30 pt constrained view (`ios/representable/hostingsizing`).
