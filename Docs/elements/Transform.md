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
| `AnyTransition.scale`, `.scale(_:anchor:)` | implemented (about the centre; the anchor is ignored) |
| Animating the parameters | implemented (`withAnimation`, `animation(_:value:)`) |
| `rotation3DEffect`, `projectionEffect`, `GeometryEffect` conformances, hit testing through rotations and scales | missing |

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

## Not yet covered

Hit testing through rotation and scale, `GeometryEffect`, 3D rotation, anchors for scale
transitions, effects on ghosts other than scale.
