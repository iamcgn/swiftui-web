// Lazy stacks (Docs/elements/Lazy.md): a `VStack`/`HStack` filling the axis across it inside a
// `_LazyContainer`, which marks the content lazy (a `ForEach` in it creates its elements as
// they scroll into view) and pins section headers and footers.

/// The kinds of views a lazy stack pins while scrolling.
public struct PinnedScrollableViews: OptionSet, Sendable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }
    public static let sectionHeaders = PinnedScrollableViews(rawValue: 1)
    public static let sectionFooters = PinnedScrollableViews(rawValue: 2)
}

/// The lazy containers' wrapper: its content is lazy along `axis` and its sections' headers and
/// footers pin (Runtime/LazyNodes.swift).
public struct _LazyContainer<Content: View> {
    package let axis: Axis
    package let pinnedViews: PinnedScrollableViews
    package let content: Content

    package init(axis: Axis, pinnedViews: PinnedScrollableViews, @ViewBuilder content: () -> Content) {
        self.axis = axis
        self.pinnedViews = pinnedViews
        self.content = content()
    }
}

extension _LazyContainer: View {
    public typealias Body = Never

    public static func _makeNode(_ context: _NodeContext<_LazyContainer<Content>>) -> TypedNode<_LazyContainer<Content>> {
        LazyContainerNode(context)
    }
}

package struct LazyContainerAxisKey: EnvironmentKey {
    package static let defaultValue: Axis? = nil
}

extension EnvironmentValues {
    /// The axis of the lazy container the view is in, if any: a `ForEach` there creates its
    /// elements on demand. Scroll views and lists start afresh.
    package var _lazyContainerAxis: Axis? {
        get { self[LazyContainerAxisKey.self] }
        set { self[LazyContainerAxisKey.self] = newValue }
    }
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
        _LazyContainer(axis: .vertical, pinnedViews: pinnedViews) {
            VStack(alignment: alignment, spacing: spacing) { content }
                .frame(maxWidth: .infinity, alignment: Alignment(horizontal: alignment, vertical: .top))
        }
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
        _LazyContainer(axis: .horizontal, pinnedViews: pinnedViews) {
            HStack(alignment: alignment, spacing: spacing) { content }
                .frame(maxHeight: .infinity, alignment: Alignment(horizontal: .leading, vertical: alignment))
        }
    }
}
