// Focused values (Docs/elements/Focus.md): `focusedValue` publishes a value from the focused
// view's subtree, `focusedSceneValue` from anywhere; `@FocusedValue` and `@FocusedBinding`
// read them, following keyboard focus.

/// A protocol for identifier types used when publishing and observing focused values.
public protocol FocusedValueKey {
    associatedtype Value
}

/// A collection of state exported by the focused view and its ancestors.
public struct FocusedValues {
    package var values: [ObjectIdentifier: Any] = [:]

    public init() {}

    public subscript<K: FocusedValueKey>(key: K.Type) -> K.Value? {
        get { values[ObjectIdentifier(key)] as? K.Value }
        set { values[ObjectIdentifier(key)] = newValue }
    }
}

/// A property wrapper for observing values from the focused view or one of its ancestors.
@propertyWrapper
public struct FocusedValue<Value>: DynamicProperty {
    package let keyPath: KeyPath<FocusedValues, Value?>
    package var resolved: Value?

    public init(_ keyPath: KeyPath<FocusedValues, Value?>) {
        self.keyPath = keyPath
    }

    public var wrappedValue: Value? { resolved }

    @MainActor public mutating func _install(in node: ViewNode, slot: inout AnyObject?) {
        node.runtime.registerFocusedValueObserver(node)
        resolved = node.runtime.focusedValues[keyPath: keyPath]
    }
}

/// A convenience wrapper for a focused `Binding`: reads and writes the bound value.
@propertyWrapper
public struct FocusedBinding<Value>: DynamicProperty {
    package let keyPath: KeyPath<FocusedValues, Binding<Value>?>
    package var binding: Binding<Value>?

    public init(_ keyPath: KeyPath<FocusedValues, Binding<Value>?>) {
        self.keyPath = keyPath
    }

    public var wrappedValue: Value? {
        get { binding?.wrappedValue }
        nonmutating set { if let newValue { binding?.wrappedValue = newValue } }
    }

    /// A binding to the optional value (nil while nothing is focused).
    public var projectedValue: Binding<Value?> {
        let binding = binding
        return Binding(get: { binding?.wrappedValue }, set: { if let value = $0 { binding?.wrappedValue = value } })
    }

    @MainActor public mutating func _install(in node: ViewNode, slot: inout AnyObject?) {
        node.runtime.registerFocusedValueObserver(node)
        binding = node.runtime.focusedValues[keyPath: keyPath]
    }
}

/// `focusedValue` and `focusedSceneValue`: a writer the runtime applies while composing the
/// focused values (a class so the runtime's field reflection ignores it).
public final class _FocusedValueWriter {
    package let write: (inout FocusedValues) -> Void
    package init(_ write: @escaping (inout FocusedValues) -> Void) { self.write = write }
}

public struct _FocusedValueModifier {
    package let writer: _FocusedValueWriter
    /// Scene values apply whatever has focus; view values only when focus is in the subtree.
    package let scene: Bool
    package init(writer: _FocusedValueWriter, scene: Bool) {
        self.writer = writer
        self.scene = scene
    }
}

extension _FocusedValueModifier: ViewModifier {
    public typealias Body = Never
    public static func _makeNode<Content: View>(_ context: _NodeContext<ModifiedContent<Content, Self>>) -> TypedNode<ModifiedContent<Content, Self>> {
        FocusedValueNode(context)
    }
}

extension View {
    /// Modifies this view by injecting a value that you provide for use by other views whose
    /// state depends on the focused view hierarchy.
    nonisolated public func focusedValue<T>(_ keyPath: WritableKeyPath<FocusedValues, T?>, _ value: T) -> some View {
        modifier(_FocusedValueModifier(writer: _FocusedValueWriter { $0[keyPath: keyPath] = value }, scene: false))
    }

    /// Sets the focused value for the key path to an optional value: nil clears it.
    nonisolated public func focusedValue<T>(_ keyPath: WritableKeyPath<FocusedValues, T?>, _ value: T?) -> some View {
        modifier(_FocusedValueModifier(writer: _FocusedValueWriter { $0[keyPath: keyPath] = value }, scene: false))
    }

    /// Modifies this view by injecting a value that applies while the scene is focused, whatever
    /// view has focus.
    nonisolated public func focusedSceneValue<T>(_ keyPath: WritableKeyPath<FocusedValues, T?>, _ value: T) -> some View {
        modifier(_FocusedValueModifier(writer: _FocusedValueWriter { $0[keyPath: keyPath] = value }, scene: true))
    }

    nonisolated public func focusedSceneValue<T>(_ keyPath: WritableKeyPath<FocusedValues, T?>, _ value: T?) -> some View {
        modifier(_FocusedValueModifier(writer: _FocusedValueWriter { $0[keyPath: keyPath] = value }, scene: true))
    }
}
