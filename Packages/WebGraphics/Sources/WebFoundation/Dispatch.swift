// `DispatchQueue` on wasm (decision 0021): there is no Dispatch module in the wasm SDK, and
// Apple's Foundation re-exports it, so apps write `DispatchQueue.main.async` under
// `import Foundation` or `import SwiftUI`. The page has one thread: every queue runs its work
// on the main actor through the host's executor (JavaScriptEventLoop), `sync` runs it in place,
// and a deadline waits with `Task.sleep`.
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
    public static func now() -> DispatchTime { DispatchTime(_seconds: _monotonicNow()) }
    public static let distantFuture = DispatchTime(_seconds: .infinity)
    public static func < (a: DispatchTime, b: DispatchTime) -> Bool { a._seconds < b._seconds }
    public static func + (t: DispatchTime, seconds: Double) -> DispatchTime { DispatchTime(_seconds: t._seconds + seconds) }
    public static func - (t: DispatchTime, seconds: Double) -> DispatchTime { DispatchTime(_seconds: t._seconds - seconds) }
    public static func + (t: DispatchTime, interval: DispatchTimeInterval) -> DispatchTime { t + interval._seconds }
    public var _delay: Double { max(0, _seconds - _monotonicNow()) }
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
    public init(qos: DispatchQoS = .unspecified, block: @escaping @Sendable () -> Void) { self.block = block }
    public func cancel() { isCancelled = true }
    public func perform() { if !isCancelled { block() } }
}

public final class DispatchQueue: @unchecked Sendable {
    public struct Attributes: OptionSet, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let concurrent = Attributes(rawValue: 1)
    }

    public static let main = DispatchQueue(label: "com.apple.main-thread")
    private static let globalQueue = DispatchQueue(label: "com.apple.root.default-qos")
    public static func global(qos: DispatchQoS.QoSClass = .default) -> DispatchQueue { globalQueue }

    public let label: String
    public init(label: String, qos: DispatchQoS = .unspecified, attributes: Attributes = [], target: DispatchQueue? = nil) {
        self.label = label
    }

    /// Runs the work on the main actor after the current turn.
    public func async(group: Any? = nil, qos: DispatchQoS = .unspecified, flags: Int = 0, execute work: @escaping @Sendable () -> Void) {
        Task { @MainActor in work() }
    }
    public func async(execute item: DispatchWorkItem) {
        Task { @MainActor in item.perform() }
    }
    /// Runs the work now: the page has one thread, so there is nothing to wait for.
    public func sync<T>(execute work: () throws -> T) rethrows -> T { try work() }
    public func sync(execute item: DispatchWorkItem) { item.perform() }
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
    public func notify(queue: DispatchQueue, execute work: @escaping @Sendable () -> Void) {
        if count <= 0 { queue.async(execute: work) } else { waiters.append { queue.async(execute: work) } }
    }
}
#endif
