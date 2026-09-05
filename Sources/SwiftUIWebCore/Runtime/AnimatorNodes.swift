// Runtime for PhaseAnimator and KeyframeAnimator: both drive their content from the runtime's
// animation clock through frame subscriptions.

/// `PhaseAnimator`: rebuilds the content for each phase inside a transaction carrying the
/// phase's animation, waits for it to finish and moves on.
@MainActor
package final class PhaseAnimatorNode<Phase: Equatable, Content: View>: TypedNode<PhaseAnimator<Phase, Content>>, _FrameSubscriber {
    package private(set) var child: TypedNode<Content>!
    package private(set) var index = 0
    private var stepEnd: Double?
    private var lastTrigger: _AnyEquatable?

    init(_ context: _NodeContext<PhaseAnimator<Phase, Content>>) {
        super.init(view: context.view, parent: context.parent, runtime: context.runtime, environment: context.environment)
        lastTrigger = context.view.trigger
        child = Content._makeNode(_NodeContext(view: makeContent(), parent: self, environment: context.environment))
        // A free-running animator shows its first phase and steps on the first frame.
        if context.view.trigger == nil, context.view.phases.count > 1 {
            stepEnd = context.runtime.animationClock
            context.runtime.subscribeFrames(self)
        }
    }

    package var phase: Phase { view.phases[min(index, view.phases.count - 1)] }

    private func makeContent() -> Content { view.content(phase) }

    override package func update(view: PhaseAnimator<Phase, Content>, environment: EnvironmentValues, force: Bool) {
        let triggerChanged = view.trigger != lastTrigger
        self.view = view
        self.environment = environment
        lastTrigger = view.trigger
        clearNeedsUpdate()
        if view.phases.isEmpty { index = 0 }
        child.update(view: makeContent(), environment: environment, force: force)
        if triggerChanged, view.phases.count > 1 { advance() }
    }

    override package func performUpdate() {
        clearNeedsUpdate()
        child.update(view: makeContent(), environment: environment, force: false)
    }

    /// Steps to the next phase under its animation.
    private func advance() {
        guard view.phases.count > 1 else { return }
        index = (index + 1) % view.phases.count
        let animation = view.animation(phase)
        var transaction = Transaction()
        transaction.animation = animation
        withTransaction(transaction) { invalidate() }
        stepEnd = runtime.animationClock + (animation?.totalDuration ?? 0)
        runtime.subscribeFrames(self)
    }

    package func frameDidAdvance() {
        guard let end = stepEnd, runtime.animationClock >= end else { return }
        stepEnd = nil
        // A triggered run stops when it is back at the first phase; a free-running one cycles.
        if view.trigger != nil, index == 0 {
            runtime.unsubscribeFrames(self)
            return
        }
        advance()
    }

    override package func unmount() {
        runtime.unsubscribeFrames(self)
        super.unmount()
    }

    override package var structuralChildren: [ViewNode] { [child] }
    override package var layoutChildren: [ViewNode] { child.layoutChildren }
    override package var nodeDescription: String { "PhaseAnimator" }
}

/// `KeyframeAnimator`: rebuilds the content every frame with the timeline's value.
@MainActor
package final class KeyframeAnimatorNode<Value, KeyframePath: Keyframes, Content: View>: TypedNode<KeyframeAnimator<Value, KeyframePath, Content>>, _FrameSubscriber
    where KeyframePath.Value == Value
{
    package private(set) var child: TypedNode<Content>!
    package private(set) var value: Value
    private var timeline: KeyframeTimeline<Value>?
    private var start: Double = 0
    private var lastTrigger: _AnyEquatable?

    init(_ context: _NodeContext<KeyframeAnimator<Value, KeyframePath, Content>>) {
        value = context.view.initialValue
        super.init(view: context.view, parent: context.parent, runtime: context.runtime, environment: context.environment)
        lastTrigger = context.view.trigger
        child = Content._makeNode(_NodeContext(view: context.view.content(value), parent: self, environment: context.environment))
        if context.view.trigger == nil { play() }
    }

    override package func update(view: KeyframeAnimator<Value, KeyframePath, Content>, environment: EnvironmentValues, force: Bool) {
        let triggerChanged = view.trigger != lastTrigger
        self.view = view
        self.environment = environment
        lastTrigger = view.trigger
        clearNeedsUpdate()
        child.update(view: view.content(value), environment: environment, force: force)
        if triggerChanged { play() }
    }

    override package func performUpdate() {
        clearNeedsUpdate()
        child.update(view: view.content(value), environment: environment, force: false)
    }

    /// Starts the keyframes from the initial value on the animation clock.
    private func play() {
        timeline = KeyframeTimeline(initialValue: view.initialValue, tracks: view.keyframes(view.initialValue)._tracks)
        start = runtime.animationClock
        value = view.initialValue
        invalidate()
        runtime.subscribeFrames(self)
    }

    package func frameDidAdvance() {
        guard let timeline else { return }
        let duration = timeline.duration
        var time = runtime.animationClock - start
        var finished = false
        if duration <= 0 {
            finished = true
        } else if time >= duration {
            if view.repeating, view.trigger == nil {
                time = time.truncatingRemainder(dividingBy: duration)
            } else {
                time = duration
                finished = true
            }
        }
        value = timeline.value(time: time)
        invalidate()
        if finished {
            self.timeline = nil
            runtime.unsubscribeFrames(self)
        }
    }

    override package func unmount() {
        runtime.unsubscribeFrames(self)
        super.unmount()
    }

    override package var structuralChildren: [ViewNode] { [child] }
    override package var layoutChildren: [ViewNode] { child.layoutChildren }
    override package var nodeDescription: String { "KeyframeAnimator" }
}
