// Geometry a view reads about itself or its container (iOS 17-18): `onGeometryChange` runs an
// action when a value derived from the view's geometry changes; `containerRelativeFrame` sizes
// the view as a share of its container (the nearest scroll view, else the window's safe area);
// `geometryGroup` isolates a subtree's geometry for animations. Nodes in
// Runtime/GeometryChangeNodes.swift.

/// `onGeometryChange`: derives a value from the view's geometry after each layout pass and
/// queues the action when it changes (once at appearance, with the first value as both the old
/// and the new one).
public struct _GeometryChangeModifier<Value: Equatable> {
    public var transform: (GeometryProxy) -> Value
    public var action: (Value, Value) -> Void

    public init(transform: @escaping (GeometryProxy) -> Value, action: @escaping (Value, Value) -> Void) {
        self.transform = transform
        self.action = action
    }
}

extension _GeometryChangeModifier: ViewModifier {
    public typealias Body = Never

    public static func _makeNode<Content: View>(_ context: _NodeContext<ModifiedContent<Content, Self>>) -> TypedNode<ModifiedContent<Content, Self>> {
        GeometryChangeNode(context)
    }
}

extension View {
    /// Adds an action to be performed when a value, created from a geometry proxy, changes. The
    /// action runs when the view first appears, then whenever the value changes.
    nonisolated public func onGeometryChange<T: Equatable>(for type: T.Type, of transform: @escaping (GeometryProxy) -> T,
                                                           action: @escaping (_ newValue: T) -> Void) -> some View {
        modifier(_GeometryChangeModifier(transform: transform, action: { _, new in action(new) }))
    }

    /// Adds an action to be performed when a value, created from a geometry proxy, changes; the
    /// action receives the old and the new value.
    nonisolated public func onGeometryChange<T: Equatable>(for type: T.Type, of transform: @escaping (GeometryProxy) -> T,
                                                           action: @escaping (_ oldValue: T, _ newValue: T) -> Void) -> some View {
        modifier(_GeometryChangeModifier(transform: transform, action: action))
    }
}

// MARK: - Container-relative frames

/// `containerRelativeFrame`: along the given axes the view takes a length computed from its
/// container's (the nearest scroll view's visible size, else the window's safe area), and is
/// aligned within it; along the others it keeps its own size.
public struct _ContainerRelativeFrameModifier {
    public var axes: Axis.Set
    public var alignment: Alignment
    public var length: (CGFloat, Axis) -> CGFloat

    public init(axes: Axis.Set, alignment: Alignment, length: @escaping (CGFloat, Axis) -> CGFloat) {
        self.axes = axes
        self.alignment = alignment
        self.length = length
    }
}

extension _ContainerRelativeFrameModifier: ViewModifier {
    public typealias Body = Never

    public static func _makeNode<Content: View>(_ context: _NodeContext<ModifiedContent<Content, Self>>) -> TypedNode<ModifiedContent<Content, Self>> {
        ContainerRelativeFrameNode(context)
    }
}

extension View {
    /// Positions this view within an invisible frame with a size relative to the nearest
    /// container: along `axes` the view is the container's full length.
    nonisolated public func containerRelativeFrame(_ axes: Axis.Set, alignment: Alignment = .center) -> some View {
        modifier(_ContainerRelativeFrameModifier(axes: axes, alignment: alignment, length: { length, _ in length }))
    }

    /// Positions this view within an invisible frame whose size is `span` of `count` equal
    /// columns (or rows) of the container's length, `spacing` apart.
    nonisolated public func containerRelativeFrame(_ axes: Axis.Set, count: Int, span: Int = 1, spacing: CGFloat,
                                                   alignment: Alignment = .center) -> some View {
        modifier(_ContainerRelativeFrameModifier(axes: axes, alignment: alignment, length: { length, _ in
            _ContainerRelativeFrameModifier.share(of: length, count: count, span: span, spacing: spacing)
        }))
    }

    /// Positions this view within an invisible frame whose size along `axes` is what `length`
    /// returns for the container's length along each axis.
    nonisolated public func containerRelativeFrame(_ axes: Axis.Set, alignment: Alignment = .center,
                                                   _ length: @escaping (CGFloat, Axis) -> CGFloat) -> some View {
        modifier(_ContainerRelativeFrameModifier(axes: axes, alignment: alignment, length: length))
    }

    /// Isolates the geometry (position and size) of this view from its parent's during an
    /// animation. The runtime already animates each view's frame on its own, so the view is
    /// returned as it is.
    nonisolated public func geometryGroup() -> some View { self }
}

extension _ContainerRelativeFrameModifier {
    /// `span` of `count` columns of `length` with `spacing` between columns: the columns share
    /// what the gaps leave, and a span crosses the gaps inside it.
    package static func share(of length: CGFloat, count: Int, span: Int, spacing: CGFloat) -> CGFloat {
        let count = max(1, count), span = min(max(1, span), count)
        let column = max(0, length - spacing * CGFloat(count - 1)) / CGFloat(count)
        return column * CGFloat(span) + spacing * CGFloat(span - 1)
    }
}
