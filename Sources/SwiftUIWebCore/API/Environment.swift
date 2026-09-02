/// A key for accessing values in the environment.
public protocol EnvironmentKey {
    /// The associated type representing the type of the environment key's value.
    associatedtype Value

    /// The default value for the environment key.
    static var defaultValue: Self.Value { get }
}

/// A collection of environment values propagated through a view hierarchy.
public struct EnvironmentValues: CustomStringConvertible {
    /// Stored values by key type. Absent keys resolve to `K.defaultValue`.
    package var values: [ObjectIdentifier: Any] = [:]

    /// Creates an environment values instance.
    public init() {}

    /// Accesses the environment value associated with a custom key.
    public subscript<K: EnvironmentKey>(key: K.Type) -> K.Value {
        get {
            if let stored = values[ObjectIdentifier(key)] {
                return stored as! K.Value
            }
            return K.defaultValue
        }
        set {
            values[ObjectIdentifier(key)] = newValue
        }
    }

    public var description: String {
        "EnvironmentValues(\(values.count) keys)"
    }
}

/// A property wrapper that reads a value from a view's environment.
///
/// The runtime resolves the key path against the environment of the view that declares the
/// property (Phase 1 steps 2–3). Before installation it reads the default `EnvironmentValues`.
@propertyWrapper
@frozen
public struct Environment<Value>: DynamicProperty {
    @usableFromInline
    package enum Content {
        case keyPath(KeyPath<EnvironmentValues, Value>)
        case value(Value)
    }

    @usableFromInline
    package var content: Content

    /// Creates an environment property to read the specified key path.
    @inlinable
    public init(_ keyPath: KeyPath<EnvironmentValues, Value>) {
        content = .keyPath(keyPath)
    }

    /// The current value of the environment property.
    @inlinable
    public var wrappedValue: Value {
        switch content {
        case .value(let value):
            return value
        case .keyPath(let keyPath):
            return EnvironmentValues()[keyPath: keyPath]
        }
    }

    /// Resolves the property against `values`. Called by the runtime when a view's body is about
    /// to be evaluated.
    package mutating func resolve(in values: EnvironmentValues) {
        if case .keyPath(let keyPath) = content {
            content = .value(values[keyPath: keyPath])
        }
    }
}

/// Modifiers that change the environment for their content. The runtime applies them when it
/// builds the environment of the modified subtree.
@MainActor
package protocol _EnvironmentModifier {
    func modifyEnvironment(_ values: inout EnvironmentValues)
}

/// Writes a single value into the environment. Produced by `View.environment(_:_:)`.
public struct _EnvironmentKeyWritingModifier<Value> {
    public var keyPath: WritableKeyPath<EnvironmentValues, Value>
    public var value: Value

    @inlinable
    public init(keyPath: WritableKeyPath<EnvironmentValues, Value>, value: Value) {
        self.keyPath = keyPath
        self.value = value
    }

}

extension _EnvironmentKeyWritingModifier: ViewModifier, _EnvironmentModifier {
    public typealias Body = Never

    package func modifyEnvironment(_ values: inout EnvironmentValues) {
        values[keyPath: keyPath] = value
    }
}

/// Transforms a single environment value in place. Produced by `View.transformEnvironment(_:transform:)`.
public struct _EnvironmentKeyTransformModifier<Value> {
    public var keyPath: WritableKeyPath<EnvironmentValues, Value>
    public var transform: (inout Value) -> Void

    @inlinable
    public init(keyPath: WritableKeyPath<EnvironmentValues, Value>, transform: @escaping (inout Value) -> Void) {
        self.keyPath = keyPath
        self.transform = transform
    }

}

extension _EnvironmentKeyTransformModifier: ViewModifier, _EnvironmentModifier {
    public typealias Body = Never

    package func modifyEnvironment(_ values: inout EnvironmentValues) {
        transform(&values[keyPath: keyPath])
    }
}

extension View {
    /// Sets the environment value of the specified key path to the given value.
    @inlinable
    public func environment<V>(
        _ keyPath: WritableKeyPath<EnvironmentValues, V>,
        _ value: V
    ) -> some View {
        modifier(_EnvironmentKeyWritingModifier(keyPath: keyPath, value: value))
    }

    /// Transforms the environment value of the specified key path with the given function.
    @inlinable
    public func transformEnvironment<V>(
        _ keyPath: WritableKeyPath<EnvironmentValues, V>,
        transform: @escaping (inout V) -> Void
    ) -> some View {
        modifier(_EnvironmentKeyTransformModifier(keyPath: keyPath, transform: transform))
    }
}
