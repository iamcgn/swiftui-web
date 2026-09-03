import Observation

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

    /// Identity of this set of values: two `EnvironmentValues` with the same generation are
    /// copies of one another with no mutation in between, so nodes can skip re-evaluation.
    package private(set) var generation: UInt64 = 0

    /// Creates an environment values instance.
    public init() {}

    package mutating func didMutate() {
        generation = _EnvironmentGeneration.next()
    }

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
            didMutate()
        }
    }

    public var description: String {
        "EnvironmentValues(\(values.count) keys)"
    }

    /// Reads an observable object of the given type from the environment, or `nil` if none was
    /// stored with `View.environment(_:)`.
    public subscript<T: AnyObject & Observable>(objectType: T.Type) -> T? {
        get { values[ObjectIdentifier(objectType)] as? T }
        set {
            values[ObjectIdentifier(objectType)] = newValue
            didMutate()
        }
    }
}

package enum _EnvironmentGeneration {
    nonisolated(unsafe) private static var counter: UInt64 = 0

    /// Environment values are only mutated on the main actor (view bodies, modifiers).
    package static func next() -> UInt64 {
        counter += 1
        return counter
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
        case lookup((EnvironmentValues) -> Value)
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
        case .lookup(let lookup):
            return lookup(EnvironmentValues())
        }
    }

    /// Resolves the property against `values`. Called by the runtime when a view's body is about
    /// to be evaluated.
    package mutating func resolve(in values: EnvironmentValues) {
        switch content {
        case .keyPath(let keyPath):
            content = .value(values[keyPath: keyPath])
        case .lookup(let lookup):
            content = .value(lookup(values))
        case .value:
            break
        }
    }

    @MainActor
    public mutating func _install(in node: ViewNode, slot: inout AnyObject?) {
        resolve(in: node.environment)
    }
}

extension Environment where Value: AnyObject & Observable {
    /// Creates an environment property to read an observable object from the environment.
    /// Reading it when no object of that type was stored is a programmer error, as in SwiftUI.
    public init(_ objectType: Value.Type) {
        content = .lookup { values in
            guard let object = values[objectType] else {
                fatalError("No Observable object of type \(objectType) found. A View.environment(_:) for \(objectType) may be missing as an ancestor of this view.")
            }
            return object
        }
    }
}

extension Environment {
    /// Creates an environment property to read an observable object from the environment,
    /// returning `nil` if no corresponding object has been set.
    public init<T: AnyObject & Observable>(_ objectType: T.Type) where Value == T? {
        content = .lookup { $0[objectType] }
    }
}

/// Stores an observable object in the environment. Produced by `View.environment(_:)`.
public struct _EnvironmentObjectWritingModifier<T: AnyObject & Observable> {
    public var object: T?

    public init(object: T?) {
        self.object = object
    }
}

extension _EnvironmentObjectWritingModifier: ViewModifier, _EnvironmentModifier {
    public typealias Body = Never

    package func modifyEnvironment(_ values: inout EnvironmentValues) {
        values[T.self] = object
    }

    @MainActor
    public static func _makeNode<Content: View>(
        _ context: _NodeContext<ModifiedContent<Content, Self>>
    ) -> TypedNode<ModifiedContent<Content, Self>> {
        EnvironmentModifierNode(context)
    }
}

extension View {
    /// Places an observable object in the view's environment.
    nonisolated public func environment<T: AnyObject & Observable>(_ object: T?) -> some View {
        modifier(_EnvironmentObjectWritingModifier(object: object))
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
    nonisolated public func environment<V>(
        _ keyPath: WritableKeyPath<EnvironmentValues, V>,
        _ value: V
    ) -> some View {
        modifier(_EnvironmentKeyWritingModifier(keyPath: keyPath, value: value))
    }

    /// Transforms the environment value of the specified key path with the given function.
    @inlinable
    nonisolated public func transformEnvironment<V>(
        _ keyPath: WritableKeyPath<EnvironmentValues, V>,
        transform: @escaping (inout V) -> Void
    ) -> some View {
        modifier(_EnvironmentKeyTransformModifier(keyPath: keyPath, transform: transform))
    }
}
