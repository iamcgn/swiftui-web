// The Combine-free `ObservableObject` family (`Docs/elements/ObservableObject.md`, decision
// 0021): objects publish through an `ObservableObjectPublisher`, `@Published` setters send
// before assigning, and SwiftUI's `@StateObject`/`@ObservedObject`/`@EnvironmentObject`
// wrappers subscribe the view's node so a change invalidates it. On wasm `import Combine`
// (Packages/Shadows) is this module.

/// A type of object with a publisher that emits before the object has changed.
public protocol ObservableObject: AnyObject {
    associatedtype ObjectWillChangePublisher = ObservableObjectPublisher
    /// A publisher that emits before the object has changed.
    var objectWillChange: ObservableObjectPublisher { get }
}

/// A publisher that publishes changes from observable objects: subscribers are closures.
public final class ObservableObjectPublisher: @unchecked Sendable {
    private var subscribers: [Int: @MainActor () -> Void] = [:]
    private var nextID = 0

    public init() {}

    /// Sends a change notification to every subscriber (on the main actor, where state changes).
    public func send() {
        let current = Array(subscribers.values)
        MainActor.assumeIsolated { for subscriber in current { subscriber() } }
    }

    /// Subscribes a closure; the returned cancellable removes it.
    @MainActor public func subscribe(_ subscriber: @escaping @MainActor () -> Void) -> AnyCancellable {
        nextID += 1
        let id = nextID
        subscribers[id] = subscriber
        return AnyCancellable { [weak self] in
            MainActor.assumeIsolated { self?.subscribers[id] = nil }
        }
    }
}

/// A cancellable that runs a closure when cancelled or deallocated.
public final class AnyCancellable: Hashable, @unchecked Sendable {
    private var cancelClosure: (() -> Void)?

    public init(_ cancel: @escaping () -> Void) { cancelClosure = cancel }
    deinit { cancel() }

    public func cancel() {
        cancelClosure?()
        cancelClosure = nil
    }

    /// Stores this cancellable in a set.
    public func store(in set: inout Set<AnyCancellable>) { set.insert(self) }
    public func store(in array: inout [AnyCancellable]) { array.append(self) }

    public static func == (lhs: AnyCancellable, rhs: AnyCancellable) -> Bool { lhs === rhs }
    public func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(self)) }
}

/// Publishers of objects that do not declare their own, kept by object identity.
@MainActor
private var objectPublishers: [ObjectIdentifier: (object: WeakObject, publisher: ObservableObjectPublisher)] = [:]

private struct WeakObject {
    weak var object: AnyObject?
}

extension ObservableObject {
    /// The default publisher: one per object, created on first access.
    public var objectWillChange: ObservableObjectPublisher {
        nonisolated(unsafe) let object = self
        return MainActor.assumeIsolated {
            let key = ObjectIdentifier(object)
            if let entry = objectPublishers[key], entry.object.object === object { return entry.publisher }
            if objectPublishers.count > 64 { objectPublishers = objectPublishers.filter { $0.value.object.object != nil } }
            let publisher = ObservableObjectPublisher()
            objectPublishers[key] = (WeakObject(object: object), publisher)
            return publisher
        }
    }
}

// MARK: - Published

/// A type that publishes a property marked with an attribute: setting the wrapped value sends
/// the enclosing object's `objectWillChange` before the assignment.
@propertyWrapper
public struct Published<Value> {
    private var stored: Value

    public init(wrappedValue: Value) { stored = wrappedValue }
    public init(initialValue: Value) { stored = initialValue }

    /// Only accessible through the enclosing-instance subscript; the property is always inside an object.
    @available(*, unavailable, message: "@Published is only available on properties of classes")
    public var wrappedValue: Value {
        get { fatalError() }
        set { fatalError() }
    }

    /// The property's publisher (`$property`): the enclosing object's `objectWillChange` for now.
    public struct Publisher {
        package let object: AnyObject?
        /// Reads the property's current value (set when the object is known).
        package var read: (() -> Value)?
        package init(object: AnyObject?, read: (() -> Value)? = nil) {
            self.object = object
            self.read = read
        }
    }

    public var projectedValue: Publisher {
        get { Publisher(object: nil) }
        set {}
    }

    public static subscript<EnclosingSelf: ObservableObject>(
        _enclosingInstance object: EnclosingSelf,
        wrapped wrappedKeyPath: ReferenceWritableKeyPath<EnclosingSelf, Value>,
        storage storageKeyPath: ReferenceWritableKeyPath<EnclosingSelf, Published<Value>>
    ) -> Value {
        get { object[keyPath: storageKeyPath].stored }
        set {
            nonisolated(unsafe) let target = object
            MainActor.assumeIsolated { target.objectWillChange.send() }
            object[keyPath: storageKeyPath].stored = newValue
        }
    }

    public static subscript<EnclosingSelf: ObservableObject>(
        _enclosingInstance object: EnclosingSelf,
        projected projectedKeyPath: ReferenceWritableKeyPath<EnclosingSelf, Publisher>,
        storage storageKeyPath: ReferenceWritableKeyPath<EnclosingSelf, Published<Value>>
    ) -> Publisher {
        get {
            nonisolated(unsafe) let object = object
            return Publisher(object: object, read: { object[keyPath: storageKeyPath].stored })
        }
        set {}
    }
}

