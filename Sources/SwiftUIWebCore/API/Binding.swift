/// A property wrapper type that can read and write a value owned by a source of truth.
@propertyWrapper
@dynamicMemberLookup
@frozen
public struct Binding<Value> {
    /// The binding's transaction.
    public var transaction: Transaction

    @usableFromInline
    package let getter: () -> Value

    @usableFromInline
    package let setter: (Value, Transaction) -> Void

    /// Creates a binding with closures that read and write the binding value.
    public init(get: @escaping () -> Value, set: @escaping (Value) -> Void) {
        transaction = Transaction()
        getter = get
        setter = { value, _ in set(value) }
    }

    /// Creates a binding with a closure that reads from the binding value, and a closure that
    /// applies a transaction when writing to the binding value.
    public init(get: @escaping () -> Value, set: @escaping (Value, Transaction) -> Void) {
        transaction = Transaction()
        getter = get
        setter = set
    }

    /// Creates a binding from the value of another binding.
    public init(projectedValue: Binding<Value>) {
        self = projectedValue
    }

    /// Creates a binding with an immutable value.
    public static func constant(_ value: Value) -> Binding<Value> {
        Binding(get: { value }, set: { _ in })
    }

    /// The underlying value referenced by the binding variable.
    public var wrappedValue: Value {
        get { getter() }
        nonmutating set { setter(newValue, transaction) }
    }

    /// A projection of the binding value that returns a binding.
    public var projectedValue: Binding<Value> { self }

    /// Returns a binding to the resulting value of a given key path.
    public subscript<Subject>(dynamicMember keyPath: WritableKeyPath<Value, Subject>) -> Binding<Subject> {
        var binding = Binding<Subject>(
            get: { self.wrappedValue[keyPath: keyPath] },
            set: { newValue, transaction in
                var value = self.getter()
                value[keyPath: keyPath] = newValue
                self.setter(value, transaction)
            })
        binding.transaction = transaction
        return binding
    }

    /// Specifies a transaction for the binding.
    public func transaction(_ transaction: Transaction) -> Binding<Value> {
        var copy = self
        copy.transaction = transaction
        return copy
    }
}

extension Binding: DynamicProperty {
    @MainActor
    public mutating func _install(in node: ViewNode, slot: inout AnyObject?) {}
}

extension Binding {
    /// Creates a binding by projecting the base value to an optional value.
    public init<V>(_ base: Binding<V>) where Value == V? {
        self.init(get: { base.wrappedValue }, set: { newValue, transaction in
            if let newValue { base.setter(newValue, transaction) }
        })
        transaction = base.transaction
    }

    /// Creates a binding by projecting the base value to an unwrapped value.
    public init?(_ base: Binding<Value?>) {
        guard let initial = base.wrappedValue else { return nil }
        self.init(get: { base.wrappedValue ?? initial }, set: { newValue, transaction in
            base.setter(newValue, transaction)
        })
        transaction = base.transaction
    }

    /// Creates a binding by projecting the base value to a hashable value.
    public init<V: Hashable>(_ base: Binding<V>) where Value == AnyHashable {
        self.init(get: { AnyHashable(base.wrappedValue) }, set: { newValue, transaction in
            base.setter(newValue.base as! V, transaction)
        })
        transaction = base.transaction
    }
}

extension Binding: Identifiable where Value: Identifiable {
    public var id: Value.ID { wrappedValue.id }
}

extension Binding: Sequence where Value: MutableCollection {
    public typealias Element = Binding<Value.Element>
    public typealias Iterator = IndexingIterator<Binding<Value>>
    public typealias SubSequence = Slice<Binding<Value>>
}

extension Binding: Collection where Value: MutableCollection {
    public typealias Index = Value.Index
    public typealias Indices = Value.Indices

    public var startIndex: Value.Index { wrappedValue.startIndex }
    public var endIndex: Value.Index { wrappedValue.endIndex }
    public var indices: Value.Indices { wrappedValue.indices }

    public func index(after i: Value.Index) -> Value.Index { wrappedValue.index(after: i) }

    public subscript(position: Value.Index) -> Binding<Value.Element> {
        Binding<Value.Element>(
            get: { self.wrappedValue[position] },
            set: { newValue, transaction in
                var value = self.getter()
                value[position] = newValue
                self.setter(value, transaction)
            })
    }
}

extension Binding: BidirectionalCollection where Value: BidirectionalCollection, Value: MutableCollection {
    public func index(before i: Value.Index) -> Value.Index { wrappedValue.index(before: i) }
}

extension Binding: RandomAccessCollection where Value: RandomAccessCollection, Value: MutableCollection {}
