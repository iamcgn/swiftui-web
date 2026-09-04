// Layer modifiers that change how a view is composited, not where it is laid out: `zIndex`
// reorders overlapping siblings; `hidden` keeps the space and draws nothing.

/// Sets the display order of a view among its siblings.
@frozen
public struct _ZIndexEffect: Equatable {
    public var value: Double
    public init(value: Double) { self.value = value }
}

extension _ZIndexEffect: ViewModifier {
    public typealias Body = Never

    public static func _makeNode<Content: View>(_ context: _NodeContext<ModifiedContent<Content, Self>>) -> TypedNode<ModifiedContent<Content, Self>> {
        ZIndexNode(context)
    }
}

/// Hides a view while keeping its layout.
@frozen
public struct _HiddenModifier: Equatable {
    public init() {}
}

extension _HiddenModifier: ViewModifier {
    public typealias Body = Never

    public static func _makeNode<Content: View>(_ context: _NodeContext<ModifiedContent<Content, Self>>) -> TypedNode<ModifiedContent<Content, Self>> {
        HiddenNode(context)
    }
}

extension View {
    /// Controls the display order of overlapping views: within one container, views with a
    /// higher value draw in front; equal values keep their declaration order. The default is 0.
    nonisolated public func zIndex(_ value: Double) -> some View {
        modifier(_ZIndexEffect(value: value))
    }

    /// Hides this view: it keeps its place in the layout but draws nothing, is not hit tested
    /// and is absent from the accessibility tree.
    nonisolated public func hidden() -> some View {
        modifier(_HiddenModifier())
    }
}
