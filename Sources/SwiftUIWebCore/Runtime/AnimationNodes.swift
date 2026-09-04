// Animation runtime: the transaction's animation is recorded when state changes and consumed by
// the next update and layout; nodes whose frame, opacity or colour changes under it keep a
// tween and paint the interpolated value; inserted and removed subtrees get transitions, removed
// ones lingering as exiting ghosts until theirs ends (Docs/elements/Animation.md).

/// An interpolation of a vector of values over an animation.
package struct Tween {
    package let from: [Double]
    package let to: [Double]
    package let animation: Animation
    package let start: Double

    package func value(at time: Double) -> [Double] {
        let t = animation.value(at: time - start)
        return zip(from, to).map { $0 + ($1 - $0) * t }
    }

    package func isFinished(at time: Double) -> Bool { animation.isFinished(at: time - start) }
}

/// A transition in flight on a node: the effects at the removed end, whether the node is
/// entering (effects fade out) or leaving (effects fade in), and its timing.
package struct TransitionState {
    package let effects: AnyTransition.Effects
    package let insertion: Bool
    package let animation: Animation
    package let start: Double
    package var onFinish: (@MainActor () -> Void)?

    /// How much of the removed-end effects applies now (1 = fully removed look).
    package func factor(at time: Double) -> Double {
        let progress = min(max(animation.value(at: time - start), 0), 1)
        return insertion ? 1 - progress : progress
    }

    package func isFinished(at time: Double) -> Bool { animation.isFinished(at: time - start) }
}

/// What a node currently shows while animating.
@MainActor
package final class NodePresentation {
    package var frame: Tween?
    package var opacity: Tween?
    package var color: Tween?
    package var effect: Tween?
    package var transition: TransitionState?

    package var isEmpty: Bool { frame == nil && opacity == nil && color == nil && effect == nil && transition == nil }
}

/// A weak reference for the runtime's list of animating nodes.
package struct WeakNode {
    package weak var node: ViewNode?
}

extension Runtime {
    /// Whether any animation is in flight.
    public var isAnimating: Bool { !animatingNodes.isEmpty }

    /// Advances the animation clock by `elapsed` seconds, drops finished animations and asks
    /// for a repaint while any remains. Returns whether animations are still in flight.
    @discardableResult
    public func advanceAnimations(elapsed: Double) -> Bool {
        animationClock += max(0, elapsed)
        let now = animationClock
        var remaining: [WeakNode] = []
        var finished: [@MainActor () -> Void] = []
        for entry in animatingNodes {
            guard let node = entry.node, let presentation = node.presentation else { continue }
            if let tween = presentation.frame, tween.isFinished(at: now) { presentation.frame = nil }
            if let tween = presentation.opacity, tween.isFinished(at: now) { presentation.opacity = nil }
            if let tween = presentation.color, tween.isFinished(at: now) { presentation.color = nil }
            if let tween = presentation.effect, tween.isFinished(at: now) { presentation.effect = nil }
            if let transition = presentation.transition, transition.isFinished(at: now) {
                presentation.transition = nil
                if let onFinish = transition.onFinish { finished.append(onFinish) }
            }
            if presentation.isEmpty { node.presentation = nil } else { remaining.append(entry) }
        }
        let hadAnimations = !animatingNodes.isEmpty
        animatingNodes = remaining
        for onFinish in finished { onFinish() }
        // Repaint while animating and once more when the last animation ends, so the final frame
        // shows the settled state rather than the last interpolated one.
        if hadAnimations { setNeedsDisplay() }
        let subscribers = advanceFrameSubscribers()
        return !remaining.isEmpty || subscribers
    }

    package func register(animating node: ViewNode) {
        if !animatingNodes.contains(where: { $0.node === node }) { animatingNodes.append(WeakNode(node: node)) }
    }

    /// The animation for changes applied in the current update pass at `node`: the nearest
    /// enclosing `animation(_:value:)` or `transaction` scope's (which may switch animation off),
    /// else the transaction's.
    package func effectiveUpdateAnimation(for node: ViewNode) -> Animation? {
        if let scoped = scopedAnimation(for: node) { return scoped }
        return updateAnimation
    }

    /// The animation for frames placed in the current layout pass at `node`.
    package func effectiveLayoutAnimation(for node: ViewNode) -> Animation? {
        if let scoped = scopedAnimation(for: node) { return scoped }
        return layoutAnimation
    }

    /// The nearest active scope's animation: `.none` without a scope, `.some(nil)` for a scope
    /// that disables animation.
    private func scopedAnimation(for node: ViewNode) -> Animation?? {
        guard activeAnimationScopes > 0 else { return nil }
        let target = isLayingOut ? layoutGeneration : layoutGeneration + 1
        var current: ViewNode? = node
        while let candidate = current {
            if let scope = candidate as? any _AnimationScoping, scope.scopeGeneration == target { return .some(scope.scopeAnimation) }
            current = candidate.parent
        }
        return nil
    }
}

/// A node that supplies an animation to the subtree changes that follow one of its updates.
@MainActor
package protocol _AnimationScoping: AnyObject {
    var scopeAnimation: Animation? { get }
    var scopeGeneration: UInt64 { get }
}

@MainActor
package final class AnimationScopeNode<Content: View, Value: Equatable>: TypedNode<ModifiedContent<Content, _AnimationModifier<Value>>>, _AnimationScoping {
    package private(set) var child: TypedNode<Content>!
    package private(set) var scopeAnimation: Animation?
    package private(set) var scopeGeneration: UInt64 = 0

    init(_ context: _NodeContext<ModifiedContent<Content, _AnimationModifier<Value>>>) {
        super.init(view: context.view, parent: context.parent, runtime: context.runtime, environment: context.environment)
        runtime.activeAnimationScopes += 1
        child = Content._makeNode(_NodeContext(view: context.view.content, parent: self, environment: context.environment))
    }

    override package func update(view: ModifiedContent<Content, _AnimationModifier<Value>>, environment: EnvironmentValues, force: Bool) {
        let changed = view.modifier.value == nil || self.view.modifier.value != view.modifier.value
        self.view = view
        self.environment = environment
        clearNeedsUpdate()
        if changed {
            scopeAnimation = view.modifier.animation
            scopeGeneration = runtime.layoutGeneration + 1
        }
        child.update(view: view.content, environment: environment, force: force)
    }

    override package func unmount() {
        runtime.activeAnimationScopes -= 1
        super.unmount()
    }

    override package var structuralChildren: [ViewNode] { [child] }
    override package var layoutChildren: [ViewNode] { child.layoutChildren }
    override package var nodeDescription: String { "Animation" }
}

@MainActor
package final class TransactionScopeNode<Content: View>: TypedNode<ModifiedContent<Content, _TransactionModifier>>, _AnimationScoping {
    package private(set) var child: TypedNode<Content>!
    package private(set) var scopeAnimation: Animation?
    package private(set) var scopeGeneration: UInt64 = 0

    init(_ context: _NodeContext<ModifiedContent<Content, _TransactionModifier>>) {
        super.init(view: context.view, parent: context.parent, runtime: context.runtime, environment: context.environment)
        runtime.activeAnimationScopes += 1
        child = Content._makeNode(_NodeContext(view: context.view.content, parent: self, environment: context.environment))
    }

    override package func update(view: ModifiedContent<Content, _TransactionModifier>, environment: EnvironmentValues, force: Bool) {
        self.view = view
        self.environment = environment
        clearNeedsUpdate()
        var transaction = Transaction()
        transaction.animation = runtime.updateAnimation
        view.modifier.transform(&transaction)
        scopeAnimation = transaction.disablesAnimations ? nil : transaction.animation
        scopeGeneration = runtime.layoutGeneration + 1
        child.update(view: view.content, environment: environment, force: force)
    }

    override package func unmount() {
        runtime.activeAnimationScopes -= 1
        super.unmount()
    }

    override package var structuralChildren: [ViewNode] { [child] }
    override package var layoutChildren: [ViewNode] { child.layoutChildren }
    override package var nodeDescription: String { "Transaction" }
}

/// Records a transition for its content; identity for layout.
@MainActor
package protocol _TransitionProviding: AnyObject {
    var transition: AnyTransition { get }
}

@MainActor
package final class TransitionNode<Content: View>: UnaryLayoutModifierNode<Content, _TransitionModifier>, _TransitionProviding {
    package var transition: AnyTransition { modifier.transition }
}

extension ViewNode {
    /// The transition declared on this layout node or on a modifier chain inside it (the
    /// default, as in SwiftUI, is a fade).
    package func declaredTransition() -> AnyTransition {
        var current: ViewNode? = self
        while let node = current {
            if let provider = node as? any _TransitionProviding { return provider.transition }
            guard let modifier = node as? any _UnaryLayoutModifier else { break }
            current = modifier.modifiedContent.layoutChildren.first
        }
        return .opacity
    }

    /// Starts an insertion or removal transition on this node.
    package func beginTransition(insertion: Bool, animation: Animation, onFinish: (@MainActor () -> Void)? = nil) {
        let transition = declaredTransition()
        let effects = transition.effects(insertion: insertion)
        guard !effects.isIdentity || onFinish != nil else { return }
        let presentation = self.presentation ?? NodePresentation()
        presentation.transition = TransitionState(effects: effects, insertion: insertion, animation: transition.animation ?? animation,
                                                  start: runtime.animationClock, onFinish: onFinish)
        self.presentation = presentation
        runtime.register(animating: self)
    }

    /// Replaces `child` (a structural child of this node) with a ghost that keeps painting
    /// through its removal transition when an animation is active, else unmounts it.
    package func retire(_ child: ViewNode) {
        guard let animation = runtime.effectiveUpdateAnimation(for: self) else { child.unmount(); return }
        let layoutNodes = child.layoutChildren
        guard !layoutNodes.isEmpty else { child.unmount(); return }
        exitingChildren.append(child)
        var pending = layoutNodes.count
        for node in layoutNodes {
            node.beginTransition(insertion: false, animation: animation) { [weak self, weak child] in
                pending -= 1
                guard pending == 0, let self, let child, let index = self.exitingChildren.firstIndex(where: { $0 === child }) else { return }
                self.exitingChildren.remove(at: index)
                child.unmount()
            }
        }
    }

    /// Starts insertion transitions on a freshly created structural child when an animation is active.
    package func noteInserted(_ child: ViewNode) {
        guard let animation = runtime.effectiveUpdateAnimation(for: self) else { return }
        for node in child.layoutChildren { node.beginTransition(insertion: true, animation: animation) }
    }

    /// Ghosts left by structural descendants that are not layout nodes, painted by this node.
    package func collectExiting() -> [ViewNode] {
        var result: [ViewNode] = []
        func walk(_ node: ViewNode) {
            for child in node.structuralChildren where !child.isLayoutNode {
                result += child.exitingChildren.flatMap { $0.layoutChildren }
                walk(child)
            }
        }
        result += exitingChildren.flatMap { $0.layoutChildren }
        walk(self)
        return result
    }

    /// Starts a frame tween from `from` to the current frame.
    package func beginFrameTween(from: CGRect, animation: Animation) {
        let presentation = self.presentation ?? NodePresentation()
        presentation.frame = Tween(from: [from.minX, from.minY, from.width, from.height], to: [frame.minX, frame.minY, frame.width, frame.height],
                                   animation: animation, start: runtime.animationClock)
        self.presentation = presentation
        runtime.register(animating: self)
    }

    /// The frame to paint at: the tweened frame, offset by a transition's movement.
    package var presentedFrame: CGRect {
        guard let presentation else { return frame }
        var rect = frame
        if let tween = presentation.frame {
            let v = tween.value(at: runtime.animationClock)
            rect = CGRect(x: v[0], y: v[1], width: v[2], height: v[3])
        }
        if let transition = presentation.transition {
            let factor = transition.factor(at: runtime.animationClock)
            rect.origin.x += (transition.effects.fraction.width * rect.width + transition.effects.points.width) * factor
            rect.origin.y += (transition.effects.fraction.height * rect.height + transition.effects.points.height) * factor
        }
        return rect
    }

    /// The group opacity a transition applies while painting this node.
    package var presentedTransitionOpacity: Double {
        guard let transition = presentation?.transition, transition.effects.fades else { return 1 }
        return 1 - transition.factor(at: runtime.animationClock)
    }

    /// The scale a transition applies while painting this node (1 when none).
    package var presentedTransitionScale: CGFloat {
        guard let transition = presentation?.transition, transition.effects.scale != 1 else { return 1 }
        return 1 + (transition.effects.scale - 1) * CGFloat(transition.factor(at: runtime.animationClock))
    }
}
