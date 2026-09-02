/// A view that arranges its subviews in a horizontal line.
@frozen
public struct HStack<Content: View> {
    @usableFromInline package let _layout: HStackLayout
    @usableFromInline package let _content: Content

    /// Creates a horizontal stack with the given spacing and vertical alignment.
    @inlinable
    public init(alignment: VerticalAlignment = .center, spacing: CGFloat? = nil, @ViewBuilder content: () -> Content) {
        _layout = HStackLayout(alignment: alignment, spacing: spacing)
        _content = content()
    }
}

extension HStack: View {
    public typealias Body = Never

    public static func _makeNode(_ context: _NodeContext<HStack<Content>>) -> TypedNode<HStack<Content>> {
        LayoutContainerNode(context, layout: \._layout, content: \._content)
    }
}

/// A view that arranges its subviews in a vertical line.
@frozen
public struct VStack<Content: View> {
    @usableFromInline package let _layout: VStackLayout
    @usableFromInline package let _content: Content

    /// Creates a vertical stack with the given spacing and horizontal alignment.
    @inlinable
    public init(alignment: HorizontalAlignment = .center, spacing: CGFloat? = nil, @ViewBuilder content: () -> Content) {
        _layout = VStackLayout(alignment: alignment, spacing: spacing)
        _content = content()
    }
}

extension VStack: View {
    public typealias Body = Never

    public static func _makeNode(_ context: _NodeContext<VStack<Content>>) -> TypedNode<VStack<Content>> {
        LayoutContainerNode(context, layout: \._layout, content: \._content)
    }
}

/// A view that overlays its subviews, aligning them in both axes.
@frozen
public struct ZStack<Content: View> {
    @usableFromInline package let _layout: ZStackLayout
    @usableFromInline package let _content: Content

    /// Creates an instance with the given alignment.
    @inlinable
    public init(alignment: Alignment = .center, @ViewBuilder content: () -> Content) {
        _layout = ZStackLayout(alignment: alignment)
        _content = content()
    }
}

extension ZStack: View {
    public typealias Body = Never

    public static func _makeNode(_ context: _NodeContext<ZStack<Content>>) -> TypedNode<ZStack<Content>> {
        LayoutContainerNode(context, layout: \._layout, content: \._content)
    }
}

/// A flexible space that expands along the major axis of its containing stack layout, or on
/// both axes if not contained in a stack.
@frozen
public struct Spacer: Sendable {
    /// The minimum length this spacer can be shrunk to, along the axis or axes of expansion.
    public var minLength: CGFloat?

    @inlinable
    public init(minLength: CGFloat? = nil) {
        self.minLength = minLength
    }
}

extension Spacer: View {
    public typealias Body = Never

    public static func _makeNode(_ context: _NodeContext<Spacer>) -> TypedNode<Spacer> {
        SpacerNode(context)
    }
}

/// A visual element that can be used to separate other content.
public struct Divider: Sendable {
    public init() {}
}

extension Divider: View {
    public typealias Body = Never

    public static func _makeNode(_ context: _NodeContext<Divider>) -> TypedNode<Divider> {
        DividerNode(context)
    }
}
