// Combine's schedulers: the `Scheduler` protocol, `ImmediateScheduler`, and the conformances of
// `DispatchQueue`, `RunLoop` and `OperationQueue` with their time types. Libraries such as
// CombineSchedulers build test and type-erased schedulers on these. Everything runs on the
// queue it names (on wasm, the page's one thread). Apple's Combine provides these on Darwin.
import WebFoundation

/// A protocol that provides a scheduler with an expression for relative time.
public protocol SchedulerTimeIntervalConvertible {
    static func seconds(_ s: Int) -> Self
    static func seconds(_ s: Double) -> Self
    static func milliseconds(_ ms: Int) -> Self
    static func microseconds(_ us: Int) -> Self
    static func nanoseconds(_ ns: Int) -> Self
}

/// A protocol that defines when and how to execute a closure.
public protocol Scheduler<SchedulerTimeType> {
    associatedtype SchedulerTimeType: Strideable where SchedulerTimeType.Stride: SchedulerTimeIntervalConvertible
    associatedtype SchedulerOptions
    var now: SchedulerTimeType { get }
    var minimumTolerance: SchedulerTimeType.Stride { get }
    func schedule(options: SchedulerOptions?, _ action: @escaping () -> Void)
    func schedule(after date: SchedulerTimeType, tolerance: SchedulerTimeType.Stride,
                  options: SchedulerOptions?, _ action: @escaping () -> Void)
    func schedule(after date: SchedulerTimeType, interval: SchedulerTimeType.Stride, tolerance: SchedulerTimeType.Stride,
                  options: SchedulerOptions?, _ action: @escaping () -> Void) -> any Cancellable
}

extension Scheduler {
    public func schedule(_ action: @escaping () -> Void) { schedule(options: nil, action) }
    public func schedule(after date: SchedulerTimeType, _ action: @escaping () -> Void) {
        schedule(after: date, tolerance: minimumTolerance, options: nil, action)
    }
    public func schedule(after date: SchedulerTimeType, tolerance: SchedulerTimeType.Stride, _ action: @escaping () -> Void) {
        schedule(after: date, tolerance: tolerance, options: nil, action)
    }
    public func schedule(after date: SchedulerTimeType, interval: SchedulerTimeType.Stride,
                         tolerance: SchedulerTimeType.Stride, _ action: @escaping () -> Void) -> any Cancellable {
        schedule(after: date, interval: interval, tolerance: tolerance, options: nil, action)
    }
    public func schedule(after date: SchedulerTimeType, interval: SchedulerTimeType.Stride, _ action: @escaping () -> Void) -> any Cancellable {
        schedule(after: date, interval: interval, tolerance: minimumTolerance, options: nil, action)
    }
}

// MARK: - Strides

/// The arithmetic every scheduler stride shares, over its raw count (seconds or nanoseconds).
public protocol _SchedulerStride: SchedulerTimeIntervalConvertible, SignedNumeric, Comparable, Hashable, ExpressibleByFloatLiteral {
    associatedtype _Raw: SignedNumeric & Comparable & Hashable
    var _raw: _Raw { get }
    init(_raw: _Raw)
    static func _raw(seconds: Double) -> _Raw
}

extension _SchedulerStride {
    public init(integerLiteral value: Int) { self = .seconds(value) }
    public init(floatLiteral value: Double) { self = .seconds(value) }
    public init?<T: BinaryInteger>(exactly source: T) {
        guard let value = Int(exactly: source) else { return nil }
        self = .seconds(value)
    }
    public static func seconds(_ s: Int) -> Self { Self(_raw: _raw(seconds: Double(s))) }
    public static func seconds(_ s: Double) -> Self { Self(_raw: _raw(seconds: s)) }
    public static func milliseconds(_ ms: Int) -> Self { Self(_raw: _raw(seconds: Double(ms) / 1e3)) }
    public static func microseconds(_ us: Int) -> Self { Self(_raw: _raw(seconds: Double(us) / 1e6)) }
    public static func nanoseconds(_ ns: Int) -> Self { Self(_raw: _raw(seconds: Double(ns) / 1e9)) }

    public static func + (lhs: Self, rhs: Self) -> Self { Self(_raw: lhs._raw + rhs._raw) }
    public static func - (lhs: Self, rhs: Self) -> Self { Self(_raw: lhs._raw - rhs._raw) }
    public static func * (lhs: Self, rhs: Self) -> Self { Self(_raw: lhs._raw * rhs._raw) }
    public static func += (lhs: inout Self, rhs: Self) { lhs = lhs + rhs }
    public static func -= (lhs: inout Self, rhs: Self) { lhs = lhs - rhs }
    public static func *= (lhs: inout Self, rhs: Self) { lhs = lhs * rhs }
    public static func < (lhs: Self, rhs: Self) -> Bool { lhs._raw < rhs._raw }
    public static func == (lhs: Self, rhs: Self) -> Bool { lhs._raw == rhs._raw }
    public func hash(into hasher: inout Hasher) { hasher.combine(_raw) }
}

/// A stride counted in seconds, for the date-based schedulers.
public struct _SecondsStride: _SchedulerStride, Sendable {
    public typealias IntegerLiteralType = Int
    public typealias FloatLiteralType = Double
    /// The interval in seconds.
    public var magnitude: Double
    public var timeInterval: Double { magnitude }
    public init(_ timeInterval: Double) { magnitude = timeInterval }
    public init(_raw: Double) { magnitude = _raw }
    public var _raw: Double { magnitude }
    public static func _raw(seconds: Double) -> Double { seconds }
}

/// A point in time on a date-based scheduler (`RunLoop`, `OperationQueue`).
public struct _DateSchedulerTime: Strideable, Hashable, Sendable {
    public typealias Stride = _SecondsStride
    public var date: Date
    public init(_ date: Date) { self.date = date }
    public func distance(to other: _DateSchedulerTime) -> Stride { Stride(other.date.timeIntervalSince(date)) }
    public func advanced(by n: Stride) -> _DateSchedulerTime { _DateSchedulerTime(date.addingTimeInterval(n.timeInterval)) }
}

/// Options for the date-based schedulers; they have none.
public struct _DateSchedulerOptions: Sendable {}

/// Marks a repeating schedule cancelled.
private final class _RepeatToken: @unchecked Sendable { var cancelled = false }

/// Runs `action` on `queue` at `start`, then every `interval` until cancelled.
private func _repeat(on queue: DispatchQueue, startingIn delay: Double, every interval: Double,
                     _ action: @escaping () -> Void) -> any Cancellable {
    let token = _RepeatToken()
    nonisolated(unsafe) let action = action
    @Sendable func fire(in delay: Double) {
        queue.asyncAfter(deadline: .now() + max(0, delay)) {
            guard !token.cancelled else { return }
            action()
            fire(in: max(interval, 0.001))
        }
    }
    fire(in: delay)
    return AnyCancellable { token.cancelled = true }
}

// MARK: - ImmediateScheduler

/// A scheduler for performing synchronous actions.
public struct ImmediateScheduler: Scheduler, Sendable {
    public struct SchedulerTimeType: Strideable, Hashable, Sendable {
        public struct Stride: _SchedulerStride, Sendable {
            public typealias IntegerLiteralType = Int
            public typealias FloatLiteralType = Double
            public var magnitude: Int
            public init(_ value: Int) { magnitude = value }
            public init(_raw: Int) { magnitude = _raw }
            public var _raw: Int { magnitude }
            public static func _raw(seconds: Double) -> Int { Int(seconds) }
        }
        public func distance(to other: SchedulerTimeType) -> Stride { Stride(0) }
        public func advanced(by n: Stride) -> SchedulerTimeType { self }
    }
    public typealias SchedulerOptions = Never

    public static let shared = ImmediateScheduler()
    public var now: SchedulerTimeType { SchedulerTimeType() }
    public var minimumTolerance: SchedulerTimeType.Stride { .zero }
    public func schedule(options: Never?, _ action: @escaping () -> Void) { action() }
    public func schedule(after date: SchedulerTimeType, tolerance: SchedulerTimeType.Stride,
                         options: Never?, _ action: @escaping () -> Void) { action() }
    public func schedule(after date: SchedulerTimeType, interval: SchedulerTimeType.Stride, tolerance: SchedulerTimeType.Stride,
                         options: Never?, _ action: @escaping () -> Void) -> any Cancellable {
        action()
        return AnyCancellable {}
    }
}

#if !canImport(Darwin)
// MARK: - DispatchQueue

extension DispatchQueue: Scheduler {
    /// A point in time on a dispatch queue.
    public struct SchedulerTimeType: Strideable, Hashable, Sendable {
        /// A dispatch queue's interval. Kept in seconds so that it holds more than two seconds
        /// where `Int` is 32 bits (wasm32); `magnitude` gives it in nanoseconds, as Apple's.
        public struct Stride: _SchedulerStride, Sendable {
            public typealias IntegerLiteralType = Int
            public typealias FloatLiteralType = Double
            public let _raw: Double
            public init(_raw: Double) { self._raw = _raw }
            /// The interval in nanoseconds.
            public var magnitude: Int {
                let ns = (_raw * 1e9).rounded()
                return ns >= Double(Int.max) ? .max : ns <= Double(Int.min) ? .min : Int(ns)
            }
            public var timeInterval: DispatchTimeInterval { .nanoseconds(magnitude) }
            public init(_ timeInterval: DispatchTimeInterval) {
                #if os(WASI)
                _raw = timeInterval._seconds
                #else
                switch timeInterval {
                case .seconds(let s): _raw = Double(s)
                case .milliseconds(let ms): _raw = Double(ms) / 1e3
                case .microseconds(let us): _raw = Double(us) / 1e6
                case .nanoseconds(let ns): _raw = Double(ns) / 1e9
                default: _raw = .infinity
                }
                #endif
            }
            public static func _raw(seconds: Double) -> Double { seconds }
        }

        public var dispatchTime: DispatchTime
        public init(_ time: DispatchTime) { dispatchTime = time }
        private var uptime: UInt64 { dispatchTime.uptimeNanoseconds }
        public func distance(to other: SchedulerTimeType) -> Stride {
            let delta = other.uptime >= uptime ? Double(other.uptime - uptime) : -Double(uptime - other.uptime)
            return Stride(_raw: delta / 1e9)
        }
        public func advanced(by n: Stride) -> SchedulerTimeType {
            let target = (Double(uptime) + n._raw * 1e9).rounded()
            let ns: UInt64 = target <= 0 ? 0 : target >= Double(UInt64.max) ? .max : UInt64(target)
            return SchedulerTimeType(DispatchTime(uptimeNanoseconds: ns))
        }
        public static func == (lhs: SchedulerTimeType, rhs: SchedulerTimeType) -> Bool { lhs.uptime == rhs.uptime }
        public func hash(into hasher: inout Hasher) { hasher.combine(uptime) }
    }

    /// Options that affect the operation of the dispatch queue scheduler.
    public struct SchedulerOptions: @unchecked Sendable {
        public var qos: DispatchQoS
        public var flags: DispatchWorkItemFlags
        public var group: DispatchGroup?
        public init(qos: DispatchQoS = .unspecified, flags: DispatchWorkItemFlags = [], group: DispatchGroup? = nil) {
            self.qos = qos
            self.flags = flags
            self.group = group
        }
    }

    public var now: SchedulerTimeType { SchedulerTimeType(.now()) }
    public var minimumTolerance: SchedulerTimeType.Stride { .zero }

    public func schedule(options: SchedulerOptions?, _ action: @escaping () -> Void) {
        nonisolated(unsafe) let action = action
        async(group: options?.group, qos: options?.qos ?? .unspecified, flags: options?.flags ?? []) { action() }
    }

    public func schedule(after date: SchedulerTimeType, tolerance: SchedulerTimeType.Stride,
                         options: SchedulerOptions?, _ action: @escaping () -> Void) {
        nonisolated(unsafe) let action = action
        asyncAfter(deadline: date.dispatchTime, qos: options?.qos ?? .unspecified) { action() }
    }

    public func schedule(after date: SchedulerTimeType, interval: SchedulerTimeType.Stride, tolerance: SchedulerTimeType.Stride,
                         options: SchedulerOptions?, _ action: @escaping () -> Void) -> any Cancellable {
        _repeat(on: self, startingIn: now.distance(to: date)._raw, every: interval._raw, action)
    }
}

// MARK: - RunLoop and OperationQueue

extension RunLoop: Scheduler {
    public typealias SchedulerTimeType = _DateSchedulerTime
    public typealias SchedulerOptions = _DateSchedulerOptions

    public var now: SchedulerTimeType { SchedulerTimeType(Date()) }
    public var minimumTolerance: SchedulerTimeType.Stride { .zero }
    public func schedule(options: SchedulerOptions?, _ action: @escaping () -> Void) {
        nonisolated(unsafe) let action = action
        DispatchQueue.main.async { action() }
    }
    public func schedule(after date: SchedulerTimeType, tolerance: SchedulerTimeType.Stride,
                         options: SchedulerOptions?, _ action: @escaping () -> Void) {
        nonisolated(unsafe) let action = action
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, date.date.timeIntervalSinceNow)) { action() }
    }
    public func schedule(after date: SchedulerTimeType, interval: SchedulerTimeType.Stride, tolerance: SchedulerTimeType.Stride,
                         options: SchedulerOptions?, _ action: @escaping () -> Void) -> any Cancellable {
        _repeat(on: .main, startingIn: date.date.timeIntervalSinceNow, every: interval.timeInterval, action)
    }
}

extension OperationQueue: Scheduler {
    public typealias SchedulerTimeType = _DateSchedulerTime
    public typealias SchedulerOptions = _DateSchedulerOptions

    // Every action runs as an operation on this queue, as Apple's do, so the queue's
    // suspension, concurrency limit and cancellation apply to it; a delay waits on the main
    // queue before the operation is added.
    public var now: SchedulerTimeType { SchedulerTimeType(Date()) }
    public var minimumTolerance: SchedulerTimeType.Stride { .zero }
    public func schedule(options: SchedulerOptions?, _ action: @escaping () -> Void) {
        nonisolated(unsafe) let action = action
        addOperation { action() }
    }
    public func schedule(after date: SchedulerTimeType, tolerance: SchedulerTimeType.Stride,
                         options: SchedulerOptions?, _ action: @escaping () -> Void) {
        nonisolated(unsafe) let action = action
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, date.date.timeIntervalSinceNow)) { [self] in
            addOperation { action() }
        }
    }
    public func schedule(after date: SchedulerTimeType, interval: SchedulerTimeType.Stride, tolerance: SchedulerTimeType.Stride,
                         options: SchedulerOptions?, _ action: @escaping () -> Void) -> any Cancellable {
        nonisolated(unsafe) let action = action
        return _repeat(on: .main, startingIn: date.date.timeIntervalSinceNow, every: interval.timeInterval) { [self] in
            addOperation { action() }
        }
    }
}
#endif
