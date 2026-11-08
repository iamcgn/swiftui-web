// Combine's connectable publishers and its type-erased subscriber (Docs/coverage.md:
// combine-schedulers' `Publishers.Timer`, which EhPanda and other TCA apps build from source,
// is a `ConnectablePublisher` that routes values through `AnySubscriber`s). A connectable
// publisher starts its work on `connect()`; `autoconnect()` connects on the first
// subscription and disconnects when the last one is cancelled. `multicast` and
// `makeConnectable()` share one upstream subscription through a subject.
import WebFoundation

/// A publisher that provides an explicit means of connecting and cancelling publication.
public protocol ConnectablePublisher<Output, Failure>: Publisher {
    /// Connects to the publisher, allowing it to produce elements; cancelling the result stops it.
    func connect() -> any Cancellable
}

extension ConnectablePublisher {
    /// Connects on the first subscription and disconnects when the last one is cancelled.
    public func autoconnect() -> Publishers.Autoconnect<Self> { Publishers.Autoconnect(self) }
}

extension Publishers {
    /// A publisher that connects its upstream while it has subscribers.
    public final class Autoconnect<Upstream: ConnectablePublisher>: Publisher, @unchecked Sendable {
        public typealias Output = Upstream.Output
        public typealias Failure = Upstream.Failure
        public let upstream: Upstream
        private var subscribers = 0
        private var connection: (any Cancellable)?

        public init(_ upstream: Upstream) { self.upstream = upstream }

        @MainActor public func _subscribe(_ receive: @escaping @MainActor (Output) -> Void,
                                          _ complete: @escaping @MainActor (Subscribers.Completion<Failure>) -> Void) -> AnyCancellable {
            let inner = upstream._subscribe(receive, complete)
            subscribers += 1
            if connection == nil { connection = upstream.connect() }
            // `AnyCancellable` runs this once.
            return AnyCancellable { [self] in
                inner.cancel()
                subscribers -= 1
                if subscribers == 0 {
                    connection?.cancel()
                    connection = nil
                }
            }
        }
    }

    /// A publisher that shares its upstream through a subject, from `connect()` on.
    public final class Multicast<Upstream: Publisher, SubjectType: Subject>: ConnectablePublisher, @unchecked Sendable
    where SubjectType.Output == Upstream.Output, SubjectType.Failure == Upstream.Failure {
        public typealias Output = Upstream.Output
        public typealias Failure = Upstream.Failure
        public let upstream: Upstream
        public let createSubject: () -> SubjectType
        private lazy var subject = createSubject()

        public init(upstream: Upstream, createSubject: @escaping () -> SubjectType) {
            self.upstream = upstream
            self.createSubject = createSubject
        }

        @MainActor public func _subscribe(_ receive: @escaping @MainActor (Output) -> Void,
                                          _ complete: @escaping @MainActor (Subscribers.Completion<Failure>) -> Void) -> AnyCancellable {
            subject._subscribe(receive, complete)
        }

        public func connect() -> any Cancellable {
            nonisolated(unsafe) let subject = subject
            return upstream._subscribeFromAnywhere({ subject.send($0) }, { subject.send(completion: $0) })
        }
    }
}

extension Publishers {
    /// A connectable wrapper around a publisher, shared through a `PassthroughSubject` (a
    /// multicast here rather than a type of its own, one publisher type fewer to link).
    public typealias MakeConnectable<Upstream: Publisher> = Multicast<Upstream, PassthroughSubject<Upstream.Output, Upstream.Failure>>
}

extension Publisher {
    /// Shares this publisher through the subject the closure makes, once `connect()` is called.
    public func multicast<S: Subject>(_ createSubject: @escaping () -> S) -> Publishers.Multicast<Self, S>
    where S.Output == Output, S.Failure == Failure {
        Publishers.Multicast(upstream: self, createSubject: createSubject)
    }

    /// Shares this publisher through the subject, once `connect()` is called.
    public func multicast<S: Subject>(subject: S) -> Publishers.Multicast<Self, S> where S.Output == Output, S.Failure == Failure {
        nonisolated(unsafe) let subject = subject
        return Publishers.Multicast(upstream: self) { subject }
    }
}

extension Publisher where Failure == Never {
    /// A connectable wrapper around this publisher.
    public func makeConnectable() -> Publishers.MakeConnectable<Self> { multicast { PassthroughSubject() } }
}

/// A type-erasing subscriber.
public struct AnySubscriber<Input, Failure: Error>: Subscriber, CustomStringConvertible {
    public let combineIdentifier: CombineIdentifier
    private let receiveSubscriptionThunk: ((any Subscription) -> Void)?
    private let receiveValueThunk: ((Input) -> Subscribers.Demand)?
    private let receiveCompletionThunk: ((Subscribers.Completion<Failure>) -> Void)?
    private let describe: String

    /// Wraps the subscriber.
    public init<S: Subscriber>(_ s: S) where S.Input == Input, S.Failure == Failure {
        if let erased = s as? AnySubscriber<Input, Failure> {
            self = erased
            return
        }
        combineIdentifier = s.combineIdentifier
        receiveSubscriptionThunk = { s.receive(subscription: $0) }
        receiveValueThunk = { s.receive($0) }
        receiveCompletionThunk = { s.receive(completion: $0) }
        describe = (s as? CustomStringConvertible)?.description ?? "\(S.self)"
    }

    /// Feeds the subject: every value and the completion are sent to it.
    public init<S: Subject>(_ s: S) where S.Output == Input, S.Failure == Failure {
        nonisolated(unsafe) let subject = s
        self.init(receiveSubscription: { $0.request(.unlimited) },
                  receiveValue: { subject.send($0); return .none },
                  receiveCompletion: { subject.send(completion: $0) })
    }

    /// A subscriber made of the closures; a missing one does nothing (and asks for nothing more).
    public init(receiveSubscription: ((any Subscription) -> Void)? = nil,
                receiveValue: ((Input) -> Subscribers.Demand)? = nil,
                receiveCompletion: ((Subscribers.Completion<Failure>) -> Void)? = nil) {
        combineIdentifier = CombineIdentifier()
        receiveSubscriptionThunk = receiveSubscription
        receiveValueThunk = receiveValue
        receiveCompletionThunk = receiveCompletion
        describe = "Anonymous AnySubscriber"
    }

    public var description: String { describe }

    public func receive(subscription: any Subscription) { receiveSubscriptionThunk?(subscription) }
    public func receive(_ value: Input) -> Subscribers.Demand { receiveValueThunk?(value) ?? .none }
    public func receive(completion: Subscribers.Completion<Failure>) { receiveCompletionThunk?(completion) }
}
