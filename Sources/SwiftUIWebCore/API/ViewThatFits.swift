// ViewThatFits (Docs/elements/Layout.md): the first child whose ideal size fits the proposal
// on the chosen axes, or the last child; only that child is laid out and shown.

/// A view that adapts to the available space by providing the first child view that fits.
public struct ViewThatFits<Content: View>: View {
    package let axes: Axis.Set
    package let content: Content

    /// Produces a view constrained in the given axes from one of several alternatives provided
    /// by a view builder.
    public init(in axes: Axis.Set = [.horizontal, .vertical], @ViewBuilder content: () -> Content) {
        self.axes = axes
        self.content = content()
    }

    public typealias Body = Never

    public static func _makeNode(_ context: _NodeContext<ViewThatFits<Content>>) -> TypedNode<ViewThatFits<Content>> {
        ViewThatFitsNode(context)
    }
}
