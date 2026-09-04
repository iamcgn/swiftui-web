#if os(WASI)
import FoundationEssentials   // never full Foundation on wasm: it links ICU (decision 0006)
#else
import Foundation
#endif

// TimelineView runtime: renders its content for the current date and wakes for the next
// scheduled date with a main-actor Task (the animation schedule re-renders every host frame).

@MainActor
package protocol _FrameSubscriber: AnyObject {
    /// Called once per host frame while animations are advanced.
    func frameDidAdvance()
}

@MainActor
package final class TimelineNode<Schedule: TimelineSchedule, Content: View>: TypedNode<TimelineView<Schedule, Content>>, _FrameSubscriber {
    package private(set) var child: TypedNode<Content>!
    package private(set) var date = Date()
    private var wake: Task<Void, Never>?
    private var isAnimation: Bool { view.schedule is AnimationTimelineSchedule }
    private var isPaused: Bool { (view.schedule as? AnimationTimelineSchedule)?.paused ?? false }
    private var lastFrameDate: Date?

    init(_ context: _NodeContext<TimelineView<Schedule, Content>>) {
        super.init(view: context.view, parent: context.parent, runtime: context.runtime, environment: context.environment)
        date = Date()
        child = Content._makeNode(_NodeContext(view: makeContent(), parent: self, environment: context.environment))
        scheduleNext()
    }

    private func makeContent() -> Content {
        view.content.make(TimelineViewDefaultContext(date: date, cadence: isAnimation ? .live : .seconds))
    }

    override package func update(view: TimelineView<Schedule, Content>, environment: EnvironmentValues, force: Bool) {
        self.view = view
        self.environment = environment
        clearNeedsUpdate()
        child.update(view: makeContent(), environment: environment, force: force)
        scheduleNext()
    }

    /// The re-render for a new date, from a wake or a frame.
    override package func performUpdate() {
        clearNeedsUpdate()
        child.update(view: makeContent(), environment: environment, force: false)
        scheduleNext()
    }

    private func scheduleNext() {
        if isAnimation {
            wake?.cancel(); wake = nil
            if isPaused { runtime.unsubscribeFrames(self) } else { runtime.subscribeFrames(self) }
            return
        }
        guard wake == nil else { return }
        let next = AnyTimelineSchedule(view.schedule).entries(from: date.addingTimeInterval(0.0005), mode: .normal).first
        guard let next else { return }
        let delay = max(0, next.timeIntervalSince(Date()))
        wake = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            self.wake = nil
            self.date = next
            self.invalidate()
        }
    }

    package func frameDidAdvance() {
        let minimum = (view.schedule as? AnimationTimelineSchedule)?.minimumInterval ?? 0
        let now = Date()
        if let last = lastFrameDate, now.timeIntervalSince(last) < minimum { return }
        lastFrameDate = now
        date = now
        invalidate()
    }

    override package func unmount() {
        wake?.cancel()
        wake = nil
        runtime.unsubscribeFrames(self)
        super.unmount()
    }

    override package var structuralChildren: [ViewNode] { [child] }
    override package var layoutChildren: [ViewNode] { child.layoutChildren }
    override package var nodeDescription: String { "TimelineView" }
}

extension Runtime {
    package func subscribeFrames(_ subscriber: any _FrameSubscriber) {
        if !frameSubscribers.contains(where: { $0.subscriber === subscriber }) {
            frameSubscribers.append(WeakFrameSubscriber(subscriber: subscriber))
            setNeedsDisplay()
        }
    }

    package func unsubscribeFrames(_ subscriber: any _FrameSubscriber) {
        frameSubscribers.removeAll { $0.subscriber === subscriber || $0.subscriber == nil }
    }

    /// Advances frame subscribers (timeline views on the animation schedule); returns whether any remain.
    package func advanceFrameSubscribers() -> Bool {
        frameSubscribers.removeAll { $0.subscriber == nil }
        for entry in frameSubscribers { entry.subscriber?.frameDidAdvance() }
        return !frameSubscribers.isEmpty
    }
}

package struct WeakFrameSubscriber {
    package weak var subscriber: (any _FrameSubscriber)?
}
