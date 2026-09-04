// Lazy stacks (Docs/elements/Lazy.md): laid out eagerly like stacks, but filling the axis
// across the stack (a `LazyVStack` takes the proposed width, a `LazyHStack` the height).

/// The kinds of views a lazy stack pins while scrolling (accepted; nothing is pinned here).
public struct PinnedScrollableViews: OptionSet, Sendable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }
    public static let sectionHeaders = PinnedScrollableViews(rawValue: 1)
    public static let sectionFooters = PinnedScrollableViews(rawValue: 2)
}

/// A view that arranges its children in a line that grows vertically, creating items only as needed.
public struct LazyVStack<Content: View>: View {
    package let alignment: HorizontalAlignment
    package let spacing: CGFloat?
    package let pinnedViews: PinnedScrollableViews
    package let content: Content

    public init(alignment: HorizontalAlignment = .center, spacing: CGFloat? = nil, pinnedViews: PinnedScrollableViews = [],
                @ViewBuilder content: () -> Content) {
        self.alignment = alignment
        self.spacing = spacing
        self.pinnedViews = pinnedViews
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: alignment, spacing: spacing) { content }
            .frame(maxWidth: .infinity, alignment: Alignment(horizontal: alignment, vertical: .top))
    }
}

/// A view that arranges its children in a line that grows horizontally, creating items only as needed.
public struct LazyHStack<Content: View>: View {
    package let alignment: VerticalAlignment
    package let spacing: CGFloat?
    package let pinnedViews: PinnedScrollableViews
    package let content: Content

    public init(alignment: VerticalAlignment = .center, spacing: CGFloat? = nil, pinnedViews: PinnedScrollableViews = [],
                @ViewBuilder content: () -> Content) {
        self.alignment = alignment
        self.spacing = spacing
        self.pinnedViews = pinnedViews
        self.content = content()
    }

    public var body: some View {
        HStack(alignment: alignment, spacing: spacing) { content }
            .frame(maxHeight: .infinity, alignment: Alignment(horizontal: .leading, vertical: alignment))
    }
}
