# Auto Layout

`Packages/UIKitWeb/Sources/UIKitWebCore/Layout/` (decision 0014, Phase 3): `Cassowary.swift` (the
solver), `NSLayoutConstraint.swift` (constraints, anchors, layout guides, the view-side API),
`LayoutEngine.swift` (one solve per layout pass). Fixtures `uikit/autolayout/*`
(`Fixtures/UIKit/AutoLayout`), goldens from UIKit's engine on the iPhone SE simulator, all exact
in `UIKitGoldenFrameTests`; `AutoLayoutTests` holds the mechanics.

## API

- `NSLayoutConstraint`: `init(item:attribute:relatedBy:toItem:attribute:multiplier:constant:)`,
  `firstItem`/`firstAttribute`/`relation`/`secondItem`/`secondAttribute`/`multiplier`,
  `constant` and `priority` (changing either re-solves), `identifier`, `isActive`,
  `activate(_:)`, `deactivate(_:)`; `Attribute` (edges, leading/trailing, size, centres,
  baselines, the margin attributes), `Relation`, `Axis`. `constraints(withVisualFormat:…)`
  returns nothing (the format language is not parsed).
- Anchors: `NSLayoutAnchor` (`constraint(equalTo:)`, `greaterThanOrEqualTo`, `lessThanOrEqualTo`,
  each with `constant:`), `NSLayoutXAxisAnchor` / `NSLayoutYAxisAnchor` (the system-spacing
  forms at 8 pt), `NSLayoutDimension` (`equalToConstant`, `multiplier:`, `multiplier:constant:`
  and the inequalities). `UIView`'s `leading/trailing/left/right/top/bottom/width/height/centerX/
  centerY/firstBaseline/lastBaselineAnchor`.
- `UILayoutGuide` (`owningView`, `identifier`, `layoutFrame`, anchors), `UIView.addLayoutGuide`,
  `removeLayoutGuide`, `layoutGuides`, `safeAreaLayoutGuide`, `layoutMarginsGuide`,
  `readableContentGuide` (the margins guide). A guide the app adds is a rectangle of its own
  in the tableau, placed only by the constraints on it; `layoutFrame` holds the solve.
- `UIView`: `translatesAutoresizingMaskIntoConstraints`, `constraints`, `addConstraint(s)`,
  `removeConstraint(s)`, `constraintsAffectingLayout(for:)`, `setNeedsUpdateConstraints`,
  `needsUpdateConstraints`, `updateConstraintsIfNeeded`, `updateConstraints` (overridable),
  `hasAmbiguousLayout` (false), `systemLayoutSizeFitting(_:)` and the fitting-priority form;
  `UIViewController.systemMinimumLayoutMargins`, `viewRespectsSystemMinimumLayoutMargins`.

## How it works

A layout pass on a root (a window, a hosted tree's window, a fixture's root view) first runs
`updateConstraints` bottom-up where asked, then builds one Cassowary tableau for the subtree:
four variables per view (origin and size in its superview's coordinates); a view that
translates its autoresizing mask pins them to its frame; one that does not gets its intrinsic
size as `width <= intrinsic` at the hugging priority and `width >= intrinsic` at the
compression resistance (less its alignment insets) and non-negative sizes; every
`NSLayoutConstraint` held by a view relates attribute expressions in that view's coordinates
(a descendant's origin is the sum of the origins below the holder; a guide is its owner inset;
margins add the effective layout margins; a baseline is the label's line in its intrinsic
height, moving with the centring). Priorities become weights of 10^(p/100), required above.
The solution is written back to the constrained views as frames rounded to the pixel grid
(origin and far edges separately), then `layoutSubviews` runs top-down as before. A fresh
tableau per pass keeps the solver simple (no constraint removal); `systemLayoutSizeFitting`
solves the subtree alone with the target proposed at the fitting priorities.
`UIStackView` keeps its own arithmetic (it is not built on constraints here).

## Measured (iOS 26, iPhone SE simulator)

- `pins`: edges pinned with constants land exactly (16, 16, 288, 40); a 101 × 51 view centred in
  320 × 300 sits at (109.5, 124.5); a 34.5 × 20.5 view centred in a 99 × 51 container sits at
  (32.5, 15.5) in it: quarter points round to the pixel, halves up. `width = 2 × height` gives
  60 × 30. A label pinned at two edges takes its intrinsic size (93 × 20.5 for "Pinned label");
  pinned leading and trailing it is 288 wide and 20.5 tall.
- `priorities`: a width of 500 at 999 under a required `trailing <= −16` becomes 288; widths of
  200 at 250 and 100 at 750 give 100; `>= 100` at 750 against `= 50` at 999 gives 50, and
  `>= 100` at 999 against `= 50` at 750 gives 100. In a row with room to spare, the label
  hugging at 252 keeps its intrinsic width (218) and the one at 251 stretches (62 for "Short").
- `guides`: a view controller's root view has margins of 16 sideways and 0 vertically with no
  status bar (the system minimum replaces the 8 pt default; `systemMinimumLayoutMargins`);
  the safe area guide is the bounds; a plain container's margins guide is 8 in.
- `fitting`: `systemLayoutSizeFitting(compressed)` of a card holding two labels 8 in with 4
  between is 107.5 × 61 (the wider label plus 16, the two line boxes plus 20); fitted to a
  required 288 it is 288 × 61 and the trailing-pinned label stretches to 272.
- `baseline`: first baselines of 11, 13, 20, 28 and 34 pt labels on a 17 pt label's put their
  tops 5.5, 3.5, −3, −10.5 and −16.5 from its: a `UILabel`'s baseline is its ascender rounded
  to the pixel (10.5, 12.5, 16, 19, 26.5, 32.5), below the text rect's rounded top. A plain
  view's first baseline is its top and its last its bottom; a 20 pt label whose last baseline
  meets a box's bottom sits 19 above it.
- `update`: a constant changed from 16 to 100 moves the view on the next layout; deactivating a
  width and activating another resizes it.

Wrapping labels (2026-09-11, `uikit/table/selfsizing`): a label with `numberOfLines` other than
1 and no `preferredMaxLayoutWidth` measures unbounded on the first solve; when the solve gives
it less width than its text, that width becomes its layout width and the subtree solves again
with the wrapped height, as UIKit sets a multi-line label's preferred width since iOS 8 (both
in a layout pass and in `systemLayoutSizeFitting`). A wrapped label's intrinsic height is a
point more than its fit (two 15 pt lines fit in 36 and take 37; three 54 and 55; two 13 pt lines
31.5 and 32.5), a single line exactly its fit.

Stack views under constraints and their baseline alignments are measured in
`Docs/elements/UIKit/UIStackView.md` (`uikit/autolayout/stacks`).

## The rest (2026-10-09, `uikit/autolayout/layoutguides`, `uikit/autolayout/hugging`)

- Layout guides: two spacer guides of equal width between three fixed boxes in 288 take 49
  each; a 101 × 61 guide centred on (160, 110) has its frame at (109.5, 79.5) and a view inset
  8 in it at (117.5, 87.5, 85, 45); a guide a container owns, 10 and 30 in from its sides and
  half its height, is (10, 12, 160, 42) in it with a 20 pt box centred on it at (80, 23). All
  exact: a guide has four variables in its owner's coordinates like a view, and its
  `layoutFrame` is written after the solve, rounded to the pixel grid like a frame.
- Hugging and compression defaults, read from every control on the simulator (the probes are
  the priorities over 4): `UIView`, `UILabel`, `UIButton`, `UITextField`, `UIImageView`,
  `UITextView`, `UIScrollView` and `UIStackView` are 250 / 250 / 750 / 750 (horizontal and
  vertical hugging, then compression resistance); `UISlider`, `UISegmentedControl`,
  `UIProgressView` and `UIPageControl` hug vertically at 750; `UISwitch`, `UIStepper` and
  `UIActivityIndicatorView` are 750 everywhere. `UILabel`'s "251" is folklore: it is 250.
- The intrinsic content size is the alignment rect's size and the frame under constraints adds
  `alignmentRectInsets`: a segmented control's intrinsic size is 88 × 31 for "One" / "Two"
  (`sizeThatFits` 88 × 32) and its frame pinned by its leading and top edges is 88 × 32; a
  switch's intrinsic width is 66 under a 2 pt inset on the right and it is 68 wide pinned,
  fitted (`systemLayoutSizeFitting`, a frame-space size) or given any frame at all. A
  segment is the widest title rounded up plus 19 (44 for "One", 55 for "Three"). `UIStackView`
  reports no intrinsic content size (UIKit keeps its content size in its own constraints;
  here `_contentSize` is what the solver, a stack around it and its fitting size use); an
  empty `UILabel` is 0 × 0; a `UIProgressView` keeps its 4 pt whatever frame it is given.
- Animated constraints: a constant changed before `layoutIfNeeded()` inside `UIView.animate`
  moves the model at once and tweens the presented frame over the duration
  (`AutoLayoutRestTests`); UIKit's `layoutIfNeeded` in a block does the same.
- Large trees: the solver's column index keeps a substitution and a pivot to the rows holding
  the symbol; 1,000 constraints over 400 views (a 200-row chain) build and solve in 0.27 s in a
  debug build (5.6 s before), one tableau per pass.

Open: the switch's and the segmented control's alignment rects under SwiftUI's representables
follow the same intrinsic sizes (verified by `ios/representable/*`); a tableau per pass stays
(no incremental edits), so a pass over thousands of constraints is still linear in their
occurrences.

## Visual format language (2026-09-11, `uikit/autolayout/visualformat`)

`NSLayoutConstraint.constraints(withVisualFormat:options:metrics:views:)` parses Apple's grammar:
`H:` / `V:`, `|` for the superview, `[view]`, `[view(80)]`, `[view(>=60@750)]`, `[view(==other)]`,
connections `-` (the standard spacing: the superview's layout margins for `|-` and `-|`, 8 between views), `-x-`, `-metric-`
and `-(>=8@750)-`, and the alignment options (`alignAllTop` … `alignAllFirstBaseline`) that tie
every view in the format to the first; `directionLeftToRight` uses left and right instead of
leading and trailing. The fixture's four formats land a, b, c and d at (16, 20, 80, 40),
(104, 20, 200, 40), (16, 72, 288, 30) and (180, 114, 120, 24), exact against UIKit: `|-[c]-|` sits on
the root view's 16 pt margins, not 20 in from the edges. A format that
does not parse prints the fault and yields nothing (UIKit raises an exception).
