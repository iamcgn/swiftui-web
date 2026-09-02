/// A 2D shape that you can use when drawing a view.
@MainActor @preconcurrency
public protocol Shape: Animatable, View {
    /// Describes this shape as a path within a rectangular frame of reference.
    nonisolated func path(in rect: CGRect) -> Path

    /// Returns the size of the view that will render the shape, given a proposed size.
    nonisolated func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize

    /// An indication of how to style a shape.
    static var role: ShapeRole { get }
}

/// Ways of styling shapes.
public enum ShapeRole: Hashable, Sendable {
    case fill, stroke, separator
}

extension Shape {
    public static var role: ShapeRole { .fill }

    nonisolated public func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    /// Fills this shape with a colour or gradient.
    nonisolated public func fill<S: ShapeStyle>(_ content: S, style: FillStyle = FillStyle()) -> some View {
        _ShapeView(shape: self, style: content, fillStyle: style)
    }

    /// Fills this shape with the foreground style.
    nonisolated public func fill(style: FillStyle = FillStyle()) -> some View {
        _ShapeView(shape: self, style: ForegroundStyle(), fillStyle: style)
    }

    /// Traces the outline of this shape with a colour or gradient.
    nonisolated public func stroke<S: ShapeStyle>(_ content: S, lineWidth: CGFloat = 1) -> some View {
        _StrokedShapeView(shape: self, style: content, lineWidth: lineWidth)
    }

    /// Traces the outline of this shape with the foreground style.
    nonisolated public func stroke(lineWidth: CGFloat = 1) -> some View {
        _StrokedShapeView(shape: self, style: ForegroundStyle(), lineWidth: lineWidth)
    }
}

/// A shape used as a view fills itself with the foreground style.
extension Shape {
    public var body: _ShapeView<Self, ForegroundStyle> {
        _ShapeView(shape: self, style: ForegroundStyle(), fillStyle: FillStyle())
    }
}

/// The style used when filling a path.
@frozen
public struct FillStyle: Equatable, Sendable {
    public var isEOFilled: Bool
    public var isAntialiased: Bool

    public init(eoFill: Bool = false, antialiased: Bool = true) {
        isEOFilled = eoFill
        isAntialiased = antialiased
    }
}

/// A shape filled with a style.
public struct _ShapeView<S: Shape, Style: ShapeStyle> {
    public var shape: S
    public var style: Style
    public var fillStyle: FillStyle

    public init(shape: S, style: Style, fillStyle: FillStyle) {
        self.shape = shape
        self.style = style
        self.fillStyle = fillStyle
    }
}

extension _ShapeView: View {
    public typealias Body = Never

    public static func _makeNode(_ context: _NodeContext<_ShapeView<S, Style>>) -> TypedNode<_ShapeView<S, Style>> {
        ShapeNode(context, shape: \.shape, style: { $0.style }, lineWidth: nil)
    }
}

/// A shape outlined with a style.
public struct _StrokedShapeView<S: Shape, Style: ShapeStyle> {
    public var shape: S
    public var style: Style
    public var lineWidth: CGFloat

    public init(shape: S, style: Style, lineWidth: CGFloat) {
        self.shape = shape
        self.style = style
        self.lineWidth = lineWidth
    }
}

extension _StrokedShapeView: View {
    public typealias Body = Never

    public static func _makeNode(_ context: _NodeContext<_StrokedShapeView<S, Style>>) -> TypedNode<_StrokedShapeView<S, Style>> {
        ShapeNode(context, shape: \.shape, style: { $0.style }, lineWidth: \.lineWidth)
    }
}

// MARK: - Built-in shapes

/// A rectangular shape aligned inside the frame of the view containing it.
@frozen
public struct Rectangle: Sendable {
    @inlinable public init() {}
}

extension Rectangle: Shape {
    nonisolated public func path(in rect: CGRect) -> Path { Path(rect) }
    public typealias AnimatableData = EmptyAnimatableData
}

/// A rectangular shape with rounded corners, aligned inside the frame of the view containing it.
@frozen
public struct RoundedRectangle: Sendable {
    public var cornerSize: CGSize
    public var style: RoundedCornerStyle

    @inlinable public init(cornerSize: CGSize, style: RoundedCornerStyle = .continuous) {
        self.cornerSize = cornerSize
        self.style = style
    }

    @inlinable public init(cornerRadius: CGFloat, style: RoundedCornerStyle = .continuous) {
        self.init(cornerSize: CGSize(width: cornerRadius, height: cornerRadius), style: style)
    }
}

extension RoundedRectangle: Shape {
    nonisolated public func path(in rect: CGRect) -> Path {
        Path(roundedRect: rect, cornerSize: cornerSize, style: style)
    }
    public typealias AnimatableData = CGSize.AnimatableData
    public var animatableData: AnimatableData {
        get { cornerSize.animatableData }
        set { cornerSize.animatableData = newValue }
    }
}

/// A circle centered on the frame of the view containing it.
@frozen
public struct Circle: Sendable {
    @inlinable public init() {}
}

extension Circle: Shape {
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
    public typealias AnimatableData = EmptyAnimatableData
}

/// An ellipse aligned inside the frame of the view containing it.
@frozen
public struct Ellipse: Sendable {
    @inlinable public init() {}
}

extension Ellipse: Shape {
    nonisolated public func path(in rect: CGRect) -> Path { Path(ellipseIn: rect) }
    public typealias AnimatableData = EmptyAnimatableData
}

/// A capsule shape aligned inside the frame of the view containing it.
@frozen
public struct Capsule: Sendable {
    public var style: RoundedCornerStyle
    @inlinable public init(style: RoundedCornerStyle = .continuous) { self.style = style }
}

extension Capsule: Shape {
    nonisolated public func path(in rect: CGRect) -> Path {
        let radius = min(rect.width, rect.height) / 2
        return Path(roundedRect: rect, cornerRadius: radius, style: style)
    }
    public typealias AnimatableData = EmptyAnimatableData
}
