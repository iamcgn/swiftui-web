# UIView and CALayer

`Packages/UIKitWeb/Sources/UIKitWebCore/Views/UIView.swift`, `Layers/CALayer.swift`. Fixtures
`uikit/view/layers` (backgrounds, corner radii, a border, alpha, a rotation, clipping, a shadow,
a continuous corner, masked corners) and `uikit/view/autoresizing` (masks applied when the
container is resized after the subviews were placed).

## API

The tree (`addSubview`, `insertSubview` at, above, below, `removeFromSuperview`, `bringSubviewToFront`,
`sendSubviewToBack`, `exchangeSubview`, `isDescendant(of:)`, `superview`, `subviews`, `window`),
geometry (`frame`, `bounds`, `center`, `transform`, `autoresizingMask`, `convert` points and
rects to and from any view), the layout cycle (`setNeedsLayout`, `layoutIfNeeded`, `layoutSubviews`,
`sizeThatFits`, `sizeToFit`, `intrinsicContentSize`, `invalidateIntrinsicContentSize`,
`systemLayoutSizeFitting`, content hugging and compression priorities, `layoutMargins`,
`safeAreaInsets`), appearance (`backgroundColor`, `alpha`, `isHidden`, `isOpaque`, `clipsToBounds`,
`tintColor`, `layer.cornerRadius`, `cornerCurve`, `maskedCorners`, `borderWidth`, `borderColor`,
`shadowColor`, `shadowOpacity`, `shadowRadius`, `shadowOffset`, `opacity`, `mask`), traits and
appearance overrides, hit testing, gesture recognizers, accessibility properties.

## Measured

- Frames are what was set: an 80 × 60 view at (16, 16) reports exactly that; corner radii,
  borders and shadows do not change the frame.
- A rotated view's `frame` (and any rect converted through a rotation) is the bounding box of
  the transformed bounds: 80 × 60 turned by π/8 about its centre reports 96.87 × 86.05 at
  (103.56, 78.98). The layer fixtures are identical on the iPhone and on Catalyst.
- A clipped subview keeps its own frame (the pink overflow view at (40, 30) inside the teal one).
- Autoresizing against a container that grows from 200 × 100 to 288 × 160: flexible width keeps
  the 10 pt margins (268 wide); flexible left and top margins pin a view to the bottom right
  (at 238, 120 for 40 × 30 with 10 pt margins); all four margins flexible keep the view centred
  (124, 70 for 40 × 20).

Drawing: `draw(_:)`, `UIBezierPath` and the graphics context are in `Docs/elements/UIKit/Drawing.md`.
Constraints: `translatesAutoresizingMaskIntoConstraints`, anchors, `constraints`, `updateConstraints`,
the layout guides and `systemLayoutSizeFitting` over the solver are in `Docs/elements/UIKit/AutoLayout.md`.

Open: pixel comparison of the painted corners, borders, shadows and the continuous corner
against these goldens; `draw(_:)`; animations (Phase 3).
