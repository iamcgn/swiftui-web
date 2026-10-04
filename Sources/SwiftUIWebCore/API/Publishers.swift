// Combine-free publishers (Docs/elements/Lifecycle.md, Docs/elements/ObservableObject.md):
// enough of Combine's surface for `onReceive`: `Just`, the subjects, `Timer.publish` and
// `NotificationCenter.publisher`, plus `objectWillChange` and `$published` values. A publisher
// delivers through a closure subscription returning an `AnyCancellable`.
#if os(WASI)
import WebFoundation
#else
import Foundation
#endif

/// A type that delivers values to subscribers.
public protocol Publisher<Output, Failure> {
    associatedtype Output
    associatedtype Failure: Error
    /// Subscribes `receive` to the values; cancelling the result ends the subscription.
    @MainActor func _subscribe(_ receive: @escaping @MainActor (Output) -> Void) -> AnyCancellable
}

extension Publisher {
    /// Attaches a subscriber with closure-based behaviour.
    @MainActor public func sink(receiveValue: @escaping @MainActor (Output) -> Void) -> AnyCancellable { _subscribe(receiveValue) }

    /// Connectable publishers connect on their first subscription here; the publisher itself.
    public func autoconnect() -> Self { self }

    /// The values delivered on the main actor (every delivery already is).
    public func receive(on scheduler: Any, options: Any? = nil) -> Self { self }
}

/// A publisher that emits one value on subscription.
public struct Just<Output>: Publisher {
    public typealias Failure = Never
    public let output: Output
    public init(_ output: Output) { self.output = output }
    @MainActor public func _subscribe(_ receive: @escaping @MainActor (Output) -> Void) -> AnyCancellable {
        receive(output)
        return AnyCancellable {}
    }
}

/// A subject that broadcasts the values it is sent.
public final class PassthroughSubject<Output, Failure: Error>: Publisher, @unchecked Sendable {
    private var subscribers: [Int: @MainActor (Output) -> Void] = [:]
    private var nextID = 0
    public init() {}

    @MainActor public func send(_ value: Output) {
        for subscriber in Array(subscribers.values) { subscriber(value) }
    }

    @MainActor public func _subscribe(_ receive: @escaping @MainActor (Output) -> Void) -> AnyCancellable {
        nextID += 1
        let id = nextID
        subscribers[id] = receive
        return AnyCancellable { [weak self] in MainActor.assumeIsolated { self?.subscribers[id] = nil } }
    }
}

extension PassthroughSubject where Output == Void {
    @MainActor public func send() { send(()) }
}

/// A subject that holds a value, delivering it to new subscribers and every change after.
public final class CurrentValueSubject<Output, Failure: Error>: Publisher, @unchecked Sendable {
    private let subject = PassthroughSubject<Output, Failure>()
    public var value: Output {
        didSet { MainActor.assumeIsolated { subject.send(value) } }
    }
    public init(_ value: Output) { self.value = value }
    @MainActor public func send(_ value: Output) { self.value = value }
    @MainActor public func _subscribe(_ receive: @escaping @MainActor (Output) -> Void) -> AnyCancellable {
        receive(value)
        return subject._subscribe(receive)
    }
}

extension ObservableObjectPublisher: Publisher {
    public typealias Output = Void
    public typealias Failure = Never
    @MainActor public func _subscribe(_ receive: @escaping @MainActor (Output) -> Void) -> AnyCancellable {
        subscribe { receive(()) }
    }
}

extension Published.Publisher: Publisher {
    public typealias Output = Value
    public typealias Failure = Never
    /// The property's value after each change of its object (the current value first, when the
    /// object is known; `$property` from inside the object).
    @MainActor public func _subscribe(_ receive: @escaping @MainActor (Value) -> Void) -> AnyCancellable {
        guard let object = object as? any ObservableObject, let read = read else { return AnyCancellable {} }
        receive(read())
        return object.objectWillChange.subscribe { Task { @MainActor in receive(read()) } }
    }
}

// MARK: - Timer and notification publishers

/// `Timer.publish(every:tolerance:on:in:)`: delivers the date every interval through a task on
/// the main actor, from the first subscription (connectable publishers connect on subscription).
/// (Not named `TimerPublisher`: Apple's Combine nests one under `Timer`.)
public struct _TimerPublisher: Publisher {
    public typealias Output = Date
    public typealias Failure = Never
    public let interval: TimeInterval
    package init(interval: TimeInterval) { self.interval = interval }

    @MainActor public func _subscribe(_ receive: @escaping @MainActor (Date) -> Void) -> AnyCancellable {
        let interval = max(self.interval, 0.001)
        let task = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                guard !Task.isCancelled else { return }
                receive(Date())
            }
        }
        return AnyCancellable { task.cancel() }
    }
}

extension Timer {
    /// A publisher that repeatedly emits the current date on the interval (the run loop and
    /// mode are accepted: the main actor delivers).
    public static func publish(every interval: TimeInterval, tolerance: TimeInterval? = nil, on runLoop: RunLoop = .main, in mode: RunLoop.Mode = .default,
                               options: Any? = nil) -> _TimerPublisher {
        _TimerPublisher(interval: interval)
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

    @MainActor public func _subscribe(_ receive: @escaping @MainActor (Notification) -> Void) -> AnyCancellable {
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

// MARK: - onReceive

/// `onReceive`: the action runs with every value the publisher delivers while the view is mounted.
public struct _OnReceiveModifier {
    /// Subscribes the action (called on the main actor, where the node mounts).
    package let subscribe: () -> AnyCancellable
    package init(subscribe: @escaping () -> AnyCancellable) { self.subscribe = subscribe }
}

extension _OnReceiveModifier: ViewModifier {
    public typealias Body = Never
    public static func _makeNode<Content: View>(_ context: _NodeContext<ModifiedContent<Content, Self>>) -> TypedNode<ModifiedContent<Content, Self>> {
        OnReceiveNode(context)
    }
}

extension View {
    /// Adds an action to perform when this view detects data emitted by the given publisher.
    /// The subscription is made when the view appears and ends when it disappears.
    nonisolated public func onReceive<P: Publisher>(_ publisher: P, perform action: @escaping @MainActor (P.Output) -> Void) -> some View where P.Failure == Never {
        // The publisher is used on the main actor only (the node subscribes when it mounts).
        nonisolated(unsafe) let held = publisher
        return modifier(_OnReceiveModifier(subscribe: { MainActor.assumeIsolated { held._subscribe(action) } }))
    }
}
