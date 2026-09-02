/// Layout-specific properties of a layout container.
public struct LayoutProperties: Sendable {
    /// The orientation of the containing stack-like container, if any.
    public var stackOrientation: Axis?

    public init() {}
}

/// A key for accessing a layout value of a layout container's subviews.
public protocol LayoutValueKey {
    associatedtype Value
    static var defaultValue: Self.Value { get }
}

/// A type that defines the geometry of a collection of views.
@MainActor @preconcurrency
public protocol Layout: Animatable {
    /// Cached values computed by the layout container.
    associatedtype Cache = Void

    /// Properties of a layout container.
    static var layoutProperties: LayoutProperties { get }

    /// Creates and initializes a cache for a layout instance.
    func makeCache(subviews: Self.Subviews) -> Self.Cache

    /// Updates the layout's cache when something changes.
    func updateCache(_ cache: inout Self.Cache, subviews: Self.Subviews)

    /// Returns the preferred spacing values of the composite view.
    func spacing(subviews: Self.Subviews, cache: inout Self.Cache) -> ViewSpacing

    /// Returns the size of the composite view, given a proposed size and the view's subviews.
    func sizeThatFits(proposal: ProposedViewSize, subviews: Self.Subviews, cache: inout Self.Cache) -> CGSize

    /// Assigns positions to each of the layout's subviews.
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Self.Subviews, cache: inout Self.Cache)

    /// Returns the position of the specified horizontal alignment guide along the x axis.
    func explicitAlignment(of guide: HorizontalAlignment, in bounds: CGRect, proposal: ProposedViewSize,
                           subviews: Self.Subviews, cache: inout Self.Cache) -> CGFloat?

    /// Returns the position of the specified vertical alignment guide along the y axis.
    func explicitAlignment(of guide: VerticalAlignment, in bounds: CGRect, proposal: ProposedViewSize,
                           subviews: Self.Subviews, cache: inout Self.Cache) -> CGFloat?

    /// A collection of proxies for the subviews of a layout view.
    typealias Subviews = LayoutSubviews
}

extension Layout {
    public static var layoutProperties: LayoutProperties { LayoutProperties() }

    public func updateCache(_ cache: inout Self.Cache, subviews: Self.Subviews) {
        cache = makeCache(subviews: subviews)
    }

    public func spacing(subviews: Self.Subviews, cache: inout Self.Cache) -> ViewSpacing {
        var spacing = ViewSpacing.zero
        for subview in subviews { spacing.formUnion(subview.spacing) }
        return spacing
    }

    public func explicitAlignment(of guide: HorizontalAlignment, in bounds: CGRect, proposal: ProposedViewSize,
                                  subviews: Self.Subviews, cache: inout Self.Cache) -> CGFloat? {
        nil
    }

    public func explicitAlignment(of guide: VerticalAlignment, in bounds: CGRect, proposal: ProposedViewSize,
                                  subviews: Self.Subviews, cache: inout Self.Cache) -> CGFloat? {
        nil
    }
}

extension Layout where Cache == Void {
    public func makeCache(subviews: Self.Subviews) -> Void {}
}

extension Layout {
    /// Combines the specified views into a single composite view using the layout algorithms of
    /// the custom layout container.
    nonisolated public func callAsFunction<V: View>(@ViewBuilder _ content: () -> V) -> some View {
        _LayoutView(layout: self, content: content())
    }
}

/// A proxy that represents one subview of a layout.
public struct LayoutSubview: Equatable {
    package let node: ViewNode
    package let container: ViewNode
    package let index: Int

    package init(node: ViewNode, container: ViewNode, index: Int) {
        self.node = node
        self.container = container
        self.index = index
    }

    /// The layout priority of the subview.
    @MainActor public var priority: Double { node.layoutPriority }

    /// The view's preferred spacing values.
    @MainActor public var spacing: ViewSpacing { node.layoutSpacing }

    /// Gets the value of a layout value key.
    @MainActor public subscript<K: LayoutValueKey>(key: K.Type) -> K.Value {
        node.layoutValue(for: key)
    }

    /// Asks the subview for its size.
    @MainActor public func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
        node.sizeThatFits(proposal)
    }

    /// Asks the subview for its dimensions and alignment guides.
    @MainActor public func dimensions(in proposal: ProposedViewSize) -> ViewDimensions {
        node.dimensions(in: proposal)
    }

    /// Assigns a position and proposed size to the subview.
    @MainActor public func place(at position: CGPoint, anchor: UnitPoint = .topLeading, proposal: ProposedViewSize) {
        node.place(at: position, anchor: anchor, proposal: proposal, by: container)
    }

    public static func == (lhs: LayoutSubview, rhs: LayoutSubview) -> Bool {
        lhs.node === rhs.node
    }
}

/// A collection of proxy values that represent the subviews of a layout view.
public struct LayoutSubviews: RandomAccessCollection, Equatable {
    public typealias Element = LayoutSubview
    public typealias Index = Int
    public typealias SubSequence = LayoutSubviews

    package let elements: [LayoutSubview]

    /// The layout direction inherited by the container view.
    public let layoutDirection: LayoutDirection

    package init(_ elements: [LayoutSubview], layoutDirection: LayoutDirection = .leftToRight) {
        self.elements = elements
        self.layoutDirection = layoutDirection
    }

    public var startIndex: Int { 0 }
    public var endIndex: Int { elements.count }
    public subscript(index: Int) -> LayoutSubview { elements[index] }
    public subscript(bounds: Range<Int>) -> LayoutSubviews {
        LayoutSubviews(Array(elements[bounds]), layoutDirection: layoutDirection)
    }
    public subscript<S: Sequence>(indices: S) -> LayoutSubviews where S.Element == Int {
        LayoutSubviews(indices.map { elements[$0] }, layoutDirection: layoutDirection)
    }
}

/// A direction in which SwiftUI can lay out content.
public enum LayoutDirection: Hashable, CaseIterable, Sendable {
    case leftToRight
    case rightToLeft
}

/// The view produced by calling a `Layout` as a function.
public struct _LayoutView<L: Layout, Content: View> {
    public var layout: L
    public var content: Content

    public init(layout: L, content: Content) {
        self.layout = layout
        self.content = content
    }
}

extension _LayoutView: View {
    public typealias Body = Never

    public static func _makeNode(_ context: _NodeContext<_LayoutView<L, Content>>) -> TypedNode<_LayoutView<L, Content>> {
        LayoutContainerNode(context, layout: \.layout, content: \.content)
    }
}
