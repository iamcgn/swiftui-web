/// A container view that you can use to add hierarchy within certain views.
///
/// In containers that support sections (`List`, `Form`, `Picker`) the header and footer are
/// styled by the container. Elsewhere a section is transparent, like `Group`: its header,
/// content and footer contribute their views to the enclosing layout in that order.
public struct Section<Parent, Content, Footer> {
    package let header: Parent
    package let content: Content
    package let footer: Footer

    package init(header: Parent, content: Content, footer: Footer) {
        self.header = header
        self.content = content
        self.footer = footer
    }
}

extension Section: View where Parent: View, Content: View, Footer: View {
    public typealias Body = Never

    public static func _makeNode(_ context: _NodeContext<Section<Parent, Content, Footer>>) -> TypedNode<Section<Parent, Content, Footer>> {
        SectionNode(context)
    }
}

extension Section where Parent: View, Content: View, Footer: View {
    /// Creates a section with a header, content and footer.
    public init(@ViewBuilder content: () -> Content, @ViewBuilder header: () -> Parent, @ViewBuilder footer: () -> Footer) {
        self.init(header: header(), content: content(), footer: footer())
    }
}

extension Section where Parent == EmptyView, Content: View, Footer: View {
    /// Creates a section with content and a footer.
    public init(@ViewBuilder content: () -> Content, @ViewBuilder footer: () -> Footer) {
        self.init(header: EmptyView(), content: content(), footer: footer())
    }
}

extension Section where Parent: View, Content: View, Footer == EmptyView {
    /// Creates a section with a header and content.
    public init(@ViewBuilder content: () -> Content, @ViewBuilder header: () -> Parent) {
        self.init(header: header(), content: content(), footer: EmptyView())
    }
}

extension Section where Parent == EmptyView, Content: View, Footer == EmptyView {
    /// Creates a section with content only.
    public init(@ViewBuilder content: () -> Content) {
        self.init(header: EmptyView(), content: content(), footer: EmptyView())
    }
}

extension Section where Parent == Text, Content: View, Footer == EmptyView {
    /// Creates a section with the provided localized title as its header.
    public init(_ titleKey: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.init(header: Text(titleKey), content: content(), footer: EmptyView())
    }

    /// Creates a section with the provided string as its header.
    @_disfavoredOverload
    public init<S: StringProtocol>(_ title: S, @ViewBuilder content: () -> Content) {
        self.init(header: Text(title), content: content(), footer: EmptyView())
    }
}

// Deprecated argument orders, kept because existing app source still uses them.
extension Section where Parent: View, Content: View, Footer: View {
    @available(*, deprecated, renamed: "init(content:header:footer:)")
    public init(header: Parent, footer: Footer, @ViewBuilder content: () -> Content) {
        self.init(header: header, content: content(), footer: footer)
    }
}

extension Section where Parent == EmptyView, Content: View, Footer: View {
    @available(*, deprecated, renamed: "init(content:footer:)")
    public init(footer: Footer, @ViewBuilder content: () -> Content) {
        self.init(header: EmptyView(), content: content(), footer: footer)
    }
}

extension Section where Parent: View, Content: View, Footer == EmptyView {
    @available(*, deprecated, renamed: "init(content:header:)")
    public init(header: Parent, @ViewBuilder content: () -> Content) {
        self.init(header: header, content: content(), footer: EmptyView())
    }
}
