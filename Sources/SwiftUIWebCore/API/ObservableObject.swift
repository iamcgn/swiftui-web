/// SwiftUI's `ObservableObject` wrappers over WebCombine's family (`Docs/elements/ObservableObject.md`):
/// `@StateObject`, `@ObservedObject` and `@EnvironmentObject` subscribe the view's node so a
/// change invalidates it.
import WebCombine

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
