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

// MARK: - Anchor preferences

/// Writes (or transforms) a preference from an anchor of the content's geometry, captured
/// in the root's coordinates when the value is read after layout.
public struct _AnchorPreferenceModifier<Value, Key: PreferenceKey> {
    package enum Write {
        case set((Anchor<Value>) -> Key.Value)
        case transform((inout Key.Value, Anchor<Value>) -> Void)
    }

    package let source: Anchor<Value>.Source
    package let write: Write

    package init(source: Anchor<Value>.Source, write: Write) {
        self.source = source
        self.write = write
    }
}

extension _AnchorPreferenceModifier: ViewModifier {
    public typealias Body = Never

    public static func _makeNode<Content: View>(_ context: _NodeContext<ModifiedContent<Content, Self>>) -> TypedNode<ModifiedContent<Content, Self>> {
        AnchorPreferenceNode(context)
    }
}

/// Layers a view, built from the content's value of a preference, behind or in front of it.
public struct _PreferenceValueLayerModifier<Key: PreferenceKey, Layer: View> {
    package let alignment: Alignment
    package let isOverlay: Bool
    package let transform: (Key.Value) -> Layer

    package init(alignment: Alignment, isOverlay: Bool, transform: @escaping (Key.Value) -> Layer) {
        self.alignment = alignment
        self.isOverlay = isOverlay
        self.transform = transform
    }
}

extension _PreferenceValueLayerModifier: ViewModifier {
    public typealias Body = Never

    public static func _makeNode<Content: View>(_ context: _NodeContext<ModifiedContent<Content, Self>>) -> TypedNode<ModifiedContent<Content, Self>> {
        PreferenceValueLayerNode(context)
    }
}

extension View {
    /// Sets a value for the specified preference key, the value is a function of a geometry
    /// value tied to the current coordinate space, allowing readers of the value to convert the
    /// geometry to their local coordinates.
    nonisolated public func anchorPreference<A, K: PreferenceKey>(key _: K.Type = K.self, value: Anchor<A>.Source,
                                                                  transform: @escaping (Anchor<A>) -> K.Value) -> some View {
        modifier(_AnchorPreferenceModifier<A, K>(source: value, write: .set(transform)))
    }

    /// Sets a value for the specified preference key from a geometry anchor, combined with the
    /// value the content's subtree writes.
    nonisolated public func transformAnchorPreference<A, K: PreferenceKey>(key _: K.Type = K.self, value: Anchor<A>.Source,
                                                                           transform: @escaping (inout K.Value, Anchor<A>) -> Void) -> some View {
        modifier(_AnchorPreferenceModifier<A, K>(source: value, write: .transform(transform)))
    }

    /// Reads the specified preference value from the view, using it to produce a second view
    /// that is applied as an overlay to the original view.
    nonisolated public func overlayPreferenceValue<K: PreferenceKey, V: View>(_ key: K.Type = K.self, alignment: Alignment = .center,
                                                                              @ViewBuilder _ transform: @escaping (K.Value) -> V) -> some View {
        modifier(_PreferenceValueLayerModifier<K, V>(alignment: alignment, isOverlay: true, transform: transform))
    }

    /// Reads the specified preference value from the view, using it to produce a second view
    /// that is applied as the background of the original view.
    nonisolated public func backgroundPreferenceValue<K: PreferenceKey, V: View>(_ key: K.Type = K.self, alignment: Alignment = .center,
                                                                                 @ViewBuilder _ transform: @escaping (K.Value) -> V) -> some View {
        modifier(_PreferenceValueLayerModifier<K, V>(alignment: alignment, isOverlay: false, transform: transform))
    }
}
