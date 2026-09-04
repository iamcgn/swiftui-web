/// Geometry effects (`Docs/elements/Transform.md`): they leave layout alone and transform the
/// painting of the modified view through the display list's `concat`. Their parameters animate.

public struct _OffsetEffect: Equatable {
    public var offset: CGSize
    public init(offset: CGSize) { self.offset = offset }
}

public struct _RotationEffect: Equatable {
    public var angle: Angle
    public var anchor: UnitPoint
    public init(angle: Angle, anchor: UnitPoint) { self.angle = angle; self.anchor = anchor }
}

public struct _ScaleEffect: Equatable {
    public var scale: CGSize
    public var anchor: UnitPoint
    public init(scale: CGSize, anchor: UnitPoint) { self.scale = scale; self.anchor = anchor }
}

public struct _TransformEffect: Equatable {
    public var transform: CGAffineTransform
    public init(transform: CGAffineTransform) { self.transform = transform }
}

extension _OffsetEffect: ViewModifier {
    public typealias Body = Never
    public static func _makeNode<Content: View>(_ context: _NodeContext<ModifiedContent<Content, Self>>) -> TypedNode<ModifiedContent<Content, Self>> {
        OffsetNode(context)
    }
}

extension _RotationEffect: ViewModifier {
    public typealias Body = Never
    public static func _makeNode<Content: View>(_ context: _NodeContext<ModifiedContent<Content, Self>>) -> TypedNode<ModifiedContent<Content, Self>> {
        RotationNode(context)
    }
}

extension _ScaleEffect: ViewModifier {
    public typealias Body = Never
    public static func _makeNode<Content: View>(_ context: _NodeContext<ModifiedContent<Content, Self>>) -> TypedNode<ModifiedContent<Content, Self>> {
        ScaleNode(context)
    }
}

extension _TransformEffect: ViewModifier {
    public typealias Body = Never
    public static func _makeNode<Content: View>(_ context: _NodeContext<ModifiedContent<Content, Self>>) -> TypedNode<ModifiedContent<Content, Self>> {
        TransformNode(context)
    }
}

extension View {
    /// Offset this view by the horizontal and vertical amount specified in the offset parameter.
    nonisolated public func offset(_ offset: CGSize) -> some View { modifier(_OffsetEffect(offset: offset)) }

    /// Offset this view by the specified horizontal and vertical distances.
    nonisolated public func offset(x: CGFloat = 0, y: CGFloat = 0) -> some View { modifier(_OffsetEffect(offset: CGSize(width: x, height: y))) }

    /// Rotates a view's rendered output in two dimensions around the specified point.
    nonisolated public func rotationEffect(_ angle: Angle, anchor: UnitPoint = .center) -> some View {
        modifier(_RotationEffect(angle: angle, anchor: anchor))
    }

    /// Scales this view's rendered output by the given vertical and horizontal size amounts.
    nonisolated public func scaleEffect(_ scale: CGSize, anchor: UnitPoint = .center) -> some View {
        modifier(_ScaleEffect(scale: scale, anchor: anchor))
    }

    /// Scales this view's rendered output by the given amount in both dimensions.
    nonisolated public func scaleEffect(_ s: CGFloat, anchor: UnitPoint = .center) -> some View {
        modifier(_ScaleEffect(scale: CGSize(width: s, height: s), anchor: anchor))
    }

    /// Scales this view's rendered output by the given horizontal and vertical amounts.
    nonisolated public func scaleEffect(x: CGFloat = 1, y: CGFloat = 1, anchor: UnitPoint = .center) -> some View {
        modifier(_ScaleEffect(scale: CGSize(width: x, height: y), anchor: anchor))
    }

    /// Applies an affine transformation to this view's rendered output.
    nonisolated public func transformEffect(_ transform: CGAffineTransform) -> some View {
        modifier(_TransformEffect(transform: transform))
    }
}
