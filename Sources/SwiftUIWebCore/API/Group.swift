/// A type that collects multiple instances of a content type — like views, scenes, or commands —
/// into a single unit.
///
/// `Group` is transparent to layout: its children contribute directly to the enclosing container,
/// so `HStack { Group { A; B }; C }` lays out three children.
@frozen
public struct Group<Content> {
    @usableFromInline
    package let content: Content

    @usableFromInline
    package init(_content: Content) {
        self.content = _content
    }
}

extension Group: View where Content: View {
    public typealias Body = Never

    /// Creates a group of views.
    @inlinable
    public init(@ViewBuilder content: () -> Content) {
        self.init(_content: content())
    }
}
