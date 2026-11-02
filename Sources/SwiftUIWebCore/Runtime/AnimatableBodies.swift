// Animatable views and modifiers with a body (a `View` that conforms to `Animatable`, an
// `AnimatableModifier`): when one's animatable data changes under an animation, its body is
// evaluated once per frame with the data interpolated from the value shown to the new one, as
// SwiftUI does (Docs/elements/Animation.md). Shapes and geometry effects have nodes of their own.
// Everything here takes the value as `Any`, so the generic nodes that call it (one
// specialisation per view and modifier type in an app) carry a type check and two calls. The
// casts run on the main actor, where a view's conformance to `Animatable` may be isolated.

/// Whether values of `type` have animatable data a body can be evaluated at.
@MainActor @inline(never)
package func _isAnimatableBody(_ type: Any.Type) -> Bool { type is any Animatable.Type }

/// A running interpolation of a value's animatable data.
private struct _AnimatableBodyTween {
    /// The progress, 0 to 1 (beyond for a spring's overshoot).
    let tween: Tween
    /// The value with its animatable data at a progress.
    let apply: (Any, Double) -> Any
}

/// A tween from `old`'s animatable data to `new`'s, or nil when the two hold the same data.
@MainActor
private func _makeAnimatableTween(from old: Any, to new: Any, animation: Animation, start: Double) -> _AnimatableBodyTween? {
    guard let animatable = old as? any Animatable else { return nil }
    return _animatableTween(animatable, to: new, animation: animation, start: start)
}

@MainActor
private func _animatableTween<A: Animatable>(_ old: A, to new: Any, animation: Animation, start: Double) -> _AnimatableBodyTween? {
    guard let new = new as? A else { return nil }
    let from = old.animatableData, to = new.animatableData
    guard (from - to).magnitudeSquared > 0 else { return nil }
    return _AnimatableBodyTween(tween: Tween(from: [0], to: [1], animation: animation, start: start)) { value, progress in
        guard var current = value as? A else { return value }
        current.animatableData = from.interpolated(towards: to, amount: progress)
        return current
    }
}

/// The per-frame side of an animatable body: the node keeps the tween and is re-evaluated each
/// frame until it finishes.
@MainActor
package final class _AnimatableBodyDriver: _FrameSubscriber {
    private unowned let node: ViewNode
    private var tween: _AnimatableBodyTween?

    private init(node: ViewNode) { self.node = node }

    /// `value` (the newest, with its dynamic properties installed) with the data shown now.
    package func presented<Value>(_ value: Value) -> Value {
        guard let tween else { return value }
        return tween.apply(value, tween.tween.value(at: node.runtime.animationClock)[0]) as? Value ?? value
    }

    /// Records a change of a value from `old` to `new` at `node`: a change of its animatable
    /// data under an animation tweens from what is on screen, one without jumps.
    package static func change(_ driver: inout _AnimatableBodyDriver?, node: ViewNode, old: Any, new: Any) {
        // An update that leaves the data as it was (a frame's re-evaluation, a parent's change)
        // keeps a running tween as it is.
        guard _makeAnimatableTween(from: old, to: new, animation: .linear(duration: 0), start: 0) != nil else { return }
        let shown = driver.map { $0.presentedAny(old) } ?? old
        if let animation = node.runtime.effectiveUpdateAnimation(for: node),
           let tween = _makeAnimatableTween(from: shown, to: new, animation: animation, start: node.runtime.animationClock) {
            let current = driver ?? _AnimatableBodyDriver(node: node)
            current.tween = tween
            node.runtime.subscribeFrames(current)
            driver = current
        } else {
            driver?.stop()
        }
    }

    private func presentedAny(_ value: Any) -> Any {
        guard let tween else { return value }
        return tween.apply(value, tween.tween.value(at: node.runtime.animationClock)[0])
    }

    package func stop() {
        tween = nil
        node.runtime.unsubscribeFrames(self)
    }

    package func frameDidAdvance() {
        guard let tween else { return }
        if tween.tween.isFinished(at: node.runtime.animationClock) { stop() }
        node.invalidate()
    }
}
