# PhaseAnimator, KeyframeAnimator, contentTransition, matchedGeometryEffect

Apple docs: [PhaseAnimator](https://developer.apple.com/documentation/swiftui/phaseanimator),
[phaseAnimator(_:content:animation:)](https://developer.apple.com/documentation/swiftui/view/phaseanimator(_:content:animation:)),
[KeyframeAnimator](https://developer.apple.com/documentation/swiftui/keyframeanimator),
[keyframeAnimator(initialValue:trigger:content:keyframes:)](https://developer.apple.com/documentation/swiftui/view/keyframeanimator(initialvalue:trigger:content:keyframes:)),
[KeyframeTimeline](https://developer.apple.com/documentation/swiftui/keyframetimeline),
[contentTransition(_:)](https://developer.apple.com/documentation/swiftui/view/contenttransition(_:)),
[ContentTransition](https://developer.apple.com/documentation/swiftui/contenttransition),
[matchedGeometryEffect(id:in:properties:anchor:isSource:)](https://developer.apple.com/documentation/swiftui/view/matchedgeometryeffect(id:in:properties:anchor:issource:)),
[Namespace](https://developer.apple.com/documentation/swiftui/namespace).

## API surface

| API | Notes |
|---|---|
| `PhaseAnimator(_:content:animation:)` (free-running), `PhaseAnimator(_:trigger:content:animation:)` | implemented |
| `View.phaseAnimator(_:content:animation:)`, `View.phaseAnimator(_:trigger:content:animation:)`, `PlaceholderContentView` | implemented |
| `KeyframeAnimator(initialValue:repeating:content:keyframes:)`, `KeyframeAnimator(initialValue:trigger:content:keyframes:)` | implemented |
| `View.keyframeAnimator(initialValue:repeating:content:keyframes:)`, `View.keyframeAnimator(initialValue:trigger:content:keyframes:)` | implemented |
| `Keyframes`, `KeyframesBuilder`, `KeyframeTrack(_:content:)` (key path, or the value itself), `KeyframeTrackContentBuilder` | implemented (if/else, optionals and loops in builders) |
| `LinearKeyframe(_:duration:timingCurve:)`, `CubicKeyframe(_:duration:startVelocity:endVelocity:)`, `SpringKeyframe(_:duration:spring:startVelocity:)`, `MoveKeyframe(_:)` | implemented |
| `KeyframeTimeline(initialValue:content:)`, `duration`, `value(time:)`, `value(progress:)` | implemented |
| `Spring` (`smooth`, `snappy`, `bouncy`, `duration:bounce:`), `UnitCurve` (`linear`, ease curves, `bezier`) | the subsets the keyframes need |
| `Animatable` for `Double`, `Float`, `CGFloat` (through `VectorArithmetic`) | added; `CGPoint`/`CGSize`/`CGRect` already conformed |
| `@Namespace`, `Namespace.ID`, `matchedGeometryEffect(id:in:properties:anchor:isSource:)`, `MatchedGeometryProperties` (`position`, `size`, `frame`) | implemented: a view arriving under an animation glides from the group's last frame while the retiring one glides to it; non-sources paint at the source's frame |
| `contentTransition(_:)`, `ContentTransition` (`identity`, `opacity`, `interpolate`, `numericText(countsDown:)`, `symbolEffect`), `EnvironmentValues.contentTransition` | implemented for `Text`: opacity, interpolate and symbolEffect crossfade, numericText crossfades with a vertical roll; images and other views snap |

## Behaviour

Both animators run on the runtime's animation clock through frame subscriptions, like
`TimelineView(.animation)`, so hosts drive them with the same `advanceAnimations(elapsed:)`
and headless tests step them deterministically.

- **PhaseAnimator** shows the first phase on appear. A free-running one steps to the next phase
  on the first frame; each step rebuilds the content for the new phase inside a transaction
  carrying `animation(phase)`, so whatever the content changes (frames, opacity, offsets,
  colours) tweens through the existing animation system, and the next step starts when that
  animation's total duration has elapsed (`repeatForever` animations therefore hold a phase).
  A triggered one steps through the remaining phases and back to the first on every change of
  `trigger`, then stops. Phases are compared as the sequence's elements; the trigger is any
  `Equatable`.
- **KeyframeAnimator** evaluates a `KeyframeTimeline` every frame and rebuilds its content with
  the value (no implicit animation: the keyframes are the motion). Without a trigger it plays on
  appear, once or, with `repeating`, wrapping at the timeline's duration; with a trigger it plays
  from the initial value on every change. Tracks run in parallel; the timeline's duration is the
  longest track's, and a track past its end holds its last keyframe.
- **Keyframe evaluation** (per track, over `AnimatableData`): linear interpolates through the
  `UnitCurve`; move jumps at the end of its (zero) duration; spring follows the spring's
  animation curve over the keyframe's duration (the spring's settling time by default), with a
  start velocity added as a decaying kick; cubic is a Hermite segment whose velocities come
  from the neighbouring keyframes (Catmull-Rom) unless given.

- **contentTransition** applies to `Text`. When a text's runs (strings or fonts) change during
  an update that carries an animation (`withAnimation`, an `animation(_:value:)` scope) and the
  environment's transition is not identity, the node keeps the previous text and paints it
  fading out at the same frame while the new text fades in, over the update's animation. Numeric
  text also rolls: the old text moves up by half the height and the new one arrives from below
  (reversed for `countsDown`). SwiftUI's `interpolate` morphs glyph weights and sizes and its
  numeric text rolls each digit separately; both are crossfades here. Changes without an
  animation, or under `.identity`, snap. Tested on the headless clock (`ContentTransitionTests`).

- **matchedGeometryEffect** keeps a registry on the runtime keyed by namespace and id; a
  source records its root frame and anchor after every layout. A follower (`isSource: false`)
  keeps its own layout size, as its parent sees it, but lays its content out differently
  (measured on `matched/anchors`, 30 cells of one source and one follower, 2026-09-05):
  - `.size` (and `.frame`) propose the source's size to the content, so a flexible follower
    becomes source-sized while a fixed frame keeps its size;
  - `.position` (and `.frame`) put the content's anchor point on the source's anchor point:
    `origin = sourceAnchorPoint − contentSize × anchor`;
  - `.frame` shifts the content once more by `(sourceSize − contentSize) × anchor` (SwiftUI's
    frame mode applies the anchor twice, so a fixed 80 × 20 follower of a 40 × 40 source with
    `.center` sits with its bottom-trailing corner on the source's);
  - `.size` alone leaves the content at the slot's origin.
  Painting and hit testing follow the content's real frame. Sources laid out after their
  followers are copied from the previous layout.
- **Arrival and departure**: when a matched view is placed for the first time in an update that
  carries an animation and the registry holds another view's frame, it starts a frame tween
  from that frame (its content scaling with the tween), and if that other view is retiring (a
  removal transition's ghost) the ghost's frame is set to the newcomer's and tweened from where
  it was, so an `if`/`else` swap under `withAnimation` glides both ways with the usual crossfade.
  `@Namespace` hands out one id per view instance and keeps it across body evaluations.

The goldens `animator/phase` and `animator/keyframe` capture the animators at rest (a trigger
that never changes): first phase and initial value, exact in Tier A/B/C.

## Open

- SwiftUI's spring keyframes integrate a real spring from the running velocity; ours follow a
  curve from the keyframe's start value, so back-to-back springs do not carry momentum.
- `PhaseAnimator` starts its first step one frame after appearing rather than at appear time.
- `contentTransition` for symbol images (`symbolEffect`), per-digit numeric rolls and a real
  `interpolate`.
- Matched geometry: several sources with one id (SwiftUI warns and picks one; here the last
  laid out wins); a source laid out after its follower is copied one layout late.
