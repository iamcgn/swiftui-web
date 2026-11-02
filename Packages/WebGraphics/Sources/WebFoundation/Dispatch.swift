// `DispatchQueue` on wasm (decision 0021): there is no Dispatch module in the wasm SDK, and
// Apple's Foundation re-exports it, so apps write `DispatchQueue.main.async` under
// `import Foundation` or `import SwiftUI`. The page has one thread: every queue runs its work
// on the main actor through the host's executor (JavaScriptEventLoop), `sync` runs it in place,
// and a deadline waits with `Task.sleep`. A wait (a semaphore's, a group's, a work item's)
// cannot block the one thread, so it returns at once; a timer source fires from the executor.
#if os(WASI)
public struct DispatchQoS: Sendable, Equatable {
    public enum QoSClass: Sendable { case background, utility, `default`, userInitiated, userInteractive, unspecified }
    public let qosClass: QoSClass
    public init(qosClass: QoSClass = .default, relativePriority: Int = 0) { self.qosClass = qosClass }
    public static let background = DispatchQoS(qosClass: .background)
    public static let utility = DispatchQoS(qosClass: .utility)
    public static let `default` = DispatchQoS(qosClass: .default)
    public static let userInitiated = DispatchQoS(qosClass: .userInitiated)
    public static let userInteractive = DispatchQoS(qosClass: .userInteractive)
    public static let unspecified = DispatchQoS(qosClass: .unspecified)
}

public struct DispatchTimeInterval: Sendable, Equatable {
    public let _seconds: Double
    public static func seconds(_ s: Int) -> DispatchTimeInterval { DispatchTimeInterval(_seconds: Double(s)) }
    public static func milliseconds(_ ms: Int) -> DispatchTimeInterval { DispatchTimeInterval(_seconds: Double(ms) / 1_000) }
    public static func microseconds(_ us: Int) -> DispatchTimeInterval { DispatchTimeInterval(_seconds: Double(us) / 1_000_000) }
    public static func nanoseconds(_ ns: Int) -> DispatchTimeInterval { DispatchTimeInterval(_seconds: Double(ns) / 1_000_000_000) }
    public static let never = DispatchTimeInterval(_seconds: .infinity)
}

/// A point on the monotonic clock, in seconds since the page loaded.
public struct DispatchTime: Sendable, Comparable {
    public let _seconds: Double
    public init(_seconds: Double) { self._seconds = _seconds }
    /// A time this many nanoseconds after the page loaded (Apple's: after boot).
    public init(uptimeNanoseconds: UInt64) { _seconds = Double(uptimeNanoseconds) / 1_000_000_000 }
    public var uptimeNanoseconds: UInt64 { _seconds.isFinite ? UInt64(max(0, _seconds) * 1_000_000_000) : .max }
    public static func now() -> DispatchTime { DispatchTime(_seconds: _monotonicNow()) }
    public static let distantFuture = DispatchTime(_seconds: .infinity)
    public static func < (a: DispatchTime, b: DispatchTime) -> Bool { a._seconds < b._seconds }
    public static func + (t: DispatchTime, seconds: Double) -> DispatchTime { DispatchTime(_seconds: t._seconds + seconds) }
    public static func - (t: DispatchTime, seconds: Double) -> DispatchTime { DispatchTime(_seconds: t._seconds - seconds) }
    public static func + (t: DispatchTime, interval: DispatchTimeInterval) -> DispatchTime { t + interval._seconds }
    public static func - (t: DispatchTime, interval: DispatchTimeInterval) -> DispatchTime { t - interval._seconds }
    public var _delay: Double { max(0, _seconds - _monotonicNow()) }
}

/// Whether a wait ended because its condition was met or because its time ran out.
public enum DispatchTimeoutResult: Sendable, Equatable {
    case success, timedOut
}

/// How work submitted to a queue runs. With one thread every item runs alone, so a barrier is
/// what every item already is.
public struct DispatchWorkItemFlags: OptionSet, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let barrier = DispatchWorkItemFlags(rawValue: 1 << 0)
    public static let detached = DispatchWorkItemFlags(rawValue: 1 << 1)
    public static let assignCurrentContext = DispatchWorkItemFlags(rawValue: 1 << 2)
    public static let noQoS = DispatchWorkItemFlags(rawValue: 1 << 3)
    public static let inheritQoS = DispatchWorkItemFlags(rawValue: 1 << 4)
    public static let enforceQoS = DispatchWorkItemFlags(rawValue: 1 << 5)
}

/// A point on the wall clock.
public struct DispatchWallTime: Sendable {
    public let _date: Date
    public static func now() -> DispatchWallTime { DispatchWallTime(_date: Date()) }
    public static func + (t: DispatchWallTime, seconds: Double) -> DispatchWallTime { DispatchWallTime(_date: t._date.addingTimeInterval(seconds)) }
    public static func + (t: DispatchWallTime, interval: DispatchTimeInterval) -> DispatchWallTime { t + interval._seconds }
    public var _delay: Double { max(0, _date.timeIntervalSinceNow) }
}

private let _pageStart = Date()
private func _monotonicNow() -> Double { Date().timeIntervalSince(_pageStart) }

public final class DispatchWorkItem: @unchecked Sendable {
    let block: @Sendable () -> Void
    public private(set) var isCancelled = false
    private var finished = false
    private var notifications: [(DispatchQueue, @Sendable () -> Void)] = []
    public init(qos: DispatchQoS = .unspecified, flags: DispatchWorkItemFlags = [], block: @escaping @Sendable () -> Void) { self.block = block }
    public func cancel() { isCancelled = true }
    public func perform() {
        if !isCancelled { block() }
        finished = true
        let pending = notifications
        notifications = []
        for (queue, work) in pending { queue.async(execute: work) }
    }
    /// Runs `work` on `queue` once this item has run.
    public func notify(qos: DispatchQoS = .unspecified, flags: DispatchWorkItemFlags = [], queue: DispatchQueue, execute work: @escaping @Sendable () -> Void) {
        if finished { queue.async(execute: work) } else { notifications.append((queue, work)) }
    }
    public func notify(queue: DispatchQueue, execute item: DispatchWorkItem) {
        notify(queue: queue) { item.perform() }
    }
    /// Returns at once: the page's one thread cannot block for an item that has not run yet.
    public func wait() {}
    public func wait(timeout: DispatchTime) -> DispatchTimeoutResult { finished ? .success : .timedOut }
    public func wait(wallTimeout: DispatchWallTime) -> DispatchTimeoutResult { finished ? .success : .timedOut }
}

/// A key for a value stored on a queue (`setSpecific(key:value:)`).
public final class DispatchSpecificKey<T>: @unchecked Sendable {
    public init() {}
}

/// What `dispatchPrecondition(condition:)` checks.
public enum DispatchPredicate: Sendable {
    case onQueue(DispatchQueue)
    case onQueueAsBarrier(DispatchQueue)
    case notOnQueue(DispatchQueue)
}

/// Checks that the current code runs (or does not run) on a queue. Every queue's work runs on
/// the page's one thread, so there is nothing a check could tell apart: it always passes.
public func dispatchPrecondition(condition: @autoclosure () -> DispatchPredicate) {}

public final class DispatchQueue: @unchecked Sendable {
    public struct Attributes: OptionSet, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let concurrent = Attributes(rawValue: 1)
        public static let initiallyInactive = Attributes(rawValue: 2)
    }

    public static let main = DispatchQueue(label: "com.apple.main-thread")
    private static let globalQueue = DispatchQueue(label: "com.apple.root.default-qos")
    public static func global(qos: DispatchQoS.QoSClass = .default) -> DispatchQueue { globalQueue }

    public let label: String
    public let qos: DispatchQoS
    private var specifics: [ObjectIdentifier: Any] = [:]
    /// The queue whose work is running, for `getSpecific(key:)`.
    nonisolated(unsafe) private static var current: DispatchQueue?

    public init(label: String, qos: DispatchQoS = .unspecified, attributes: Attributes = [], autoreleaseFrequency: AutoreleaseFrequency = .inherit, target: DispatchQueue? = nil) {
        self.label = label
        self.qos = qos
    }

    public enum AutoreleaseFrequency: Sendable { case inherit, workItem, never }

    /// Runs `work` with this queue as the current one.
    private func run<T>(_ work: () throws -> T) rethrows -> T {
        let previous = DispatchQueue.current
        DispatchQueue.current = self
        defer { DispatchQueue.current = previous }
        return try work()
    }

    /// Runs the work on the main actor after the current turn.
    public func async(group: DispatchGroup? = nil, qos: DispatchQoS = .unspecified, flags: DispatchWorkItemFlags = [], execute work: @escaping @Sendable () -> Void) {
        group?.enter()
        Task { @MainActor in
            self.run(work)
            group?.leave()
        }
    }
    public func async(execute item: DispatchWorkItem) {
        Task { @MainActor in self.run { item.perform() } }
    }
    public func async(group: DispatchGroup, execute item: DispatchWorkItem) {
        group.enter()
        Task { @MainActor in
            self.run { item.perform() }
            group.leave()
        }
    }
    /// Runs the work now: the page has one thread, so there is nothing to wait for.
    public func sync<T>(execute work: () throws -> T) rethrows -> T { try run(work) }
    public func sync<T>(flags: DispatchWorkItemFlags, execute work: () throws -> T) rethrows -> T { try run(work) }
    public func sync(execute item: DispatchWorkItem) { run { item.perform() } }

    /// Stores a value on the queue under `key` (nil removes it).
    public func setSpecific<T>(key: DispatchSpecificKey<T>, value: T?) {
        specifics[ObjectIdentifier(key)] = value
    }
    /// The value stored on this queue under `key`.
    public func getSpecific<T>(key: DispatchSpecificKey<T>) -> T? { specifics[ObjectIdentifier(key)] as? T }
    /// The value stored under `key` on the queue whose work is running.
    public class func getSpecific<T>(key: DispatchSpecificKey<T>) -> T? { current?.getSpecific(key: key) }

    /// Runs `work` for each index, one after the other (there is one thread to run them on).
    public class func concurrentPerform(iterations: Int, execute work: (Int) -> Void) {
        for index in 0..<iterations { work(index) }
    }

    // Activation and suspension change nothing here: work is handed to the page's executor as
    // it is submitted.
    public func activate() {}
    public func suspend() {}
    public func resume() {}
    public func asyncAfter(deadline: DispatchTime, qos: DispatchQoS = .unspecified, execute work: @escaping @Sendable () -> Void) {
        schedule(after: deadline._delay, work)
    }
    public func asyncAfter(deadline: DispatchTime, execute item: DispatchWorkItem) {
        schedule(after: deadline._delay) { item.perform() }
    }
    public func asyncAfter(wallDeadline: DispatchWallTime, qos: DispatchQoS = .unspecified, execute work: @escaping @Sendable () -> Void) {
        schedule(after: wallDeadline._delay, work)
    }
    private func schedule(after seconds: Double, _ work: @escaping @Sendable () -> Void) {
        Task { @MainActor in
            if seconds > 0 { try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)) }
            work()
        }
    }
}

public final class DispatchGroup: @unchecked Sendable {
    private var count = 0
    private var waiters: [@Sendable () -> Void] = []
    public init() {}
    public func enter() { count += 1 }
    public func leave() {
        count -= 1
        if count <= 0 { let w = waiters; waiters = []; for n in w { n() } }
    }
    public func notify(qos: DispatchQoS = .unspecified, flags: DispatchWorkItemFlags = [], queue: DispatchQueue, execute work: @escaping @Sendable () -> Void) {
        if count <= 0 { queue.async(execute: work) } else { waiters.append { queue.async(execute: work) } }
    }
    public func notify(queue: DispatchQueue, work: DispatchWorkItem) {
        notify(queue: queue) { work.perform() }
    }
    /// Returns at once: the page's one thread cannot block while the group's work waits for it.
    public func wait() {}
    /// `.success` when no work is outstanding; otherwise `.timedOut` at once, for the same reason.
    public func wait(timeout: DispatchTime) -> DispatchTimeoutResult { count <= 0 ? .success : .timedOut }
    public func wait(wallTimeout: DispatchWallTime) -> DispatchTimeoutResult { count <= 0 ? .success : .timedOut }
}

/// A counting semaphore. One thread cannot block: a wait takes a unit when there is one, and
/// otherwise returns at once (`.timedOut` from the timed forms).
public final class DispatchSemaphore: @unchecked Sendable {
    private var value: Int
    public init(value: Int) { self.value = value }
    /// Adds a unit; returns nonzero when a waiter would have been woken, as Apple's does.
    @discardableResult public func signal() -> Int {
        value += 1
        return value <= 0 ? 1 : 0
    }
    public func wait() { value -= 1 }
    public func wait(timeout: DispatchTime) -> DispatchTimeoutResult {
        guard value > 0 else { return .timedOut }
        value -= 1
        return .success
    }
    public func wait(wallTimeout: DispatchWallTime) -> DispatchTimeoutResult { wait(timeout: .now()) }
}

// MARK: - Timer sources

/// A dispatch source. Timers are the kind a page has; the rest are not made here.
public protocol DispatchSourceProtocol: AnyObject, Sendable {
    func setEventHandler(qos: DispatchQoS, flags: DispatchWorkItemFlags, handler: (@Sendable () -> Void)?)
    func setCancelHandler(qos: DispatchQoS, flags: DispatchWorkItemFlags, handler: (@Sendable () -> Void)?)
    func activate()
    func resume()
    func suspend()
    func cancel()
    var isCancelled: Bool { get }
}

extension DispatchSourceProtocol {
    public func setEventHandler(handler: (@Sendable () -> Void)?) { setEventHandler(qos: .unspecified, flags: [], handler: handler) }
    public func setCancelHandler(handler: (@Sendable () -> Void)?) { setCancelHandler(qos: .unspecified, flags: [], handler: handler) }
}

/// A source that fires its handler at a deadline and then, optionally, at an interval.
public protocol DispatchSourceTimer: DispatchSourceProtocol {
    func _schedule(deadline: DispatchTime, repeating interval: DispatchTimeInterval)
}

extension DispatchSourceTimer {
    public func schedule(deadline: DispatchTime, repeating interval: DispatchTimeInterval = .never, leeway: DispatchTimeInterval = .nanoseconds(0)) {
        _schedule(deadline: deadline, repeating: interval)
    }
    public func schedule(deadline: DispatchTime, repeating interval: Double, leeway: DispatchTimeInterval = .nanoseconds(0)) {
        schedule(deadline: deadline, repeating: interval.isFinite ? .nanoseconds(Int(interval * 1_000_000_000)) : .never, leeway: leeway)
    }
    public func schedule(wallDeadline: DispatchWallTime, repeating interval: DispatchTimeInterval = .never, leeway: DispatchTimeInterval = .nanoseconds(0)) {
        schedule(deadline: .now() + wallDeadline._delay, repeating: interval, leeway: leeway)
    }
}

public enum DispatchSource {
    public struct TimerFlags: OptionSet, Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let strict = TimerFlags(rawValue: 1)
    }
    /// A timer source whose handler runs on `queue` (the main queue when nil). It starts
    /// suspended, as Apple's does: `resume()` or `activate()` starts it.
    public static func makeTimerSource(flags: TimerFlags = [], queue: DispatchQueue? = nil) -> any DispatchSourceTimer {
        _DispatchTimer(queue: queue ?? .main)
    }
}

final class _DispatchTimer: DispatchSourceTimer, @unchecked Sendable {
    private let queue: DispatchQueue
    private var handler: (@Sendable () -> Void)?
    private var cancelHandler: (@Sendable () -> Void)?
    private var deadline = DispatchTime.distantFuture
    private var interval = DispatchTimeInterval.never
    private var suspended = true
    private var generation = 0
    private(set) var isCancelled = false

    init(queue: DispatchQueue) { self.queue = queue }

    func setEventHandler(qos: DispatchQoS, flags: DispatchWorkItemFlags, handler: (@Sendable () -> Void)?) { self.handler = handler }
    func setCancelHandler(qos: DispatchQoS, flags: DispatchWorkItemFlags, handler: (@Sendable () -> Void)?) { cancelHandler = handler }
    func _schedule(deadline: DispatchTime, repeating interval: DispatchTimeInterval) {
        self.deadline = deadline
        self.interval = interval
        restart()
    }
    func activate() { resume() }
    func resume() {
        guard suspended, !isCancelled else { return }
        suspended = false
        restart()
    }
    func suspend() {
        suspended = true
        generation += 1
    }
    func cancel() {
        guard !isCancelled else { return }
        isCancelled = true
        generation += 1
        if let cancelHandler { queue.async(execute: cancelHandler) }
    }

    /// Starts a loop for the current schedule; a later schedule, suspend or cancel ends it.
    private func restart() {
        generation += 1
        guard !suspended, !isCancelled, deadline._seconds.isFinite else { return }
        let mine = generation
        Task { @MainActor in
            var next = self.deadline
            while true {
                let delay = next._delay
                if delay > 0 { try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
                guard self.generation == mine else { return }
                if let handler = self.handler { self.queue.sync(execute: handler) }
                guard self.interval._seconds.isFinite, self.interval._seconds > 0 else { return }
                next = max(next + self.interval, .now())
            }
        }
    }
}
#endif
