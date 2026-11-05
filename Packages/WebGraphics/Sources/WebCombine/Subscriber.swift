// Combine's subscriber model over WebCombine's closure subscriptions: `Subscriber`,
// `Subscription` and `Subscribers.Demand`. A publisher written against Combine implements
// `receive(subscriber:)` and gets `_subscribe` from it; WebCombine's own publishers implement
// `_subscribe` and get `receive(subscriber:)`, which honours the subscriber's demand by holding
// values back until it asks for more.
import WebFoundation

/// A unique identifier for identifying publisher streams.
public struct CombineIdentifier: Hashable, Sendable, CustomStringConvertible {
    private let value: UInt
    public init() {
        _nextCombineIdentifier.value += 1
        value = _nextCombineIdentifier.value
    }
    public init(_ object: AnyObject) { value = UInt(bitPattern: ObjectIdentifier(object).hashValue) }
    public var description: String { "0x" + String(value, radix: 16) }
}

private let _nextCombineIdentifier = _CombineCounter()
private final class _CombineCounter: @unchecked Sendable { var value: UInt = 0 }

/// A type that has a Combine identifier.
public protocol CustomCombineIdentifierConvertible {
    var combineIdentifier: CombineIdentifier { get }
}

extension CustomCombineIdentifierConvertible where Self: AnyObject {
    public var combineIdentifier: CombineIdentifier { CombineIdentifier(self) }
}

/// A protocol representing the connection of a subscriber to a publisher.
public protocol Subscription: Cancellable, CustomCombineIdentifierConvertible {
    /// Tells a publisher that it may send more values to the subscriber.
    func request(_ demand: Subscribers.Demand)
}

/// A protocol that declares a type that can receive input from a publisher.
public protocol Subscriber<Input, Failure>: CustomCombineIdentifierConvertible {
    associatedtype Input
    associatedtype Failure: Error
    func receive(subscription: any Subscription)
    func receive(_ input: Input) -> Subscribers.Demand
    func receive(completion: Subscribers.Completion<Failure>)
}

extension Subscriber where Input == Void {
    public func receive() -> Subscribers.Demand { receive(()) }
}

extension Subscribers {
    /// A requested number of items, sent to a publisher from a subscriber through the subscription.
    public struct Demand: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
        /// The number of requested values, or nil when unlimited.
        public let max: Int?
        private init(_ max: Int?) { self.max = max }

        public static let unlimited = Demand(nil)
        public static let none = Demand(0)
        public static func max(_ value: Int) -> Demand {
            precondition(value >= 0, "demand must not be negative")
            return Demand(value)
        }

        public var description: String { max.map { "max(\($0))" } ?? "unlimited" }

        public static func + (lhs: Demand, rhs: Demand) -> Demand {
            guard let l = lhs.max, let r = rhs.max else { return .unlimited }
            let (sum, overflow) = l.addingReportingOverflow(r)
            return overflow ? .unlimited : Demand(sum)
        }
        public static func + (lhs: Demand, rhs: Int) -> Demand { lhs + Demand(Swift.max(0, rhs)) }
        public static func - (lhs: Demand, rhs: Demand) -> Demand {
            guard let l = lhs.max else { return .unlimited }
            guard let r = rhs.max else { return .none }
            return Demand(Swift.max(0, l - r))
        }
        public static func - (lhs: Demand, rhs: Int) -> Demand { lhs.max.map { Demand(Swift.max(0, $0 - rhs)) } ?? .unlimited }
        public static func * (lhs: Demand, rhs: Int) -> Demand {
            guard let l = lhs.max else { return .unlimited }
            let (product, overflow) = l.multipliedReportingOverflow(by: Swift.max(0, rhs))
            return overflow ? .unlimited : Demand(product)
        }
        public static func += (lhs: inout Demand, rhs: Demand) { lhs = lhs + rhs }
        public static func += (lhs: inout Demand, rhs: Int) { lhs = lhs + rhs }
        public static func -= (lhs: inout Demand, rhs: Demand) { lhs = lhs - rhs }
        public static func -= (lhs: inout Demand, rhs: Int) { lhs = lhs - rhs }
        public static func *= (lhs: inout Demand, rhs: Int) { lhs = lhs * rhs }

        public static func < (lhs: Demand, rhs: Demand) -> Bool {
            switch (lhs.max, rhs.max) {
            case let (l?, r?): return l < r
            case (_?, nil): return true
            default: return false
            }
        }
        public static func == (lhs: Demand, rhs: Int) -> Bool { lhs.max == rhs }
        public static func != (lhs: Demand, rhs: Int) -> Bool { lhs.max != rhs }
        public static func < (lhs: Demand, rhs: Int) -> Bool { lhs.max.map { $0 < rhs } ?? false }
        public static func > (lhs: Demand, rhs: Int) -> Bool { lhs.max.map { $0 > rhs } ?? true }
        public static func <= (lhs: Demand, rhs: Int) -> Bool { lhs.max.map { $0 <= rhs } ?? false }
        public static func >= (lhs: Demand, rhs: Int) -> Bool { lhs.max.map { $0 >= rhs } ?? true }
    }
}

extension Publisher {
    /// Attaches the subscriber to this publisher. Publishers written against Combine implement
    /// this; WebCombine's own get it from `_subscribe`.
    public func receive<S: Subscriber>(subscriber: S) where S.Input == Output, S.Failure == Failure {
        nonisolated(unsafe) let publisher = self
        let bridge = _DemandBridge<Output, Failure>(
            receive: { subscriber.receive($0) },
            complete: { subscriber.receive(completion: $0) })
        subscriber.receive(subscription: bridge)
        MainActor.assumeIsolated { bridge.start { publisher._subscribe($0, $1) } }
    }

    /// Delivery through `receive(subscriber:)`, for publishers that implement only that.
    @MainActor public func _subscribe(_ receive: @escaping @MainActor (Output) -> Void,
                                      _ complete: @escaping @MainActor (Subscribers.Completion<Failure>) -> Void) -> AnyCancellable {
        let sink = _ClosureSubscriber<Output, Failure>(receive, complete)
        self.receive(subscriber: sink)
        return AnyCancellable { sink.cancel() }
    }

    /// Attaches the specified subscriber to this publisher.
    public func subscribe<S: Subscriber>(_ subscriber: S) where S.Input == Output, S.Failure == Failure {
        receive(subscriber: subscriber)
    }
}

/// The subscription a WebCombine publisher hands a Combine subscriber: values wait in order
/// until the subscriber's demand allows them; completion follows the last of them.
final class _DemandBridge<Output, Failure: Error>: Subscription, @unchecked Sendable {
    private var downstream: (receive: (Output) -> Subscribers.Demand, complete: (Subscribers.Completion<Failure>) -> Void)?
    private var demand = Subscribers.Demand.none
    private var buffer: [Output] = []
    private var completion: Subscribers.Completion<Failure>?
    private var upstream: AnyCancellable?
    private var draining = false

    init(receive: @escaping (Output) -> Subscribers.Demand, complete: @escaping (Subscribers.Completion<Failure>) -> Void) {
        downstream = (receive, complete)
    }

    @MainActor func start(_ subscribe: (@escaping @MainActor (Output) -> Void,
                                         @escaping @MainActor (Subscribers.Completion<Failure>) -> Void) -> AnyCancellable) {
        guard downstream != nil else { return }
        let cancellable = subscribe({ [weak self] in self?.buffer.append($0); self?.drain() },
                                    { [weak self] in self?.completion = $0; self?.drain() })
        if downstream == nil { cancellable.cancel() } else { upstream = cancellable }
    }

    func request(_ more: Subscribers.Demand) {
        demand += more
        drain()
    }

    func cancel() {
        downstream = nil
        buffer = []
        upstream?.cancel()
        upstream = nil
    }

    private func drain() {
        guard !draining else { return }
        draining = true
        defer { draining = false }
        while demand > 0, !buffer.isEmpty, let downstream {
            demand -= 1
            demand += downstream.receive(buffer.removeFirst())
        }
        if buffer.isEmpty, let completion, let downstream {
            self.downstream = nil
            upstream = nil
            downstream.complete(completion)
        }
    }
}

/// A subscriber that asks for every value and hands each to closures on the main actor.
final class _ClosureSubscriber<Input, Failure: Error>: Subscriber, Cancellable, @unchecked Sendable {
    private let onValue: @MainActor (Input) -> Void
    private let onCompletion: @MainActor (Subscribers.Completion<Failure>) -> Void
    private var subscription: (any Subscription)?
    private var done = false

    init(_ onValue: @escaping @MainActor (Input) -> Void, _ onCompletion: @escaping @MainActor (Subscribers.Completion<Failure>) -> Void) {
        self.onValue = onValue
        self.onCompletion = onCompletion
    }

    func receive(subscription: any Subscription) {
        guard !done, self.subscription == nil else { return subscription.cancel() }
        self.subscription = subscription
        subscription.request(.unlimited)
    }

    func receive(_ input: Input) -> Subscribers.Demand {
        guard !done else { return .none }
        nonisolated(unsafe) let input = input
        MainActor.assumeIsolated { onValue(input) }
        return .none
    }

    func receive(completion: Subscribers.Completion<Failure>) {
        guard !done else { return }
        done = true
        subscription = nil
        nonisolated(unsafe) let completion = completion
        MainActor.assumeIsolated { onCompletion(completion) }
    }

    func cancel() {
        done = true
        subscription?.cancel()
        subscription = nil
    }
}
