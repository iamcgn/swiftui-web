// Combine's publishers without Combine (decision 0021, `Docs/elements/ObservableObject.md`): a
// publisher delivers its values and then its completion to closures on the main actor, and the
// subscription is an `AnyCancellable`. `Just`, the subjects, `Timer.publish`,
// `NotificationCenter.publisher`, `objectWillChange` and `$published` are here; the operators
// in Operators.swift. SwiftUI's `onReceive` subscribes to any of them; on wasm
// `import Combine` (Packages/Shadows) is this module.
import WebFoundation

/// A type that delivers values to subscribers, then finishes or fails.
public protocol Publisher<Output, Failure> {
    associatedtype Output
    associatedtype Failure: Error
    /// Subscribes `receive` to the values and `complete` to the end; cancelling the result ends
    /// the subscription. Every delivery is on the main actor.
    @MainActor func _subscribe(_ receive: @escaping @MainActor (Output) -> Void,
                               _ complete: @escaping @MainActor (Subscribers.Completion<Failure>) -> Void) -> AnyCancellable
    /// Combine's entry point; each of the two has a default in terms of the other
    /// (Subscriber.swift), so a publisher implements one.
    func receive<S: Subscriber>(subscriber: S) where S.Input == Output, S.Failure == Failure
}

public enum Subscribers {
    /// How a publisher ended.
    public enum Completion<Failure: Error> {
        case finished
        case failure(Failure)
    }
}

/// A protocol indicating that an activity or action supports cancellation.
public protocol Cancellable {
    func cancel()
}

extension AnyCancellable: Cancellable {}

extension Publisher {
    /// Subscribes to the values alone.
    @MainActor public func _subscribe(_ receive: @escaping @MainActor (Output) -> Void) -> AnyCancellable {
        _subscribe(receive) { _ in }
    }

    /// Subscribes from any isolation: Combine's `sink` is nonisolated, and app models call it
    /// from their initialisers. Everything here runs on the main actor (one thread on wasm; the
    /// native hosts subscribe from the main thread too).
    func _subscribeFromAnywhere(_ receive: @escaping @MainActor (Output) -> Void,
                                _ complete: @escaping @MainActor (Subscribers.Completion<Failure>) -> Void) -> AnyCancellable {
        nonisolated(unsafe) let publisher = self
        return MainActor.assumeIsolated { publisher._subscribe(receive, complete) }
    }

    /// Attaches a subscriber with closure-based behaviour to a publisher that never fails. The
    /// closures are plain, as Combine's: they run on the main actor, where every value arrives.
    public func sink(receiveValue: @escaping (Output) -> Void) -> AnyCancellable where Failure == Never {
        nonisolated(unsafe) let receiveValue = receiveValue
        return _subscribeFromAnywhere({ receiveValue($0) }) { _ in }
    }

    /// Attaches a subscriber with closure-based behaviour.
    public func sink(receiveCompletion: @escaping (Subscribers.Completion<Failure>) -> Void,
                     receiveValue: @escaping (Output) -> Void) -> AnyCancellable {
        nonisolated(unsafe) let receiveValue = receiveValue
        nonisolated(unsafe) let receiveCompletion = receiveCompletion
        return _subscribeFromAnywhere({ receiveValue($0) }, { receiveCompletion($0) })
    }

    /// Assigns each value to a property of an object.
    public func assign<Root: AnyObject>(to keyPath: ReferenceWritableKeyPath<Root, Output>, on object: Root) -> AnyCancellable where Failure == Never {
        nonisolated(unsafe) let object = object
        nonisolated(unsafe) let keyPath = keyPath
        return _subscribeFromAnywhere({ object[keyPath: keyPath] = $0 }) { _ in }
    }

    /// Connectable publishers connect on their first subscription here; the publisher itself.
    public func autoconnect() -> Self { self }
}

// MARK: - Just, Empty, Fail

/// A publisher that emits one value on subscription, then finishes.
public struct Just<Output>: Publisher {
    public typealias Failure = Never
    public let output: Output
    public init(_ output: Output) { self.output = output }
    @MainActor public func _subscribe(_ receive: @escaping @MainActor (Output) -> Void,
                                      _ complete: @escaping @MainActor (Subscribers.Completion<Never>) -> Void) -> AnyCancellable {
        receive(output)
        complete(.finished)
        return AnyCancellable {}
    }
}

/// A publisher that never publishes any values, and optionally finishes immediately.
public struct Empty<Output, Failure: Error>: Publisher {
    public let completeImmediately: Bool
    public init(completeImmediately: Bool = true) { self.completeImmediately = completeImmediately }
    public init(completeImmediately: Bool = true, outputType: Output.Type, failureType: Failure.Type) { self.completeImmediately = completeImmediately }
    @MainActor public func _subscribe(_ receive: @escaping @MainActor (Output) -> Void,
                                      _ complete: @escaping @MainActor (Subscribers.Completion<Failure>) -> Void) -> AnyCancellable {
        if completeImmediately { complete(.finished) }
        return AnyCancellable {}
    }
}

/// A publisher that immediately terminates with the specified error.
public struct Fail<Output, Failure: Error>: Publisher {
    public let error: Failure
    public init(error: Failure) { self.error = error }
    public init(outputType: Output.Type, failure: Failure) { error = failure }
    @MainActor public func _subscribe(_ receive: @escaping @MainActor (Output) -> Void,
                                      _ complete: @escaping @MainActor (Subscribers.Completion<Failure>) -> Void) -> AnyCancellable {
        complete(.failure(error))
        return AnyCancellable {}
    }
}

#if !(canImport(Darwin) && !os(WASI))
// Apple's Combine declares this beside `Just` and `Fail`; on Apple platforms it is Combine's.
extension Result {
    /// A publisher of the result: its value and then finished, or its error (Alamofire's
    /// `DataResponsePublisher` maps each response's result through `result.publisher`).
    public var publisher: Publisher { Publisher(self) }

    /// A publisher that publishes a result's value once and finishes, or fails with its error.
    public struct Publisher: WebCombine.Publisher {
        public typealias Output = Success
        public let result: Result<Success, Failure>
        public init(_ result: Result<Success, Failure>) { self.result = result }
        public init(_ output: Success) { result = .success(output) }
        public init(_ failure: Failure) { result = .failure(failure) }
        @MainActor public func _subscribe(_ receive: @escaping @MainActor (Success) -> Void,
                                          _ complete: @escaping @MainActor (Subscribers.Completion<Failure>) -> Void) -> AnyCancellable {
            switch result {
            case .success(let output):
                receive(output)
                complete(.finished)
            case .failure(let error):
                complete(.failure(error))
            }
            return AnyCancellable {}
        }
    }
}
#endif

// MARK: - Subjects

/// A publisher that exposes a method for outside callers to publish elements.
public protocol Subject: AnyObject, Publisher {
    func send(_ value: Output)
    func send(completion: Subscribers.Completion<Failure>)
    /// Gives the subject the subscription to an upstream publisher it was attached to
    /// (`Publisher.subscribe(_:)` with a subject); the subject asks it for values.
    func send(subscription: any Subscription)
}

extension Subject {
    /// Asks for every value, as Combine's subjects do.
    public func send(subscription: any Subscription) {
        subscription.request(.unlimited)
    }
}

/// The subscribers of a subject: closures kept until cancelled or the subject completes.
final class _Subscribers<Output, Failure: Error>: @unchecked Sendable {
    private var entries: [Int: (receive: @MainActor (Output) -> Void, complete: @MainActor (Subscribers.Completion<Failure>) -> Void)] = [:]
    private var nextID = 0
    private(set) var completion: Subscribers.Completion<Failure>?

    @MainActor func add(_ receive: @escaping @MainActor (Output) -> Void,
                        _ complete: @escaping @MainActor (Subscribers.Completion<Failure>) -> Void) -> AnyCancellable {
        if let completion {
            complete(completion)
            return AnyCancellable {}
        }
        nextID += 1
        let id = nextID
        entries[id] = (receive, complete)
        return AnyCancellable { [weak self] in MainActor.assumeIsolated { self?.entries[id] = nil } }
    }

    /// Sends on the main actor, where state changes (Combine's `send` is nonisolated; a value
    /// crosses to the subscribers' closures as it would through a subject).
    func send(_ value: Output) {
        guard completion == nil else { return }
        let current = Array(entries.values)
        nonisolated(unsafe) let value = value
        MainActor.assumeIsolated { for entry in current { entry.receive(value) } }
    }

    func send(completion: Subscribers.Completion<Failure>) {
        guard self.completion == nil else { return }
        self.completion = completion
        let current = Array(entries.values)
        entries.removeAll()
        nonisolated(unsafe) let completion = completion
        MainActor.assumeIsolated { for entry in current { entry.complete(completion) } }
    }
}

/// A subject that broadcasts the values it is sent.
public final class PassthroughSubject<Output, Failure: Error>: Subject, @unchecked Sendable {
    private let subscribers = _Subscribers<Output, Failure>()
    public init() {}

    /// Sends a value to every subscriber (on the main actor, where state changes).
    public func send(_ value: Output) { subscribers.send(value) }
    public func send(completion: Subscribers.Completion<Failure>) { subscribers.send(completion: completion) }

    @MainActor public func _subscribe(_ receive: @escaping @MainActor (Output) -> Void,
                                      _ complete: @escaping @MainActor (Subscribers.Completion<Failure>) -> Void) -> AnyCancellable {
        subscribers.add(receive, complete)
    }
}

extension PassthroughSubject: _SubjectDemand {
    var _keepsLatestWithoutDemand: Bool { false }
}

extension PassthroughSubject where Output == Void {
    public func send() { send(()) }
}

/// A subject that holds a value, delivering it to new subscribers and every change after.
public final class CurrentValueSubject<Output, Failure: Error>: Subject, @unchecked Sendable {
    private let subscribers = _Subscribers<Output, Failure>()
    public var value: Output {
        didSet { subscribers.send(value) }
    }
    public init(_ value: Output) { self.value = value }
    public func send(_ value: Output) { self.value = value }
    public func send(completion: Subscribers.Completion<Failure>) { subscribers.send(completion: completion) }

    @MainActor public func _subscribe(_ receive: @escaping @MainActor (Output) -> Void,
                                      _ complete: @escaping @MainActor (Subscribers.Completion<Failure>) -> Void) -> AnyCancellable {
        if subscribers.completion == nil { receive(value) }
        return subscribers.add(receive, complete)
    }
}

extension CurrentValueSubject: _SubjectDemand {
    var _keepsLatestWithoutDemand: Bool { true }
}

// MARK: - Objects and published properties

extension ObservableObjectPublisher: Publisher {
    public typealias Output = Void
    public typealias Failure = Never
    @MainActor public func _subscribe(_ receive: @escaping @MainActor (Output) -> Void,
                                      _ complete: @escaping @MainActor (Subscribers.Completion<Never>) -> Void) -> AnyCancellable {
        subscribe { receive(()) }
    }
}

extension Published.Publisher: Publisher {
    public typealias Output = Value
    public typealias Failure = Never
    /// The property's value after each change of its object (the current value first, when the
    /// object is known; `$property` from inside the object).
    @MainActor public func _subscribe(_ receive: @escaping @MainActor (Value) -> Void,
                                      _ complete: @escaping @MainActor (Subscribers.Completion<Never>) -> Void) -> AnyCancellable {
        guard let object = object as? any ObservableObject, let read = read else { return AnyCancellable {} }
        receive(read())
        return object.objectWillChange.subscribe { Task { @MainActor in receive(read()) } }
    }
}

// MARK: - Timer and notification publishers

/// `Timer.publish(every:tolerance:on:in:)`: a connectable publisher, as Combine's is. From
/// `connect()` (or `autoconnect()`'s first subscription) it delivers the date every interval to
/// its subscribers, through a task on the main actor, until the connection is cancelled.
/// (Not named `TimerPublisher`: Apple's Combine nests one under `Timer`.)
public final class _TimerPublisher: ConnectablePublisher, @unchecked Sendable {
    public typealias Output = Date
    public typealias Failure = Never
    public let interval: TimeInterval
    public let tolerance: TimeInterval?
    // The subscribers and the running task are touched from the main actor, where subscriptions
    // are made and the timer's task runs (`@unchecked`, as Autoconnect's counts are).
    private var receivers: [Int: @MainActor (Date) -> Void] = [:]
    private var nextReceiver = 0
    private var task: Task<Void, Never>?
    /// Counts the timer's starts, so a token from an earlier start leaves a later one running.
    private var generation = 0

    public init(interval: TimeInterval, tolerance: TimeInterval? = nil) {
        self.interval = interval
        self.tolerance = tolerance
    }

    @MainActor public func _subscribe(_ receive: @escaping @MainActor (Date) -> Void,
                                      _ complete: @escaping @MainActor (Subscribers.Completion<Never>) -> Void) -> AnyCancellable {
        let id = nextReceiver
        nextReceiver += 1
        receivers[id] = receive
        return AnyCancellable { [self] in receivers[id] = nil }
    }

    /// Starts the timer; cancelling the result stops it (a second call while it runs shares that
    /// run, and a token from a run already stopped does nothing).
    public func connect() -> any Cancellable {
        if task == nil {
            generation += 1
            let interval = max(self.interval, 0.001)
            task = Task { @MainActor [self] in
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                    guard !Task.isCancelled else { return }
                    let now = Date()
                    for receive in receivers.values { receive(now) }
                }
            }
        }
        let issued = generation
        return AnyCancellable { [self] in
            guard generation == issued, let running = task else { return }
            running.cancel()
            task = nil
        }
    }
}

extension Timer {
    /// A connectable publisher that repeatedly emits the current date on the interval once
    /// connected (the run loop and mode are accepted: the main actor delivers).
    public static func publish(every interval: TimeInterval, tolerance: TimeInterval? = nil, on runLoop: RunLoop = .main, in mode: RunLoop.Mode = .default,
                               options: Any? = nil) -> _TimerPublisher {
        _TimerPublisher(interval: interval, tolerance: tolerance)
    }
}

/// `NotificationCenter.publisher(for:object:)`: the notifications posted with the name (and
/// sender, when given).
public struct NotificationCenterPublisher: Publisher {
    public typealias Output = Notification
    public typealias Failure = Never
    public let center: NotificationCenter
    public let name: Notification.Name
    public let object: AnyObject?

    public init(center: NotificationCenter, name: Notification.Name, object: AnyObject? = nil) {
        self.center = center
        self.name = name
        self.object = object
    }

    @MainActor public func _subscribe(_ receive: @escaping @MainActor (Notification) -> Void,
                                      _ complete: @escaping @MainActor (Subscribers.Completion<Never>) -> Void) -> AnyCancellable {
        let token = center.addObserver(forName: name, object: object, queue: nil) { notification in
            // Foundation's `Notification` is not Sendable (the wasm stand-in is).
            #if os(WASI)
            MainActor.assumeIsolated { receive(notification) }
            #else
            nonisolated(unsafe) let notification = notification
            MainActor.assumeIsolated { receive(notification) }
            #endif
        }
        let center = self.center
        nonisolated(unsafe) let held = token
        return AnyCancellable { center.removeObserver(held) }
    }
}

extension NotificationCenter {
    public func publisher(for name: Notification.Name, object: AnyObject? = nil) -> NotificationCenterPublisher {
        NotificationCenterPublisher(center: self, name: name, object: object)
    }
}

#if !(canImport(Darwin) && !os(WASI))
extension NotificationCenter {
    /// Combine's name for the publisher type, as apps spell it in a stored property or a return
    /// type (Clendar's `AppEvents`: `NotificationCenter.Publisher`). Apple's Foundation declares it
    /// itself, so this is only where Foundation is the stand-in.
    public typealias Publisher = NotificationCenterPublisher
}
#endif
