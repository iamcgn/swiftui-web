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

    /// Mirrors the view's rendered output horizontally when the layout direction is right to
    /// left (images are not mirrored by default; `layout/rtl-shapes`).
    public func flipsForRightToLeftLayoutDirection(_ enabled: Bool) -> some View {
        _FlipsForRightToLeft(enabled: enabled, content: self)
    }
}

/// `flipsForRightToLeftLayoutDirection`: a horizontal scale of −1 about the centre in a
/// right-to-left environment, nothing otherwise.
struct _FlipsForRightToLeft<Content: View>: View {
    var enabled: Bool
    var content: Content
    @Environment(\.layoutDirection) private var layoutDirection

    var body: some View {
        content.scaleEffect(x: enabled && layoutDirection == .rightToLeft ? -1 : 1, y: 1)
    }
}

// MARK: - 3D rotation, projection, GeometryEffect

/// A 3D transformation matrix (row-major, as Apple's), applied to views through its affine part.
public struct ProjectionTransform: Equatable, Sendable {
    public var m11: CGFloat = 1, m12: CGFloat = 0, m13: CGFloat = 0
    public var m21: CGFloat = 0, m22: CGFloat = 1, m23: CGFloat = 0
    public var m31: CGFloat = 0, m32: CGFloat = 0, m33: CGFloat = 1

    public init() {}
    public init(_ m: CGAffineTransform) {
        m11 = m.a; m12 = m.b; m21 = m.c; m22 = m.d; m31 = m.tx; m32 = m.ty
    }

    public var isIdentity: Bool { self == ProjectionTransform() }
    public var isAffine: Bool { m13 == 0 && m23 == 0 && m33 == 1 }

    /// The affine part (the perspective terms dropped): what the painters can apply.
    public var affine: CGAffineTransform { CGAffineTransform(a: m11, b: m12, c: m21, d: m22, tx: m31, ty: m32) }

    public func concatenating(_ rhs: ProjectionTransform) -> ProjectionTransform {
        var r = ProjectionTransform()
        r.m11 = m11 * rhs.m11 + m12 * rhs.m21 + m13 * rhs.m31
        r.m12 = m11 * rhs.m12 + m12 * rhs.m22 + m13 * rhs.m32
        r.m13 = m11 * rhs.m13 + m12 * rhs.m23 + m13 * rhs.m33
        r.m21 = m21 * rhs.m11 + m22 * rhs.m21 + m23 * rhs.m31
        r.m22 = m21 * rhs.m12 + m22 * rhs.m22 + m23 * rhs.m32
        r.m23 = m21 * rhs.m13 + m22 * rhs.m23 + m23 * rhs.m33
        r.m31 = m31 * rhs.m11 + m32 * rhs.m21 + m33 * rhs.m31
        r.m32 = m31 * rhs.m12 + m32 * rhs.m22 + m33 * rhs.m32
        r.m33 = m31 * rhs.m13 + m32 * rhs.m23 + m33 * rhs.m33
        return r
    }

    public func inverted() -> ProjectionTransform {
        guard isAffine else { return self }
        return ProjectionTransform(affine.inverted())
    }
}

extension CGPoint {
    public func applying(_ m: ProjectionTransform) -> CGPoint {
        let w = x * m.m13 + y * m.m23 + m.m33
        let px = x * m.m11 + y * m.m21 + m.m31
        let py = x * m.m12 + y * m.m22 + m.m32
        return w != 0 && w != 1 ? CGPoint(x: px / w, y: py / w) : CGPoint(x: px, y: py)
    }
}

/// `rotation3DEffect`: a rotation about an axis through the anchor. The painters apply the
/// affine part of the projection: a turn about the vertical axis narrows the view, about the
/// horizontal axis flattens it, about the depth axis rotates it (`perspective` and `anchorZ`
/// are accepted; the trapezoid of a perspective projection is not drawn).
public struct _Rotation3DEffect: Equatable {
    public var angle: Angle
    public var axis: (x: CGFloat, y: CGFloat, z: CGFloat)
    public var anchor: UnitPoint
    public var anchorZ: CGFloat
    public var perspective: CGFloat

    public init(angle: Angle, axis: (x: CGFloat, y: CGFloat, z: CGFloat), anchor: UnitPoint, anchorZ: CGFloat, perspective: CGFloat) {
        self.angle = angle
        self.axis = axis
        self.anchor = anchor
        self.anchorZ = anchorZ
        self.perspective = perspective
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.angle == rhs.angle && lhs.axis == rhs.axis && lhs.anchor == rhs.anchor && lhs.anchorZ == rhs.anchorZ && lhs.perspective == rhs.perspective
    }

    /// The affine part of the rotation matrix for `radians` about the (normalised) axis.
    package static func affine(radians: Double, axis: (x: CGFloat, y: CGFloat, z: CGFloat)) -> CGAffineTransform {
        let length = (axis.x * axis.x + axis.y * axis.y + axis.z * axis.z).squareRoot()
        guard length > 0 else { return .identity }
        let (x, y, z) = (Double(axis.x / length), Double(axis.y / length), Double(axis.z / length))
        let c = _cos(radians), s = _sin(radians), t = 1 - c
        // Rodrigues' rotation: the top-left 2 × 2 of the 3 × 3 matrix is what a flat view keeps.
        return CGAffineTransform(a: CGFloat(t * x * x + c), b: CGFloat(t * x * y + s * z),
                                 c: CGFloat(t * x * y - s * z), d: CGFloat(t * y * y + c), tx: 0, ty: 0)
    }
}

extension _Rotation3DEffect: ViewModifier {
    public typealias Body = Never
    public static func _makeNode<Content: View>(_ context: _NodeContext<ModifiedContent<Content, Self>>) -> TypedNode<ModifiedContent<Content, Self>> {
        Rotation3DNode(context)
    }
}

/// `projectionEffect`: a projection transform's affine part about the view's origin.
public struct _ProjectionEffect: Equatable {
    public var transform: ProjectionTransform
    public init(transform: ProjectionTransform) { self.transform = transform }
}

extension _ProjectionEffect: ViewModifier {
    public typealias Body = Never
    public static func _makeNode<Content: View>(_ context: _NodeContext<ModifiedContent<Content, Self>>) -> TypedNode<ModifiedContent<Content, Self>> {
        ProjectionNode(context)
    }
}

/// An effect that changes the visual appearance of a view, largely without changing its
/// ancestors or descendants: its `effectValue(size:)` projection is applied about the view's
/// origin (the affine part), and its `animatableData` tweens under an animation.
public protocol GeometryEffect: Animatable {
    func effectValue(size: CGSize) -> ProjectionTransform
}

/// The modifier a geometry effect becomes when applied (`View.modifier(_:)`): keeps the effect's
/// own type free of the main actor so plain structs conform.
public struct _GeometryEffectModifier<Effect: GeometryEffect> {
    public var effect: Effect
    public init(effect: Effect) { self.effect = effect }
}

extension _GeometryEffectModifier: ViewModifier {
    public typealias Body = Never
    public static func _makeNode<Content: View>(_ context: _NodeContext<ModifiedContent<Content, Self>>) -> TypedNode<ModifiedContent<Content, Self>> {
        GeometryEffectNode(context)
    }
}

extension GeometryEffect {
    /// Returns an effect that produces the same geometry transform as this effect, but only
    /// applies the transform while rendering its view: the effect itself, as effects never change
    /// layout here.
    public func ignoredByLayout() -> Self { self }
}

extension View {
    /// Applies a geometry effect to this view.
    nonisolated public func modifier<E: GeometryEffect>(_ effect: E) -> some View {
        modifier(_GeometryEffectModifier(effect: effect))
    }

    /// Rotates the view's rendered output in three dimensions around the given axis of rotation.
    nonisolated public func rotation3DEffect(_ angle: Angle, axis: (x: CGFloat, y: CGFloat, z: CGFloat), anchor: UnitPoint = .center,
                                             anchorZ: CGFloat = 0, perspective: CGFloat = 1) -> some View {
        modifier(_Rotation3DEffect(angle: angle, axis: axis, anchor: anchor, anchorZ: anchorZ, perspective: perspective))
    }

    /// Applies a projection transformation to the view's rendered output.
    nonisolated public func projectionEffect(_ transform: ProjectionTransform) -> some View {
        modifier(_ProjectionEffect(transform: transform))
    }
}
