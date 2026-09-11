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
  `readableContentGuide` (the margins guide).
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

Open: `UIStackView` on constraints (its baseline alignments),
constraints between a view and its own layout guides made with `addLayoutGuide` (their frames are
not solved yet), `contentHuggingPriority` defaults per control (UIKit's 250/750 with UILabel's
251 are modelled; others unverified), performance on large trees (one tableau per pass),
animation of constraint changes.

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
