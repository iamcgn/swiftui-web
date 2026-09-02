/// A modifier that you apply to a view or another view modifier, producing a different version
/// of the original value.
@MainActor @preconcurrency
public protocol ViewModifier {
    /// The type of view representing the body.
    associatedtype Body: View

    /// Gets the current body of the caller.
    @ViewBuilder @MainActor @preconcurrency func body(content: Self.Content) -> Self.Body

    /// The content view type passed to `body(content:)`.
    typealias Content = _ViewModifier_Content<Self>

    /// Hidden runtime hook: builds the node for `content.modifier(self)`. Modifiers with a
    /// `body(content:)` use the default; primitive modifiers provide their own node.
    @MainActor static func _makeNode<Content: View>(
        _ context: _NodeContext<ModifiedContent<Content, Self>>
    ) -> TypedNode<ModifiedContent<Content, Self>>
}

extension ViewModifier where Body == Never {
    /// Primitive modifiers (those the runtime applies directly) have no body.
    public func body(content: Content) -> Never {
        _primitiveBodyError(Self.self)
    }
}

extension ViewModifier {
    /// Returns a new modifier that is the result of concatenating `self` with `modifier`.
    @inlinable
    public func concat<T>(_ modifier: T) -> ModifiedContent<Self, T> {
        ModifiedContent(content: self, modifier: modifier)
    }
}

extension View {
    /// Applies a modifier to a view and returns a new view.
    @inlinable
    public func modifier<T>(_ modifier: T) -> ModifiedContent<Self, T> {
        ModifiedContent(content: self, modifier: modifier)
    }
}

/// The view passed to a `ViewModifier.body(content:)` as a stand-in for the modified view.
public struct _ViewModifier_Content<Modifier: ViewModifier> {
    package init() {}
}

extension _ViewModifier_Content: View {
    public typealias Body = Never
}

/// An empty, or identity, modifier, used during development to switch modifiers at compile time.
@frozen
public struct EmptyModifier: Sendable {
    public static let identity = EmptyModifier()

    @inlinable
    public init() {}
}

extension EmptyModifier: ViewModifier {
    public typealias Body = Never
}
