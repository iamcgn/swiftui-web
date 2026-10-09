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

## Hover and pointer interactions (2026-09-18, `Events/Hover.swift`, `HoverTests`)

A pointer move without a press hovers the view under it (`UIKitScene.pointerMoved` routes
presses to the touches and the rest to a `HoverRouter`; `pointerLeft` ends every hover).
`UIHoverGestureRecognizer` on the hit view and its superviews: `began` when the pointer enters
the view, `changed` on every move inside, `ended` when it leaves, `location(in:)` the pointer's
position. `UIView.addInteraction` / `removeInteraction` / `interactions` with `UIInteraction`;
`UIPointerInteraction` asks its delegate for the region and the `UIPointerStyle` (`.system()`,
`.hidden()`, a shape: beams and paths, or an effect over a `UITargetedPreview` of the view)
when the pointer is over its view, with `willEnter` / `willExit` on region changes; the style
maps to the cursor the host shows (`UIKitScene.pointerCursor`: `text`, `vertical-text`,
`pointer`, `none`, or nothing for the system style). `UIButton.isPointerInteractionEnabled`
shows the hand. The pointer's own morphing over a hover-effect view is not drawn: the browser
has a cursor, not a pointer shape. A hosted tree (`UIKitHostedTree.hover(at:)`) hovers the same
way from its host's pointer and reports its cursor (`ios/representable/hover`).

## Materials: UIVisualEffectView (`uikit/view/materials`, iPhone SE simulator, iOS 26, 2026-10-09)

`Views/UIVisualEffectView.swift`. `UIBlurEffect(style:)` (every system and plain style),
`UIVibrancyEffect(blurEffect:style:)`, `UIVisualEffectView(effect:)` with its `contentView`
and `effect`. The view blurs what lies beneath it and tints it: the substrate's new
`backdropBlur` command (a Gaussian of the painted ground within the view's path, the layer's
corners included, keeping its alpha, optionally saturated) followed by a flat tint; the
content view draws over both. The native painter blurs a shrunken snapshot of the ground
(the sigma about four pixels) and draws it back smoothly; the canvas host copies its target,
blurs with the browser's filter and draws the box back clipped to the path.

Fitted to the simulator's capture of each style over black, systemBlue, white and systemRed
bands (a least-squares fit of a Gaussian of the ground mixed with a flat tint; the system
materials within 3–5 of 255 rms, the plain styles within 5 once the ground is saturated):

| Style | Sigma (pt) | Light tint (rgb @ alpha) | Ground saturation |
|---|---|---|---|
| `systemUltraThinMaterial` | 20 | 222, 222, 226 @ 0.44 | 1 |
| `systemThinMaterial` | 32 | 245, 250, 252 @ 0.56 | 1 |
| `systemMaterial` | 28 | 245, 249, 249 @ 0.78 | 1 |
| `systemThickMaterial` | 32 | 246, 248, 249 @ 0.93 | 1 |
| `systemChromeMaterial` | 32 | 255, 255, 255 @ 0.73 | 1 |
| `regular`, `light` (`prominent`, `extraLight` approximate) | 24 | 239, 239, 255 @ 0.33 | 1.6 |
| `dark` | 16 | 25, 26, 29 @ 0.73 | 1 |

The `…Light` and `…Dark` material styles use the light and dark tints whatever the
appearance; the dark appearance's tints are approximate (unmeasured). A vibrancy effect view
is a transparent container: its content draws in its own colours (the simulator's vibrant
label was 7/255 black over the material, the label colour). Pixels: `uikit/view/materials`
1.1 % off the simulator (the blur kernels differ at the band edges).

The glass platters (`GlassPainter`: the tab bar's pill, bar buttons, the floating toolbar and
search field, the search cancel circle) are now that blur (sigma 20) under white at 31 %
(the 252 the UIKit goldens measured over white; the pill over yellow in
`ios/representable/hostingsafearea-tabs` within tolerance, 5.6 → 2.3 %), the selected tab's
lens black at 7.5 % over it; the SwiftUI iOS tab bar's capsule takes the same blur and tint.
iOS 26's refraction and highlight rim are not drawn (approximate).

