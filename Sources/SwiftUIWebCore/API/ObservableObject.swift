/// The Combine-free `ObservableObject` family (`Docs/elements/ObservableObject.md`): objects
/// publish through an `ObservableObjectPublisher`, `@Published` setters send before assigning,
/// and the `@StateObject`/`@ObservedObject`/`@EnvironmentObject` wrappers subscribe the view's
/// node so a change invalidates it.

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

    /// Runs `receiveValue` on every change (the Combine-style spelling).
    @MainActor public func sink(receiveValue: @escaping @MainActor () -> Void) -> AnyCancellable { subscribe(receiveValue) }
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
        @MainActor public func sink(receiveValue: @escaping @MainActor () -> Void) -> AnyCancellable {
            (object as? any ObservableObject)?.objectWillChange.subscribe(receiveValue) ?? AnyCancellable {}
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
        get { Publisher(object: object) }
        set {}
    }
}

// MARK: - Subscriptions kept by nodes

/// A node's subscription to an object's publisher: invalidates the node on every change.
@MainActor
package final class _ObjectSubscription {
    package private(set) var objectID: ObjectIdentifier?
    private var cancellable: AnyCancellable?

    package init() {}

    package func observe(_ object: any ObservableObject, from node: ViewNode) {
        let id = ObjectIdentifier(object)
        guard id != objectID else { return }
        cancellable?.cancel()
        objectID = id
        cancellable = object.objectWillChange.subscribe { [weak node] in node?.invalidate() }
    }
}

/// A binding-producing wrapper for an observed object's properties (`$model.property`).
@dynamicMemberLookup
public struct _ObservedObjectWrapper<ObjectType: ObservableObject> {
    package let object: ObjectType

    public subscript<Subject>(dynamicMember keyPath: ReferenceWritableKeyPath<ObjectType, Subject>) -> Binding<Subject> {
        let object = self.object
        return Binding(get: { object[keyPath: keyPath] }, set: { object[keyPath: keyPath] = $0 })
    }
}

// MARK: - StateObject

/// A property wrapper that instantiates an observable object once per view identity.
@propertyWrapper
public struct StateObject<ObjectType: ObservableObject>: DynamicProperty {
    package let make: () -> ObjectType
    package var box: _StateObjectBox<ObjectType>?

    /// Creates a new state object with an initial wrapped value.
    public init(wrappedValue thunk: @autoclosure @escaping () -> ObjectType) {
        make = thunk
    }

    /// The underlying value referenced by the state object.
    public var wrappedValue: ObjectType { box?.object ?? make() }

    /// A projection of the state object that creates bindings to its properties.
    public var projectedValue: _ObservedObjectWrapper<ObjectType> { _ObservedObjectWrapper(object: wrappedValue) }

    @MainActor
    public mutating func _install(in node: ViewNode, slot: inout AnyObject?) {
        if let existing = slot as? _StateObjectBox<ObjectType> {
            box = existing
        } else {
            let created = _StateObjectBox(object: make())
            slot = created
            box = created
        }
        box?.subscription.observe(box!.object, from: node)
    }
}

package final class _StateObjectBox<ObjectType: ObservableObject> {
    package let object: ObjectType
    package let subscription: _ObjectSubscription
    @MainActor package init(object: ObjectType) {
        self.object = object
        subscription = _ObjectSubscription()
    }
}

// MARK: - ObservedObject

/// A property wrapper that subscribes to an observable object and invalidates a view when the
/// observable object changes.
@propertyWrapper
public struct ObservedObject<ObjectType: ObservableObject>: DynamicProperty {
    /// The underlying value referenced by the observed object.
    public var wrappedValue: ObjectType

    public init(wrappedValue: ObjectType) { self.wrappedValue = wrappedValue }
    public init(initialValue: ObjectType) { self.wrappedValue = initialValue }

    /// A projection of the observed object that creates bindings to its properties.
    public var projectedValue: _ObservedObjectWrapper<ObjectType> { _ObservedObjectWrapper(object: wrappedValue) }

    @MainActor
    public mutating func _install(in node: ViewNode, slot: inout AnyObject?) {
        let subscription = (slot as? _ObjectSubscription) ?? _ObjectSubscription()
        slot = subscription
        subscription.observe(wrappedValue, from: node)
    }
}

extension ObservedObject {
    /// The wrapper type Apple exposes for `$object`.
    public typealias Wrapper = _ObservedObjectWrapper<ObjectType>
}

// MARK: - EnvironmentObject

/// A property wrapper that reads an observable object supplied by an ancestor with
/// `environmentObject(_:)` and invalidates the view when it changes.
@propertyWrapper
public struct EnvironmentObject<ObjectType: ObservableObject>: DynamicProperty {
    package var object: ObjectType?

    public init() {}

    /// The underlying value referenced by the environment object.
    public var wrappedValue: ObjectType {
        guard let object else {
            fatalError("No ObservableObject of type \(ObjectType.self) found. A View.environmentObject(_:) for \(ObjectType.self) may be missing as an ancestor of this view.")
        }
        return object
    }

    /// A projection that creates bindings to the environment object's properties.
    public var projectedValue: _ObservedObjectWrapper<ObjectType> { _ObservedObjectWrapper(object: wrappedValue) }

    @MainActor
    public mutating func _install(in node: ViewNode, slot: inout AnyObject?) {
        object = node.environment._observableObject(ObjectType.self)
        guard let object else { return }
        let subscription = (slot as? _ObjectSubscription) ?? _ObjectSubscription()
        slot = subscription
        subscription.observe(object, from: node)
    }
}

extension EnvironmentValues {
    package func _observableObject<T: ObservableObject>(_ type: T.Type) -> T? {
        values[ObjectIdentifier(type)] as? T
    }

    package mutating func _setObservableObject<T: ObservableObject>(_ object: T) {
        values[ObjectIdentifier(T.self)] = object
        didMutate()
    }
}

/// Stores an observable object in the environment. Produced by `View.environmentObject(_:)`.
public struct _EnvironmentObjectModifier<T: ObservableObject> {
    package let object: T
    package init(object: T) { self.object = object }
}

extension _EnvironmentObjectModifier: ViewModifier, _EnvironmentModifier {
    public typealias Body = Never

    package func modifyEnvironment(_ values: inout EnvironmentValues) {
        values._setObservableObject(object)
    }

    @MainActor
    public static func _makeNode<Content: View>(_ context: _NodeContext<ModifiedContent<Content, Self>>) -> TypedNode<ModifiedContent<Content, Self>> {
        EnvironmentModifierNode(context)
    }
}

extension View {
    /// Supplies an observable object to a view's hierarchy.
    nonisolated public func environmentObject<T: ObservableObject>(_ object: T) -> some View {
        modifier(_EnvironmentObjectModifier(object: object))
    }
}
