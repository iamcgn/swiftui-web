# UIView.animate

`Packages/UIKitWeb/Sources/UIKitWebCore/Layers/LayerAnimation.swift` (decision 0014, Phase 3);
`AnimationTests` holds the mechanics. Animations in flight cannot be captured as goldens
(Docs/ELEMENT_WORKFLOW.md), so the curves are UIKit's documented ones, not measured.

## API

`UIView.animate(withDuration:animations:)`, `animate(withDuration:delay:options:animations:completion:)`,
`animate(withDuration:delay:usingSpringWithDamping:initialSpringVelocity:options:animations:completion:)`,
`transition(with:duration:options:animations:completion:)` (the changes apply at once; the
completion runs after the duration), `performWithoutAnimation`, `setAnimationsEnabled`,
`areAnimationsEnabled`. The `curveEaseInOut` (default), `curveEaseIn`, `curveEaseOut` and
`curveLinear` options; `repeat`, `autoreverse` and `beginFromCurrentState` are accepted without
effect.

## How it works

The animation block runs with a recording group current: every animatable layer property set
inside it (`position`, `bounds`, `opacity`, `backgroundColor`, `transform`, `cornerRadius`,
`borderWidth`, `borderColor`, `shadowOpacity`; a view's `frame`, `center`, `alpha`,
`transform`, `backgroundColor` go through them) records its old and new value. The model takes
the new value at once, as in UIKit; painting reads the presented value, the interpolation at
the group's eased progress, while the group runs. The scene advances every group in
`advanceFrame(elapsed:)` (the hosts' frame clock; a hosted tree's through its node), reports
`isAnimating` while any runs, and calls the completion with `true` when one ends. A block that
animates nothing still waits the duration out before its completion. Nested blocks record into
the innermost. Curves: CSS's cubic-bezier for ease in-out (0.42, 0, 0.58, 1), ease in
(0.42, 0, 1, 1), ease out (0, 0, 0.58, 1); the spring is a damped oscillator settling at the
end of the duration (ζ = damping, ω = 6.9 / ζ, the initial velocity as UIKit scales it).

Open: `repeat`/`autoreverse`, `beginFromCurrentState` (a new block on a running property
starts from the model's value, not the presented one), `UIViewPropertyAnimator`, `CATransaction`,
`CABasicAnimation`/`CAKeyframeAnimation` added to layers, `layoutIfNeeded` inside a block
animating Auto Layout changes (it does: the constraint pass sets frames inside the block),
hit testing during an animation (the model's frame).

## Core Animation (2026-09-11)

`Layers/CAAnimation.swift`. `CABasicAnimation(keyPath:)` (`fromValue`, `toValue`, `byValue`),
`CAKeyframeAnimation` (`values`, approximate: first to last), `CAAnimationGroup` (stored),
`duration`, `beginTime` (a delay), `timingFunction` (`CAMediaTimingFunction` named or by
control points), `repeatCount`, `repeatDuration`, `autoreverses`, `fillMode`,
`isRemovedOnCompletion`, `delegate` (`animationDidStart`, `animationDidStop(_:finished:)`);
`CALayer.add(_:forKey:)`, `removeAnimation(forKey:)`, `removeAllAnimations`,
`animation(forKey:)`, `animationKeys()`. Key paths: `opacity`, `position` (`.x`, `.y`),
`bounds` (`.size.width`, `.size.height`), `transform` (`.scale`, `.rotation`), `cornerRadius`,
`borderWidth`, `backgroundColor`, `borderColor`, `shadowOpacity`. An explicit animation drives
the layer's presented value from the scene's frame clock and leaves the model alone; on
completion it is removed (the presented value snaps back to the model, as Core Animation's
does) unless `fillMode` is `forwards` and `isRemovedOnCompletion` is false, when it stays until
removed. `CATransaction` (`begin`, `commit`, `setAnimationDuration`, `setDisableActions`,
`setAnimationTimingFunction`, `setCompletionBlock`, `flush`): a standalone layer's property
changes animate implicitly over the transaction's duration (0.25 s by default); a view's
backing layer animates only inside `UIView.animate`, as in UIKit. Changes made outside any
transaction join an implicit one the scene commits at its next frame. Open: `CAAnimationGroup`
playback, keyframe interpolation through every value, additive animations, `CADisplayLink`.
