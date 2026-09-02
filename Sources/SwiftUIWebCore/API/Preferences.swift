/// A named value produced by a view. Values flow up the tree; a container reduces the values of
/// its children with `reduce(value:nextValue:)`.
public protocol PreferenceKey {
    associatedtype Value

    /// The default value of the preference, used when no child writes it.
    static var defaultValue: Self.Value { get }

    /// Combines a sequence of the values written by sibling views.
    static func reduce(value: inout Self.Value, nextValue: () -> Self.Value)
}

extension PreferenceKey where Self.Value: ExpressibleByNilLiteral {
    public static var defaultValue: Self.Value { nil }
}

/// Sets a preference value on the content, replacing anything the content's subtree wrote.
public struct _PreferenceWritingModifier<Key: PreferenceKey> {
    public var value: Key.Value
    public init(value: Key.Value) { self.value = value }
}

extension _PreferenceWritingModifier: ViewModifier {
    public typealias Body = Never

    public static func _makeNode<Content: View>(_ context: _NodeContext<ModifiedContent<Content, Self>>) -> TypedNode<ModifiedContent<Content, Self>> {
        PreferenceWritingNode(context)
    }
}

/// Transforms the preference value of the content.
public struct _PreferenceTransformModifier<Key: PreferenceKey> {
    public var transform: (inout Key.Value) -> Void
    public init(transform: @escaping (inout Key.Value) -> Void) { self.transform = transform }
}

extension _PreferenceTransformModifier: ViewModifier {
    public typealias Body = Never

    public static func _makeNode<Content: View>(_ context: _NodeContext<ModifiedContent<Content, Self>>) -> TypedNode<ModifiedContent<Content, Self>> {
        PreferenceTransformNode(context)
    }
}

/// Runs an action after layout whenever the content's preference value changes.
public struct _PreferenceActionModifier<Key: PreferenceKey> where Key.Value: Equatable {
    public var action: @MainActor (Key.Value) -> Void
    public init(action: @escaping @MainActor (Key.Value) -> Void) { self.action = action }
}

extension _PreferenceActionModifier: ViewModifier {
    public typealias Body = Never

    public static func _makeNode<Content: View>(_ context: _NodeContext<ModifiedContent<Content, Self>>) -> TypedNode<ModifiedContent<Content, Self>> {
        PreferenceActionNode(context)
    }
}

extension View {
    /// Sets a value for the given preference.
    nonisolated public func preference<K: PreferenceKey>(key: K.Type = K.self, value: K.Value) -> some View {
        modifier(_PreferenceWritingModifier<K>(value: value))
    }

    /// Applies a transformation to a preference value.
    nonisolated public func transformPreference<K: PreferenceKey>(_ key: K.Type = K.self, _ callback: @escaping (inout K.Value) -> Void) -> some View {
        modifier(_PreferenceTransformModifier<K>(transform: callback))
    }

    /// Adds an action to perform when the specified preference key's value changes.
    nonisolated public func onPreferenceChange<K: PreferenceKey>(_ key: K.Type = K.self, perform action: @escaping @MainActor (K.Value) -> Void) -> some View where K.Value: Equatable {
        modifier(_PreferenceActionModifier<K>(action: action))
    }
}
