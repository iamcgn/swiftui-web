import Observation

/// A property wrapper type that supports creating bindings to the mutable properties of
/// observable objects.
@propertyWrapper
@dynamicMemberLookup
public struct Bindable<Value> {
    /// The wrapped object.
    public var wrappedValue: Value

    /// The bindable wrapper for the object that creates bindings to its properties using
    /// dynamic member lookup.
    public var projectedValue: Bindable<Value> { self }

    /// Creates a bindable object from an observable object.
    public init(wrappedValue: Value) {
        self.wrappedValue = wrappedValue
    }

    /// Creates a bindable object from an observable object.
    public init(_ wrappedValue: Value) {
        self.wrappedValue = wrappedValue
    }

    /// Creates a bindable from the value of another bindable.
    public init(projectedValue: Bindable<Value>) {
        self = projectedValue
    }
}

extension Bindable where Value: AnyObject {
    /// Returns a binding to the value of a given key path.
    public subscript<Subject>(dynamicMember keyPath: ReferenceWritableKeyPath<Value, Subject>) -> Binding<Subject> {
        let object = wrappedValue
        return Binding(get: { object[keyPath: keyPath] }, set: { object[keyPath: keyPath] = $0 })
    }
}

extension Bindable: Identifiable where Value: Identifiable {
    public var id: Value.ID { wrappedValue.id }
}

extension Bindable: Sendable where Value: Sendable {}
