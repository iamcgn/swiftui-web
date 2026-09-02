// The built-in shapes and their insets. Path element order matches SwiftUI's (measured in
// `Docs/elements/Shape.md`) so `trim` and `description` agree with it.

/// Insetting hook: the built-ins define what "inset" means (rounded rectangles also shrink their
/// corner radii, as SwiftUI does).
public protocol _InsetPathProviding: Shape {
    nonisolated func _insetPath(in rect: CGRect, by amount: CGFloat) -> Path
}

extension _InsetPathProviding {
    nonisolated public func _insetPath(in rect: CGRect, by amount: CGFloat) -> Path {
        path(in: rect.insetBy(dx: amount, dy: amount))
    }
}

/// A built-in shape inset by an amount; insetting again accumulates. Lays out like a plain
/// shape (an inset circle takes the whole proposal, measured in `Docs/elements/Shape.md`).
@frozen
public struct _InsetShape<Base: _InsetPathProviding> {
    public var shape: Base
    public var amount: CGFloat

    @inlinable public init(shape: Base, amount: CGFloat) {
        self.shape = shape
        self.amount = amount
    }
}

extension _InsetShape: InsettableShape, _InsetPathProviding {
    nonisolated public func path(in rect: CGRect) -> Path { shape._insetPath(in: rect, by: amount) }
    nonisolated public func _insetPath(in rect: CGRect, by extra: CGFloat) -> Path { shape._insetPath(in: rect, by: amount + extra) }
    nonisolated public func inset(by extra: CGFloat) -> _InsetShape<Base> { _InsetShape(shape: shape, amount: amount + extra) }

    public typealias AnimatableData = AnimatablePair<Base.AnimatableData, CGFloat>
    public var animatableData: AnimatableData {
        get { .init(shape.animatableData, amount) }
        set { shape.animatableData = newValue.first; amount = newValue.second }
    }
}

extension _InsetShape: Sendable where Base: Sendable {}

// MARK: - Rectangle

/// A rectangular shape aligned inside the frame of the view containing it.
@frozen
public struct Rectangle: Sendable {
    @inlinable nonisolated public init() {}
}

extension Rectangle: InsettableShape, _InsetPathProviding {
    nonisolated public func path(in rect: CGRect) -> Path { Path(rect) }
    nonisolated public func inset(by amount: CGFloat) -> _InsetShape<Rectangle> { _InsetShape(shape: self, amount: amount) }
    public typealias AnimatableData = EmptyAnimatableData
}

// MARK: - RoundedRectangle

/// A rectangular shape with rounded corners, aligned inside the frame of the view containing it.
@frozen
public struct RoundedRectangle: Sendable {
    public var cornerSize: CGSize
    public var style: RoundedCornerStyle

    @inlinable nonisolated public init(cornerSize: CGSize, style: RoundedCornerStyle = .continuous) {
        self.cornerSize = cornerSize
        self.style = style
    }

    @inlinable nonisolated public init(cornerRadius: CGFloat, style: RoundedCornerStyle = .continuous) {
        self.init(cornerSize: CGSize(width: cornerRadius, height: cornerRadius), style: style)
    }
}

extension RoundedRectangle: InsettableShape, _InsetPathProviding {
    nonisolated public func path(in rect: CGRect) -> Path {
        Path(roundedRect: rect, cornerSize: cornerSize, style: style)
    }

    /// Insetting shrinks the corner radii by the same amount.
    nonisolated public func _insetPath(in rect: CGRect, by amount: CGFloat) -> Path {
        let size = CGSize(width: max(0, cornerSize.width - amount), height: max(0, cornerSize.height - amount))
        return Path(roundedRect: rect.insetBy(dx: amount, dy: amount), cornerSize: size, style: style)
    }

    nonisolated public func inset(by amount: CGFloat) -> _InsetShape<RoundedRectangle> { _InsetShape(shape: self, amount: amount) }

    public typealias AnimatableData = CGSize.AnimatableData
    public var animatableData: AnimatableData {
        get { cornerSize.animatableData }
        set { cornerSize.animatableData = newValue }
    }
}

// MARK: - UnevenRoundedRectangle

/// A rectangular shape with rounded corners of different radii.
@frozen
public struct UnevenRoundedRectangle: Sendable {
    public var cornerRadii: RectangleCornerRadii
    public var style: RoundedCornerStyle

    @inlinable nonisolated public init(cornerRadii: RectangleCornerRadii, style: RoundedCornerStyle = .continuous) {
        self.cornerRadii = cornerRadii
        self.style = style
    }

    @inlinable nonisolated public init(topLeadingRadius: CGFloat = 0, bottomLeadingRadius: CGFloat = 0, bottomTrailingRadius: CGFloat = 0,
                           topTrailingRadius: CGFloat = 0, style: RoundedCornerStyle = .continuous) {
        self.init(cornerRadii: RectangleCornerRadii(topLeading: topLeadingRadius, bottomLeading: bottomLeadingRadius,
                                                    bottomTrailing: bottomTrailingRadius, topTrailing: topTrailingRadius), style: style)
    }
}

extension UnevenRoundedRectangle: InsettableShape, _InsetPathProviding {
    nonisolated public func path(in rect: CGRect) -> Path {
        Path(roundedRect: rect, cornerRadii: cornerRadii, style: style)
    }

    nonisolated public func _insetPath(in rect: CGRect, by amount: CGFloat) -> Path {
        let r = cornerRadii
        let radii = RectangleCornerRadii(topLeading: max(0, r.topLeading - amount), bottomLeading: max(0, r.bottomLeading - amount),
                                         bottomTrailing: max(0, r.bottomTrailing - amount), topTrailing: max(0, r.topTrailing - amount))
        return Path(roundedRect: rect.insetBy(dx: amount, dy: amount), cornerRadii: radii, style: style)
    }

    nonisolated public func inset(by amount: CGFloat) -> _InsetShape<UnevenRoundedRectangle> { _InsetShape(shape: self, amount: amount) }

    public typealias AnimatableData = RectangleCornerRadii.AnimatableData
    public var animatableData: AnimatableData {
        get { cornerRadii.animatableData }
        set { cornerRadii.animatableData = newValue }
    }
}

// MARK: - Circle, Ellipse, Capsule

/// A circle centered on the frame of the view containing it.
@frozen
public struct Circle: Sendable {
    @inlinable nonisolated public init() {}
}

extension Circle: InsettableShape, _InsetPathProviding {
    nonisolated public func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let square = CGRect(x: rect.midX - side / 2, y: rect.midY - side / 2, width: side, height: side)
        return Path(ellipseIn: square)
    }

    /// A circle is as wide as it is tall: the smaller proposed dimension.
    nonisolated public func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
        let size = proposal.replacingUnspecifiedDimensions()
        let side = min(size.width, size.height)
        return CGSize(width: side, height: side)
    }

    nonisolated public func inset(by amount: CGFloat) -> _InsetShape<Circle> { _InsetShape(shape: self, amount: amount) }
    public typealias AnimatableData = EmptyAnimatableData
}

/// An ellipse aligned inside the frame of the view containing it.
@frozen
public struct Ellipse: Sendable {
    @inlinable nonisolated public init() {}
}

extension Ellipse: InsettableShape, _InsetPathProviding {
    nonisolated public func path(in rect: CGRect) -> Path { Path(ellipseIn: rect) }
    nonisolated public func inset(by amount: CGFloat) -> _InsetShape<Ellipse> { _InsetShape(shape: self, amount: amount) }
    public typealias AnimatableData = EmptyAnimatableData
}

/// A capsule shape aligned inside the frame of the view containing it.
@frozen
public struct Capsule: Sendable {
    public var style: RoundedCornerStyle
    @inlinable nonisolated public init(style: RoundedCornerStyle = .continuous) { self.style = style }
}

extension Capsule: InsettableShape, _InsetPathProviding {
    nonisolated public func path(in rect: CGRect) -> Path {
        let radius = min(rect.width, rect.height) / 2
        return Path(roundedRect: rect, cornerRadius: radius, style: style)
    }
    nonisolated public func inset(by amount: CGFloat) -> _InsetShape<Capsule> { _InsetShape(shape: self, amount: amount) }
    public typealias AnimatableData = EmptyAnimatableData
}

// MARK: - ContainerRelativeShape, AnyShape

/// A shape that is replaced by an inset version of the current container shape. Without a
/// container shape it is a rectangle (approximate: SwiftUI containers are not modelled).
@frozen
public struct ContainerRelativeShape: Sendable {
    @inlinable nonisolated public init() {}
}

extension ContainerRelativeShape: InsettableShape, _InsetPathProviding {
    nonisolated public func path(in rect: CGRect) -> Path { Path(rect) }
    nonisolated public func inset(by amount: CGFloat) -> _InsetShape<ContainerRelativeShape> { _InsetShape(shape: self, amount: amount) }
    public typealias AnimatableData = EmptyAnimatableData
}

/// A type-erased shape value.
public struct AnyShape: @unchecked Sendable {
    private let base: any Shape

    public init<S: Shape>(_ shape: S) {
        base = shape
    }
}

extension AnyShape: Shape {
    nonisolated public func path(in rect: CGRect) -> Path { base.path(in: rect) }
    nonisolated public func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize { base.sizeThatFits(proposal) }
    public typealias AnimatableData = EmptyAnimatableData
}
