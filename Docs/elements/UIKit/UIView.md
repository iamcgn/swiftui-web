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

## Looks against pixels (`uikit/view/layers`, `uikit/view/looks`, iPhone SE simulator, iOS 26, 2026-10-09)

Every painted look of `uikit/view/layers` matches the simulator within edge antialiasing (each
element's differing pixels sit on its edges; the plain and shadowed views are exact; 0.2 %
overall), and `uikit/view/looks` adds the rest (0.3 %):

- A `shadowPath` casts the shadow instead of the layer's composite, in the layer's background
  colour under the layer (a white view's oval path shows only where it reaches past the
  view); a transparent layer's shadow path casts nothing (open). A shadow colour and tight
  offset (`systemBlue` at 0.6, radius 2, offset 3) match; a container with a clear background
  casts its rounded child's shadow.
- Borders: a 0.5 pt hairline on a 10 pt corner, a 4 pt border on a capsule (`cornerRadius`
  half the height) and a 3 pt border on a continuous 20 pt corner all draw inside the bounds
  as strokes centred half the width in, with the corner radius less half the width.
- A corner radius past half a side is not clamped: CoreAnimation lays the quarter arcs out
  as if they fit, the edges run backwards and the nonzero fill is a lens with pointed ends
  about 1.3 in (`cornerRadius` 40 on 80 × 60); `UIKitWeb` builds that path explicitly
  (`CALayer.unclampedCornerPath`) for a circular corner, as the painter's rounded rectangles clamp.
- Group opacity: a view at `alpha` 0.5 composites its overlapping children once (no double
  blending where they overlap).
- `layer.mask`: a `CAShapeLayer` mask (its path's alpha) clips the layer's fill, border and
  sublayers, through the substrate's mask group.

Open: `draw(_:)` (see Drawing.md); animations (Phase 3); a transparent layer's shadow path;
masks with `contents`.

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
appearance. The dark appearance's tints, fitted the same way to `uikit/dark/materials`:
ultra thin 72, 77, 78 @ 0.46; thin 40, 41, 48 @ 0.57; material 36, 37, 40 @ 0.72; thick 31, 30,
34 @ 0.92; chrome 28, 29, 30 @ 0.61 with the ground saturated by 1.3; regular 27, 29, 30 @
0.73; light 245, 255, 255 @ 0.32; dark 24, 27, 28 @ 0.73 (1.6 % off). A vibrancy effect view
is a transparent container: its content draws in its own colours (the simulator's vibrant
label was 7/255 black over the material, the label colour). Pixels: `uikit/view/materials`
1.1 % off the simulator (the blur kernels differ at the band edges).

The glass platters (`GlassPainter`: the tab bar's pill, bar buttons, the floating toolbar and
search field, the search cancel circle) are now that blur (sigma 20) under white at 31 %
(the 252 the UIKit goldens measured over white; the pill over yellow in
`ios/representable/hostingsafearea-tabs` within tolerance, 5.6 → 2.3 %), the selected tab's
lens black at 7.5 % over it; the SwiftUI iOS tab bar's capsule takes the same blur and tint.
iOS 26's refraction and highlight rim are not drawn (approximate).

## Appearance proxies (uk-appearance, 2026-10-12)

`UIView.appearance()` and `appearance(whenContainedInInstancesOf:)` return a
`UIAppearanceProxy<T>` whose dynamic member lookup records every settable key path
(`UILabel.appearance().textColor = .red`); reading one gives the recorded value (a property
nothing recorded traps: UIKit's nil has no key-path equivalent). `_UIAppearanceRegistry`
applies the entries to a view as it enters a window (`didMoveToWindow`), writing over values
set earlier as UIKit does: the entries of the view's class and superclasses in recording
order, then the contained ones whose containers (view and view controller classes) appear in
order along the responder chain. `UIView` and `UIViewController` are `UIAppearanceContainer`s;
bar items are not proxied. `AppearanceTests`.

## Scenes and the lifecycle (uk-scenes, 2026-10-12; `App/UIScene.swift`)

One `UIWindowScene` stands for the host's page or window (`UIKitScene.windowScene`,
`UIApplication.connectedScenes`); `UIWindow(windowScene:)` joins it and every window's
`windowScene` is it. A scene delegate class set on `UIApplication.sceneDelegateType` (what the
scene manifest names) is created at launch and connected (`scene(_:willConnectTo:options:)`,
with the page's URL as a `UIOpenURLContext`); its `window` is made key and visible. The host's
`hostIsVisible` and `hostIsFocused` drive `UIApplication.applicationState` and the scene's
`activationState`: losing focus resigns active (`sceneWillResignActive`,
`applicationWillResignActive`, the notifications), hiding the page enters the background,
showing it enters the foreground, focus activates — `UIScene` and `UIApplication` notifications
post on `NotificationCenter.default` in UIKit's order (scene first, then the app).
`UIFeedbackGenerator` and its impact, selection and notification kinds are no-ops (a page has
no haptics). `SceneLifecycleTests`.

