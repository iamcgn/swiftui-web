# offset, rotationEffect, scaleEffect, transformEffect

Apple docs: [offset(x:y:)](https://developer.apple.com/documentation/swiftui/view/offset(x:y:)),
[rotationEffect(_:anchor:)](https://developer.apple.com/documentation/swiftui/view/rotationeffect(_:anchor:)),
[scaleEffect(_:anchor:)](https://developer.apple.com/documentation/swiftui/view/scaleeffect(_:anchor:)-pmi7),
[transformEffect(_:)](https://developer.apple.com/documentation/swiftui/view/transformeffect(_:)).

## API surface

| API | Notes |
|---|---|
| `offset(_:)`, `offset(x:y:)` | implemented (hit testing follows) |
| `rotationEffect(_:anchor:)` | implemented |
| `scaleEffect(_:anchor:)` (`CGSize`, scalar, `x:y:`) | implemented |
| `transformEffect(_:)` | implemented |
| `AnyTransition.scale`, `.scale(_:anchor:)` | implemented: the ghost scales about the anchor (2026-10-04) |
| Animating the parameters | implemented (`withAnimation`, `animation(_:value:)`) |
| `rotation3DEffect(_:axis:anchor:anchorZ:perspective:)` | implemented (2026-10-04), approximate: the painters apply the affine part of the rotation about the anchor (a turn about the vertical axis narrows the view by the cosine, about the horizontal axis flattens it, about the depth axis rotates it); `perspective` and `anchorZ` are accepted, the trapezoid of a perspective projection is not drawn. The harness cannot capture turns about the x and y axes (`transform/3d` holds the z turn) |
| `projectionEffect(_:)`, `ProjectionTransform` (`init(CGAffineTransform)`, `affine`, `concatenating`, `inverted`, `isAffine`, `CGPoint.applying`) | implemented: the affine part about the view's origin (`transform/3d` `projected`, exact) |
| `GeometryEffect` (`effectValue(size:)`, `animatableData`, `ignoredByLayout()`), `View.modifier(_: GeometryEffect)` | implemented: the effect's projection at the view's size, its affine part about the origin; a changed `animatableData` tweens under an animation (`transform/3d` `skewed`, exact) |
| Hit testing through rotations, scales, affine, projection and 3D effects | implemented: a press maps back through the effect's inverse (`hitTestTransform`), so a turned button is hit where it paints |

## Behaviour

Each effect is a `UnaryLayoutModifierNode` whose `paintTarget` wraps the target in
`save`/`concat`/`restore` (`DisplayCommand.concat`, painted by Canvas2D's `transform`). Rotation
and scale build their matrix about the anchor point in absolute coordinates (`aboutAnchor`);
`transformEffect` applies its matrix about the view's origin; offsets are translations. On an
update the node compares its parameter vector with the presented one and, under an animation,
records an `effect` tween (`NodePresentation.effect`) that `presentedEffect` reads while painting.
`OffsetNode.hitTestOffset` shifts hit testing, and `hitTest` no longer requires points to be
inside ancestor bounds (only `ScrollNode` clips, `clipsHitTesting`), so a view offset outside its
stack is still hit where it paints. Ghosts of removed views scale about their centre through
`presentedTransitionScale`.

## Measured (macOS 26.2, `transform/basic`, `transform/steps`, 2026-09-03)

| Property | Value | Probe |
|---|---|---|
| Layout is unaffected | every probe frame equals the untransformed layout (the row is 200 wide, the offset square's frame is still at 60) | all probes |
| Anchors and directions | a 30° rotation about `.topLeading` keeps that corner and turns clockwise (leftmost point 20 pt left); `scaleEffect(x: 2, y: 0.5, anchor: .bottom)` keeps the bottom edge; `transformEffect(translation 20, −4)` moves the pixels right and up | pixels of `anchored`, `stretched`, `affine` |
| Pixels | rotated, scaled and offset squares and rotated text within 0.11 % of Apple's | `transform/basic` |
| Animation | after `withAnimation` the frames are unchanged and the end state matches | `transform/steps` |

## Verification (2026-09-03)

Tier A: 2 fixtures exact (the animated step included). Tier B 3/3 in Chromium and WebKit
(≤ 0.11 %), Firefox off by the "Tilt" width hinting. `TransformTests` cover the concat matrices,
parameter tweens, hit testing through an offset and the scale transition. wasm js tests pass.

## 3D and projections (macOS 26.6, `transform/3d`, 2026-10-04)

A 45° turn about the depth axis, a projection skewing by half the height, and a custom
`GeometryEffect` skew: Tier A exact, Tier C 0.00 %. Turns about the x and y axes are out of the
golden set: the harness's `cacheDisplay` drops the layer Apple turns about the vertical axis and
draws the one turned about the horizontal axis untransformed at the window's origin.
`Transform3DTests` cover the affine parts of 3D rotations and projections, an animated geometry
effect, hit testing through a rotation and a scale, and the scale transition's anchor.

## Not yet covered

Perspective (3D turns draw their affine part), `anchorZ`, effects on ghosts other than scale.
