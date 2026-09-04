#if os(WASI)
import FoundationEssentials   // never full Foundation on wasm: it links ICU (decision 0006)
#else
import Foundation
#endif

/// A view that updates according to a schedule that you provide (`Docs/elements/TimelineView.md`).
///
/// Periodic, explicit and every-minute schedules wake through a main-actor `Task` sleeping
/// until the next date; the `.animation` schedule re-renders on every host frame (Foundation's
/// `Timer`/`RunLoop` do not fire on wasm, so nothing here depends on them).
public struct TimelineView<Schedule: TimelineSchedule, Content: View>: View {
    package let schedule: Schedule
    package let content: _TimelineContentBox<Content>

    /// Creates a new timeline view that uses the given schedule.
    public init(_ schedule: Schedule, @ViewBuilder content: @escaping (Context) -> Content) {
        self.schedule = schedule
        self.content = _TimelineContentBox(content)
    }

    /// Information passed to a timeline view's content callback.
    public typealias Context = TimelineViewDefaultContext

    public typealias Body = Never

    public static func _makeNode(_ context: _NodeContext<TimelineView<Schedule, Content>>) -> TypedNode<TimelineView<Schedule, Content>> {
        TimelineNode(context)
    }
}

/// Information passed to a timeline view's content callback.
public struct TimelineViewDefaultContext {
    /// The date from the schedule that triggered the callback.
    public let date: Date
    /// The rate at which the timeline updates the view.
    public let cadence: Cadence

    /// A rate at which timeline views can update the content they display.
    public enum Cadence: Comparable, Sendable { case live, seconds, minutes }

    package init(date: Date, cadence: Cadence) {
        self.date = date
        self.cadence = cadence
    }
}

/// Holds a timeline view's content builder (a class so the runtime's field reflection ignores it).
package final class _TimelineContentBox<Content: View> {
    package let make: (TimelineViewDefaultContext) -> Content
    package init(_ make: @escaping (TimelineViewDefaultContext) -> Content) { self.make = make }
}

// MARK: - Schedules

/// A type that provides a sequence of dates for use as a schedule.
public protocol TimelineSchedule {
    associatedtype Entries: Sequence where Entries.Element == Date
    /// Provides a sequence of dates starting around a given date.
    func entries(from startDate: Date, mode: TimelineScheduleMode) -> Entries
}

/// Options for how the timeline view updates its content.
public enum TimelineScheduleMode: Sendable {
    case normal, lowFrequency
}

/// A schedule for updating a timeline view at regular intervals.
public struct PeriodicTimelineSchedule: TimelineSchedule, Sendable {
    package let start: Date
    package let interval: TimeInterval

    public init(from startDate: Date, by interval: TimeInterval) {
        start = startDate
        self.interval = max(interval, 0.001)
    }

    public struct Entries: Sequence, IteratorProtocol, Sendable {
        var next_: Date
        let interval: TimeInterval
        public mutating func next() -> Date? {
            let current = next_
            next_ = next_.addingTimeInterval(interval)
            return current
        }
    }

    public func entries(from startDate: Date, mode: TimelineScheduleMode) -> Entries {
        // The first entry at or after `startDate` on the period's grid.
        let elapsed = startDate.timeIntervalSince(start)
        let steps = elapsed <= 0 ? 0 : (elapsed / interval).rounded(.up)
        return Entries(next_: start.addingTimeInterval(steps * interval), interval: interval)
    }
}

/// A schedule for updating a timeline view at the start of every minute.
public struct EveryMinuteTimelineSchedule: TimelineSchedule, Sendable {
    public init() {}
    public func entries(from startDate: Date, mode: TimelineScheduleMode) -> PeriodicTimelineSchedule.Entries {
        let seconds = startDate.timeIntervalSinceReferenceDate
        let minuteStart = Date(timeIntervalSinceReferenceDate: (seconds / 60).rounded(.down) * 60)
        return PeriodicTimelineSchedule.Entries(next_: minuteStart, interval: 60)
    }
}

/// A schedule for updating a timeline view at explicit points in time.
public struct ExplicitTimelineSchedule<Entries: Sequence>: TimelineSchedule where Entries.Element == Date {
    package let dates: Entries
    public init(_ dates: Entries) { self.dates = dates }
    public func entries(from startDate: Date, mode: TimelineScheduleMode) -> Entries { dates }
}

/// A pausable schedule of dates updating at a frequency no more quickly than the provided interval.
public struct AnimationTimelineSchedule: TimelineSchedule, Sendable {
    package let minimumInterval: Double?
    package let paused: Bool

    public init(minimumInterval: Double? = nil, paused: Bool = false) {
        self.minimumInterval = minimumInterval
        self.paused = paused
    }

    public func entries(from startDate: Date, mode: TimelineScheduleMode) -> PeriodicTimelineSchedule.Entries {
        PeriodicTimelineSchedule.Entries(next_: startDate, interval: minimumInterval ?? 1.0 / 60)
    }
}

/// A type-erased schedule (the runtime's view of any schedule).
public struct AnyTimelineSchedule: TimelineSchedule {
    package let base: any TimelineSchedule
    package init<S: TimelineSchedule>(_ schedule: S) { base = schedule }
    public func entries(from startDate: Date, mode: TimelineScheduleMode) -> [Date] {
        var result: [Date] = []
        var iterator = (base.entries(from: startDate, mode: mode) as any Sequence).makeIterator()
        while result.count < 2, let next = iterator.next() as? Date { result.append(next) }
        return result
    }
}

extension TimelineSchedule where Self == PeriodicTimelineSchedule {
    public static func periodic(from startDate: Date, by interval: TimeInterval) -> PeriodicTimelineSchedule {
        PeriodicTimelineSchedule(from: startDate, by: interval)
    }
}
extension TimelineSchedule where Self == EveryMinuteTimelineSchedule {
    public static var everyMinute: EveryMinuteTimelineSchedule { EveryMinuteTimelineSchedule() }
}
extension TimelineSchedule where Self == AnimationTimelineSchedule {
    public static var animation: AnimationTimelineSchedule { AnimationTimelineSchedule() }
    public static func animation(minimumInterval: Double? = nil, paused: Bool = false) -> AnimationTimelineSchedule {
        AnimationTimelineSchedule(minimumInterval: minimumInterval, paused: paused)
    }
}
extension TimelineSchedule {
    public static func explicit<S: Sequence>(_ dates: S) -> ExplicitTimelineSchedule<S> where Self == ExplicitTimelineSchedule<S>, S.Element == Date {
        ExplicitTimelineSchedule(dates)
    }
}
