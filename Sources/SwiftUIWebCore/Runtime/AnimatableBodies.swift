// Animatable views and modifiers with a body (a `View` that conforms to `Animatable`, an
// `AnimatableModifier`): when one's animatable data changes under an animation, its body is
// evaluated once per frame with the data interpolated from the value shown to the new one, as
// SwiftUI does (Docs/elements/Animation.md). Shapes and geometry effects have nodes of their own.

/// A running interpolation of a value's animatable data.
@MainActor
package struct _AnimatableBodyTween<Value> {
    /// The progress, 0 to 1 (beyond for a spring's overshoot).
    let tween: Tween
    /// The value with its animatable data at a progress.
    let apply: (Value, Double) -> Value

    /// `value` (the newest, with its dynamic properties installed) with the data shown at `time`.
    func presented(_ value: Value, at time: Double) -> Value { apply(value, tween.value(at: time)[0]) }

    func isFinished(at time: Double) -> Bool { tween.isFinished(at: time) }

    /// A tween from `old`'s animatable data to `new`'s, or nil when `Value` is not `Animatable`
    /// or the two hold the same data.
    static func make(from old: Value, to new: Value, animation: Animation, start: Double) -> Self? {
        guard Value.self is any Animatable.Type, let animatable = old as? any Animatable else { return nil }
        return _animatableTween(animatable, to: new, animation: animation, start: start)
    }

    /// Whether `old` and `new` hold different animatable data.
    static func dataDiffers(_ old: Value, _ new: Value) -> Bool {
        make(from: old, to: new, animation: .linear(duration: 0), start: 0) != nil
    }
}

@MainActor
private func _animatableTween<A: Animatable, Value>(_ old: A, to new: Value, animation: Animation, start: Double) -> _AnimatableBodyTween<Value>? {
    guard let new = new as? A else { return nil }
    let from = old.animatableData, to = new.animatableData
    guard (from - to).magnitudeSquared > 0 else { return nil }
    return _AnimatableBodyTween(tween: Tween(from: [0], to: [1], animation: animation, start: start)) { value, progress in
        guard var current = value as? A else { return value }
        current.animatableData = from.interpolated(towards: to, amount: progress)
        return current as? Value ?? value
    }
}

/// The per-frame side of an animatable body: a node keeps the tween and is re-evaluated each
/// frame until it finishes.
@MainActor
package final class _AnimatableBodyDriver<Value>: _FrameSubscriber {
    private unowned let node: ViewNode
    private(set) var tween: _AnimatableBodyTween<Value>?

    init(node: ViewNode) { self.node = node }

    /// The value to evaluate the body with now.
    func presented(_ value: Value) -> Value {
        tween?.presented(value, at: node.runtime.animationClock) ?? value
    }

    /// Starts, retargets or ends the tween for a change of the data, from the value shown
    /// (`shown`, already interpolated) to `new`: a change under an animation tweens from what
    /// is on screen, one without jumps.
    func update(shown: Value, new: Value) {
        if let animation = node.runtime.effectiveUpdateAnimation(for: node),
           let tween = _AnimatableBodyTween.make(from: shown, to: new, animation: animation, start: node.runtime.animationClock) {
            self.tween = tween
            node.runtime.subscribeFrames(self)
        } else {
            stop()
        }
    }

    func stop() {
        tween = nil
        node.runtime.unsubscribeFrames(self)
    }

    package func frameDidAdvance() {
        guard let tween else { return }
        if tween.isFinished(at: node.runtime.animationClock) { stop() }
        node.invalidate()
    }
}
