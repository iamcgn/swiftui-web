// Shapes derived from other shapes: offset, scaled, rotated, transformed, sized, trimmed,
// stroked. Layout forwards to the base shape (`Docs/elements/Shape.md`, "Layout").

/// A shape with a translation offset transform applied to it.
@frozen
public struct OffsetShape<Content: Shape> {
    public var shape: Content
    public var offset: CGSize

    @inlinable public init(shape: Content, offset: CGSize) {
        self.shape = shape
        self.offset = offset
    }
}

extension OffsetShape: Shape {
    nonisolated public func path(in rect: CGRect) -> Path { shape.path(in: rect).offsetBy(dx: offset.width, dy: offset.height) }
    nonisolated public func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize { shape.sizeThatFits(proposal) }

    public typealias AnimatableData = AnimatablePair<Content.AnimatableData, CGSize.AnimatableData>
    public var animatableData: AnimatableData {
        get { .init(shape.animatableData, offset.animatableData) }
        set { shape.animatableData = newValue.first; offset.animatableData = newValue.second }
    }
}

extension OffsetShape: InsettableShape where Content: InsettableShape {
    nonisolated public func inset(by amount: CGFloat) -> OffsetShape<Content.InsetShape> {
        OffsetShape<Content.InsetShape>(shape: shape.inset(by: amount), offset: offset)
    }
}

extension OffsetShape: Sendable where Content: Sendable {}

/// A shape with a scale transform applied to it.
@frozen
public struct ScaledShape<Content: Shape> {
    public var shape: Content
    public var scale: CGSize
    public var anchor: UnitPoint

    @inlinable public init(shape: Content, scale: CGSize, anchor: UnitPoint = .center) {
        self.shape = shape
        self.scale = scale
        self.anchor = anchor
    }
}

extension ScaledShape: Shape {
    nonisolated public func path(in rect: CGRect) -> Path {
        let ax = rect.minX + rect.width * anchor.x, ay = rect.minY + rect.height * anchor.y
        let transform = CGAffineTransform(translationX: -ax, y: -ay)
            .concatenating(CGAffineTransform(scaleX: scale.width, y: scale.height))
            .concatenating(CGAffineTransform(translationX: ax, y: ay))
        return shape.path(in: rect).applying(transform)
    }
    nonisolated public func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize { shape.sizeThatFits(proposal) }

    public typealias AnimatableData = AnimatablePair<Content.AnimatableData, AnimatablePair<CGSize.AnimatableData, UnitPoint.AnimatableData>>
    public var animatableData: AnimatableData {
        get { .init(shape.animatableData, .init(scale.animatableData, anchor.animatableData)) }
        set {
            shape.animatableData = newValue.first
            scale.animatableData = newValue.second.first
            anchor.animatableData = newValue.second.second
        }
    }
}

extension ScaledShape: InsettableShape where Content: InsettableShape {
    nonisolated public func inset(by amount: CGFloat) -> ScaledShape<Content.InsetShape> {
        ScaledShape<Content.InsetShape>(shape: shape.inset(by: amount), scale: scale, anchor: anchor)
    }
}

extension ScaledShape: Sendable where Content: Sendable {}

/// A shape with a rotation transform applied to it.
@frozen
public struct RotatedShape<Content: Shape> {
    public var shape: Content
    public var angle: Angle
    public var anchor: UnitPoint

    @inlinable public init(shape: Content, angle: Angle, anchor: UnitPoint = .center) {
        self.shape = shape
        self.angle = angle
        self.anchor = anchor
    }
}

extension RotatedShape: Shape {
    nonisolated public func path(in rect: CGRect) -> Path {
        let ax = rect.minX + rect.width * anchor.x, ay = rect.minY + rect.height * anchor.y
        let transform = CGAffineTransform(translationX: -ax, y: -ay)
            .concatenating(CGAffineTransform(rotationAngle: angle.radians))
            .concatenating(CGAffineTransform(translationX: ax, y: ay))
        return shape.path(in: rect).applying(transform)
    }
    nonisolated public func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize { shape.sizeThatFits(proposal) }

    public typealias AnimatableData = AnimatablePair<Content.AnimatableData, AnimatablePair<Angle.AnimatableData, UnitPoint.AnimatableData>>
    public var animatableData: AnimatableData {
        get { .init(shape.animatableData, .init(angle.animatableData, anchor.animatableData)) }
        set {
            shape.animatableData = newValue.first
            angle.animatableData = newValue.second.first
            anchor.animatableData = newValue.second.second
        }
    }
}

extension RotatedShape: InsettableShape where Content: InsettableShape {
    nonisolated public func inset(by amount: CGFloat) -> RotatedShape<Content.InsetShape> {
        RotatedShape<Content.InsetShape>(shape: shape.inset(by: amount), angle: angle, anchor: anchor)
    }
}

extension RotatedShape: Sendable where Content: Sendable {}

/// A shape with an affine transform applied to it.
@frozen
public struct TransformedShape<Content: Shape> {
    public var shape: Content
    public var transform: CGAffineTransform

    @inlinable public init(shape: Content, transform: CGAffineTransform) {
        self.shape = shape
        self.transform = transform
    }
}

extension TransformedShape: Shape {
    nonisolated public func path(in rect: CGRect) -> Path { shape.path(in: rect).applying(transform) }
    nonisolated public func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize { shape.sizeThatFits(proposal) }

    public typealias AnimatableData = Content.AnimatableData
    public var animatableData: AnimatableData {
        get { shape.animatableData }
        set { shape.animatableData = newValue }
    }
}

extension TransformedShape: InsettableShape where Content: InsettableShape {
    nonisolated public func inset(by amount: CGFloat) -> TransformedShape<Content.InsetShape> {
        TransformedShape<Content.InsetShape>(shape: shape.inset(by: amount), transform: transform)
    }
}

extension TransformedShape: Sendable where Content: Sendable {}

/// A shape that draws its base from a rect of a fixed size at the frame's origin.
@frozen
public struct _SizedShape<Content: Shape> {
    public var shape: Content
    public var size: CGSize

    @inlinable public init(shape: Content, size: CGSize) {
        self.shape = shape
        self.size = size
    }
}

extension _SizedShape: Shape {
    nonisolated public func path(in rect: CGRect) -> Path { shape.path(in: CGRect(origin: rect.origin, size: size)) }
    nonisolated public func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize { shape.sizeThatFits(proposal) }

    public typealias AnimatableData = AnimatablePair<Content.AnimatableData, CGSize.AnimatableData>
    public var animatableData: AnimatableData {
        get { .init(shape.animatableData, size.animatableData) }
        set { shape.animatableData = newValue.first; size.animatableData = newValue.second }
    }
}

extension _SizedShape: Sendable where Content: Sendable {}

/// A shape trimmed to a fraction of its length.
@frozen
public struct _TrimmedShape<Content: Shape> {
    public var shape: Content
    public var startFraction: CGFloat
    public var endFraction: CGFloat

    @inlinable public init(shape: Content, startFraction: CGFloat, endFraction: CGFloat) {
        self.shape = shape
        self.startFraction = startFraction
        self.endFraction = endFraction
    }
}

extension _TrimmedShape: Shape {
    nonisolated public func path(in rect: CGRect) -> Path { shape.path(in: rect).trimmedPath(from: startFraction, to: endFraction) }
    nonisolated public func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize { shape.sizeThatFits(proposal) }

    public typealias AnimatableData = AnimatablePair<Content.AnimatableData, AnimatablePair<CGFloat, CGFloat>>
    public var animatableData: AnimatableData {
        get { .init(shape.animatableData, .init(startFraction, endFraction)) }
        set {
            shape.animatableData = newValue.first
            startFraction = newValue.second.first
            endFraction = newValue.second.second
        }
    }
}

extension _TrimmedShape: Sendable where Content: Sendable {}

/// The outline of a shape stroked with a style, as a shape. Painters stroke the base shape
/// natively; `path(in:)` is the approximate stroked outline (`Path.strokedPath`).
@frozen
public struct _StrokedShape<Content: Shape> {
    public var shape: Content
    public var style: StrokeStyle

    @inlinable public init(shape: Content, style: StrokeStyle) {
        self.shape = shape
        self.style = style
    }
}

extension _StrokedShape: Shape, _StrokeOutline {
    public static var role: ShapeRole { .stroke }

    nonisolated public func path(in rect: CGRect) -> Path { shape.path(in: rect).strokedPath(style) }
    nonisolated public func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize { shape.sizeThatFits(proposal) }

    nonisolated package func _basePath(in rect: CGRect) -> Path { shape.path(in: rect) }
    nonisolated package var _strokeStyle: StrokeStyle { style }

    public typealias AnimatableData = AnimatablePair<Content.AnimatableData, StrokeStyle.AnimatableData>
    public var animatableData: AnimatableData {
        get { .init(shape.animatableData, style.animatableData) }
        set { shape.animatableData = newValue.first; style.animatableData = newValue.second }
    }
}

extension _StrokedShape: Sendable where Content: Sendable {}
