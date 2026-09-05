// `position` and the safe-area modifiers. A browser window has no safe area of its own, but
// `safeAreaInset`/`safeAreaPadding` create one: plain content is laid out inside it, scroll
// views (and `ignoresSafeArea`) keep their frame and inset their content instead.

/// Fixes the centre of the content at a point in its parent's coordinate space; the modified
/// view takes the proposed size.
@frozen
public struct _PositionLayout: Equatable {
    public var position: CGPoint
    public init(position: CGPoint) { self.position = position }
}

extension _PositionLayout: ViewModifier {
    public typealias Body = Never

    public static func _makeNode<Content: View>(_ context: _NodeContext<ModifiedContent<Content, Self>>) -> TypedNode<ModifiedContent<Content, Self>> {
        PositionNode(context)
    }
}

/// An edge of a rectangle along one axis.
public enum HorizontalEdge: Int8, CaseIterable, Hashable, Sendable {
    case leading, trailing

    public struct Set: OptionSet, Sendable {
        public let rawValue: Int8
        public init(rawValue: Int8) { self.rawValue = rawValue }
        public init(_ edge: HorizontalEdge) { self.init(rawValue: 1 << edge.rawValue) }
        public static let leading = Set(.leading)
        public static let trailing = Set(.trailing)
        public static let all: Set = [.leading, .trailing]
    }
}

/// The regions of a safe area (`ignoresSafeArea`); a browser window only has the container.
public struct SafeAreaRegions: OptionSet, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let container = SafeAreaRegions(rawValue: 1 << 0)
    public static let keyboard = SafeAreaRegions(rawValue: 1 << 1)
    public static let all: SafeAreaRegions = [.container, .keyboard]
}

/// Shows `inset` beside the content at `edge` and adds its length (plus `spacing`) to the
/// content's safe area.
public struct _SafeAreaInsetModifier<Inset: View> {
    public var edge: Edge
    public var alignment: Alignment
    public var spacing: CGFloat?
    public var inset: Inset

    public init(edge: Edge, alignment: Alignment, spacing: CGFloat?, inset: Inset) {
        self.edge = edge
        self.alignment = alignment
        self.spacing = spacing
        self.inset = inset
    }
}

extension _SafeAreaInsetModifier: ViewModifier {
    public typealias Body = Never

    public static func _makeNode<Content: View>(_ context: _NodeContext<ModifiedContent<Content, Self>>) -> TypedNode<ModifiedContent<Content, Self>> {
        SafeAreaInsetNode(context)
    }
}

/// Adds fixed lengths to the content's safe area.
@frozen
public struct _SafeAreaPaddingModifier: Equatable {
    public var edges: Edge.Set
    public var length: CGFloat?
    public var insets: EdgeInsets?

    public init(edges: Edge.Set, length: CGFloat?) {
        self.edges = edges
        self.length = length
    }

    public init(insets: EdgeInsets) {
        edges = .all
        self.insets = insets
    }

    /// The insets to add: explicit ones, or `length` (default 16) on `edges`.
    package var resolvedInsets: EdgeInsets {
        if let insets { return insets }
        let value = length ?? 16
        return EdgeInsets(top: edges.contains(.top) ? value : 0, leading: edges.contains(.leading) ? value : 0,
                          bottom: edges.contains(.bottom) ? value : 0, trailing: edges.contains(.trailing) ? value : 0)
    }
}

extension _SafeAreaPaddingModifier: ViewModifier {
    public typealias Body = Never

    public static func _makeNode<Content: View>(_ context: _NodeContext<ModifiedContent<Content, Self>>) -> TypedNode<ModifiedContent<Content, Self>> {
        SafeAreaPaddingNode(context)
    }
}

/// Lets the content extend into the safe area on `edges`.
@frozen
public struct _IgnoresSafeAreaModifier: Equatable {
    public var regions: SafeAreaRegions
    public var edges: Edge.Set
    public init(regions: SafeAreaRegions, edges: Edge.Set) {
        self.regions = regions
        self.edges = edges
    }
}

extension _IgnoresSafeAreaModifier: ViewModifier {
    public typealias Body = Never

    public static func _makeNode<Content: View>(_ context: _NodeContext<ModifiedContent<Content, Self>>) -> TypedNode<ModifiedContent<Content, Self>> {
        IgnoresSafeAreaNode(context)
    }
}

extension View {
    /// Positions the centre of this view at the given coordinates in its parent's coordinate
    /// space; the view itself takes the proposed size.
    nonisolated public func position(_ position: CGPoint) -> some View {
        modifier(_PositionLayout(position: position))
    }

    /// Positions the centre of this view at the given point in its parent's coordinate space.
    nonisolated public func position(x: CGFloat = 0, y: CGFloat = 0) -> some View {
        modifier(_PositionLayout(position: CGPoint(x: x, y: y)))
    }

    /// Shows the given content above or below this view, insetting the view's safe area by the
    /// content's height plus `spacing` (default 8): plain content shrinks, scroll views keep
    /// their frame and inset their content.
    nonisolated public func safeAreaInset<V: View>(edge: VerticalEdge, alignment: HorizontalAlignment = .center, spacing: CGFloat? = nil,
                                                   @ViewBuilder content: () -> V) -> some View {
        modifier(_SafeAreaInsetModifier(edge: edge == .top ? .top : .bottom, alignment: Alignment(horizontal: alignment, vertical: .center),
                                        spacing: spacing, inset: content()))
    }

    /// Shows the given content beside this view, insetting the view's safe area by its width.
    nonisolated public func safeAreaInset<V: View>(edge: HorizontalEdge, alignment: VerticalAlignment = .center, spacing: CGFloat? = nil,
                                                   @ViewBuilder content: () -> V) -> some View {
        modifier(_SafeAreaInsetModifier(edge: edge == .leading ? .leading : .trailing, alignment: Alignment(horizontal: .center, vertical: alignment),
                                        spacing: spacing, inset: content()))
    }

    /// Adds the insets to this view's safe area.
    nonisolated public func safeAreaPadding(_ insets: EdgeInsets) -> some View {
        modifier(_SafeAreaPaddingModifier(insets: insets))
    }

    /// Adds `length` (default 16) to this view's safe area on `edges`.
    nonisolated public func safeAreaPadding(_ edges: Edge.Set = .all, _ length: CGFloat? = nil) -> some View {
        modifier(_SafeAreaPaddingModifier(edges: edges, length: length))
    }

    /// Adds `length` to this view's safe area on every edge.
    nonisolated public func safeAreaPadding(_ length: CGFloat) -> some View {
        modifier(_SafeAreaPaddingModifier(edges: .all, length: length))
    }

    /// Expands this view out of its safe area on `edges`.
    nonisolated public func ignoresSafeArea(_ regions: SafeAreaRegions = .all, edges: Edge.Set = .all) -> some View {
        modifier(_IgnoresSafeAreaModifier(regions: regions, edges: edges))
    }

    /// The older spelling of `ignoresSafeArea`.
    nonisolated public func edgesIgnoringSafeArea(_ edges: Edge.Set) -> some View {
        modifier(_IgnoresSafeAreaModifier(regions: .container, edges: edges))
    }
}
