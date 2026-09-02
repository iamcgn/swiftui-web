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

/// A shape type that is able to inset itself to produce another shape.
@MainActor @preconcurrency
public protocol InsettableShape: Shape {
    associatedtype InsetShape: InsettableShape

    /// Returns `self` inset by `amount`.
    nonisolated func inset(by amount: CGFloat) -> InsetShape
}

/// The properties of a stroke used to trace a path.
@frozen
public struct StrokeStyle: Equatable, Sendable {
    public var lineWidth: CGFloat
    public var lineCap: CGLineCap
    public var lineJoin: CGLineJoin
    public var miterLimit: CGFloat
    public var dash: [CGFloat]
    public var dashPhase: CGFloat

    nonisolated public init(lineWidth: CGFloat = 1, lineCap: CGLineCap = .butt, lineJoin: CGLineJoin = .miter,
                miterLimit: CGFloat = 10, dash: [CGFloat] = [], dashPhase: CGFloat = 0) {
        self.lineWidth = lineWidth
        self.lineCap = lineCap
        self.lineJoin = lineJoin
        self.miterLimit = miterLimit
        self.dash = dash
        self.dashPhase = dashPhase
    }

    /// Whether the style needs more than a plain line width (for painters and descriptions).
    package var isPlain: Bool { lineCap == .butt && lineJoin == .miter && miterLimit == 10 && dash.isEmpty }
}

extension StrokeStyle: Animatable {
    public typealias AnimatableData = AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>>
    public var animatableData: AnimatableData {
        get { .init(lineWidth, .init(miterLimit, dashPhase)) }
        set {
            lineWidth = newValue.first
            miterLimit = newValue.second.first
            dashPhase = newValue.second.second
        }
    }
}

/// The style used when filling a path.
@frozen
public struct FillStyle: Equatable, Sendable {
    public var isEOFilled: Bool
    public var isAntialiased: Bool

    nonisolated public init(eoFill: Bool = false, antialiased: Bool = true) {
        isEOFilled = eoFill
        isAntialiased = antialiased
    }
}

// MARK: - Shape API

extension Shape {
    public static var role: ShapeRole { .fill }

    nonisolated public func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    /// Fills this shape with a colour or gradient.
    nonisolated public func fill<S: ShapeStyle>(_ content: S, style: FillStyle = FillStyle()) -> FillShapeView<Self, S, EmptyView> {
        FillShapeView(shape: self, style: content, fillStyle: style, background: EmptyView())
    }

    /// Fills this shape with the foreground style.
    nonisolated public func fill(style: FillStyle = FillStyle()) -> FillShapeView<Self, ForegroundStyle, EmptyView> {
        FillShapeView(shape: self, style: ForegroundStyle(), fillStyle: style, background: EmptyView())
    }

    /// Traces the outline of this shape with a colour or gradient.
    nonisolated public func stroke<S: ShapeStyle>(_ content: S, style: StrokeStyle, antialiased: Bool = true) -> StrokeShapeView<Self, S, EmptyView> {
        StrokeShapeView(shape: self, style: content, strokeStyle: style, isAntialiased: antialiased, background: EmptyView())
    }

    /// Traces the outline of this shape with a colour or gradient, using a line width.
    nonisolated public func stroke<S: ShapeStyle>(_ content: S, lineWidth: CGFloat = 1, antialiased: Bool = true) -> StrokeShapeView<Self, S, EmptyView> {
        stroke(content, style: StrokeStyle(lineWidth: lineWidth), antialiased: antialiased)
    }

    /// Returns a shape that is the outline of this shape stroked with `style`.
    nonisolated public func stroke(style: StrokeStyle) -> _StrokedShape<Self> {
        _StrokedShape(shape: self, style: style)
    }

    /// Returns a shape that is the outline of this shape stroked with a line width.
    nonisolated public func stroke(lineWidth: CGFloat = 1) -> _StrokedShape<Self> {
        _StrokedShape(shape: self, style: StrokeStyle(lineWidth: lineWidth))
    }

    /// Trims this shape by a fractional amount of its length.
    nonisolated public func trim(from startFraction: CGFloat = 0, to endFraction: CGFloat = 1) -> _TrimmedShape<Self> {
        _TrimmedShape(shape: self, startFraction: startFraction, endFraction: endFraction)
    }

    /// Changes the relative position of this shape using the specified size.
    nonisolated public func offset(_ offset: CGSize) -> OffsetShape<Self> {
        OffsetShape(shape: self, offset: offset)
    }

    /// Changes the relative position of this shape using the specified point.
    nonisolated public func offset(_ offset: CGPoint) -> OffsetShape<Self> {
        OffsetShape(shape: self, offset: CGSize(width: offset.x, height: offset.y))
    }

    /// Changes the relative position of this shape using the specified distances.
    nonisolated public func offset(x: CGFloat = 0, y: CGFloat = 0) -> OffsetShape<Self> {
        OffsetShape(shape: self, offset: CGSize(width: x, height: y))
    }

    /// Scales this shape without changing its bounding frame.
    nonisolated public func scale(x: CGFloat = 1, y: CGFloat = 1, anchor: UnitPoint = .center) -> ScaledShape<Self> {
        ScaledShape(shape: self, scale: CGSize(width: x, height: y), anchor: anchor)
    }

    /// Scales this shape uniformly without changing its bounding frame.
    nonisolated public func scale(_ scale: CGFloat, anchor: UnitPoint = .center) -> ScaledShape<Self> {
        ScaledShape(shape: self, scale: CGSize(width: scale, height: scale), anchor: anchor)
    }

    /// Rotates this shape around an anchor point.
    nonisolated public func rotation(_ angle: Angle, anchor: UnitPoint = .center) -> RotatedShape<Self> {
        RotatedShape(shape: self, angle: angle, anchor: anchor)
    }

    /// Applies an affine transform to this shape.
    nonisolated public func transform(_ transform: CGAffineTransform) -> TransformedShape<Self> {
        TransformedShape(shape: self, transform: transform)
    }

    /// Returns a version of this shape that creates its path from a rect of the given size.
    nonisolated public func size(_ size: CGSize) -> _SizedShape<Self> {
        _SizedShape(shape: self, size: size)
    }

    /// Returns a version of this shape that creates its path from a rect of the given size.
    nonisolated public func size(width: CGFloat, height: CGFloat) -> _SizedShape<Self> {
        _SizedShape(shape: self, size: CGSize(width: width, height: height))
    }
}

/// A shape used as a view fills itself with the foreground style.
extension Shape {
    public var body: _ShapeView<Self, ForegroundStyle> {
        _ShapeView(shape: self, style: ForegroundStyle())
    }
}

extension InsettableShape {
    /// Traces the inner edge of this shape with a colour or gradient.
    nonisolated public func strokeBorder<S: ShapeStyle>(_ content: S, style: StrokeStyle, antialiased: Bool = true) -> StrokeBorderShapeView<Self, S, EmptyView> {
        StrokeBorderShapeView(shape: self, style: content, strokeStyle: style, isAntialiased: antialiased, background: EmptyView())
    }

    /// Traces the inner edge of this shape with the foreground style.
    nonisolated public func strokeBorder(style: StrokeStyle, antialiased: Bool = true) -> StrokeBorderShapeView<Self, ForegroundStyle, EmptyView> {
        strokeBorder(ForegroundStyle(), style: style, antialiased: antialiased)
    }

    /// Traces the inner edge of this shape with a colour or gradient, using a line width.
    nonisolated public func strokeBorder<S: ShapeStyle>(_ content: S, lineWidth: CGFloat = 1, antialiased: Bool = true) -> StrokeBorderShapeView<Self, S, EmptyView> {
        strokeBorder(content, style: StrokeStyle(lineWidth: lineWidth), antialiased: antialiased)
    }

    /// Traces the inner edge of this shape with the foreground style, using a line width.
    nonisolated public func strokeBorder(lineWidth: CGFloat = 1, antialiased: Bool = true) -> StrokeBorderShapeView<Self, ForegroundStyle, EmptyView> {
        strokeBorder(ForegroundStyle(), style: StrokeStyle(lineWidth: lineWidth), antialiased: antialiased)
    }
}

// MARK: - Shape views

/// A view that provides a shape that you can use for drawing operations.
@MainActor @preconcurrency
public protocol ShapeView: View {
    associatedtype Content: Shape
    var shape: Content { get }
}

extension ShapeView {
    /// Fills the shape with a colour or gradient, behind this view's drawing.
    public func fill<S: ShapeStyle>(_ content: S, style: FillStyle = FillStyle()) -> FillShapeView<Content, S, Self> {
        FillShapeView(shape: shape, style: content, fillStyle: style, background: self)
    }

    /// Fills the shape with the foreground style, behind this view's drawing.
    public func fill(style: FillStyle = FillStyle()) -> FillShapeView<Content, ForegroundStyle, Self> {
        FillShapeView(shape: shape, style: ForegroundStyle(), fillStyle: style, background: self)
    }

    /// Traces the shape's outline with a colour or gradient, in front of this view's drawing.
    public func stroke<S: ShapeStyle>(_ content: S, style: StrokeStyle, antialiased: Bool = true) -> StrokeShapeView<Content, S, Self> {
        StrokeShapeView(shape: shape, style: content, strokeStyle: style, isAntialiased: antialiased, background: self)
    }

    /// Traces the shape's outline with a colour or gradient, using a line width.
    public func stroke<S: ShapeStyle>(_ content: S, lineWidth: CGFloat = 1, antialiased: Bool = true) -> StrokeShapeView<Content, S, Self> {
        stroke(content, style: StrokeStyle(lineWidth: lineWidth), antialiased: antialiased)
    }

}

extension ShapeView where Content: InsettableShape {
    public func strokeBorder<S: ShapeStyle>(_ content: S, style: StrokeStyle, antialiased: Bool = true) -> StrokeBorderShapeView<Content, S, Self> {
        StrokeBorderShapeView(shape: shape, style: content, strokeStyle: style, isAntialiased: antialiased, background: self)
    }

    public func strokeBorder(style: StrokeStyle, antialiased: Bool = true) -> StrokeBorderShapeView<Content, ForegroundStyle, Self> {
        strokeBorder(ForegroundStyle(), style: style, antialiased: antialiased)
    }

    public func strokeBorder<S: ShapeStyle>(_ content: S, lineWidth: CGFloat = 1, antialiased: Bool = true) -> StrokeBorderShapeView<Content, S, Self> {
        strokeBorder(content, style: StrokeStyle(lineWidth: lineWidth), antialiased: antialiased)
    }

    public func strokeBorder(lineWidth: CGFloat = 1, antialiased: Bool = true) -> StrokeBorderShapeView<Content, ForegroundStyle, Self> {
        strokeBorder(ForegroundStyle(), style: StrokeStyle(lineWidth: lineWidth), antialiased: antialiased)
    }
}

/// A view that paints a shape; the runtime's `ShapeNode` sizes and paints through it.
@MainActor
package protocol _ShapePainting: View {
    func _shapeSizeThatFits(_ proposal: ProposedViewSize) -> CGSize
    /// Emits the drawing into `bounds` (absolute, pixel aligned).
    func _paintShape(in bounds: CGRect, environment: EnvironmentValues, into list: inout DisplayList)
}

extension _ShapePainting {
    public static func _makeNode(_ context: _NodeContext<Self>) -> TypedNode<Self> {
        ShapeNode(context)
    }
}

/// Paints `background` first when it is itself a shape view (`Circle().fill(.red).stroke(.blue)`).
@MainActor
private func _paintBackground<B: View>(_ background: B, in bounds: CGRect, environment: EnvironmentValues, into list: inout DisplayList) {
    if let painter = background as? any _ShapePainting {
        painter._paintShape(in: bounds, environment: environment, into: &list)
    }
}

/// A shape drawn with the foreground style (the view a bare shape becomes).
public struct _ShapeView<Content: Shape, Style: ShapeStyle> {
    public var shape: Content
    public var style: Style

    public init(shape: Content, style: Style) {
        self.shape = shape
        self.style = style
    }

}

extension _ShapeView: ShapeView, _ShapePainting {
    public typealias Body = Never

    package func _shapeSizeThatFits(_ proposal: ProposedViewSize) -> CGSize { shape.sizeThatFits(proposal) }

    package func _paintShape(in bounds: CGRect, environment: EnvironmentValues, into list: inout DisplayList) {
        let color = style.resolveColor(in: environment)
        guard color.alpha > 0 else { return }
        list.append(_fillCommand(shape, in: bounds, color: color, fillStyle: FillStyle()))
    }
}

/// A shape filled with a style, over an optional background shape view.
public struct FillShapeView<Content: Shape, Style: ShapeStyle, Background: View> {
    public var shape: Content
    public var style: Style
    public var fillStyle: FillStyle
    public var background: Background

    public init(shape: Content, style: Style, fillStyle: FillStyle, background: Background) {
        self.shape = shape
        self.style = style
        self.fillStyle = fillStyle
        self.background = background
    }

}

extension FillShapeView: ShapeView, _ShapePainting {
    public typealias Body = Never

    package func _shapeSizeThatFits(_ proposal: ProposedViewSize) -> CGSize { shape.sizeThatFits(proposal) }

    package func _paintShape(in bounds: CGRect, environment: EnvironmentValues, into list: inout DisplayList) {
        _paintBackground(background, in: bounds, environment: environment, into: &list)
        let color = style.resolveColor(in: environment)
        guard color.alpha > 0 else { return }
        list.append(_fillCommand(shape, in: bounds, color: color, fillStyle: fillStyle))
    }
}

/// A shape stroked with a style, over an optional background shape view.
public struct StrokeShapeView<Content: Shape, Style: ShapeStyle, Background: View> {
    public var shape: Content
    public var style: Style
    public var strokeStyle: StrokeStyle
    public var isAntialiased: Bool
    public var background: Background

    public init(shape: Content, style: Style, strokeStyle: StrokeStyle, isAntialiased: Bool, background: Background) {
        self.shape = shape
        self.style = style
        self.strokeStyle = strokeStyle
        self.isAntialiased = isAntialiased
        self.background = background
    }

}

extension StrokeShapeView: ShapeView, _ShapePainting {
    public typealias Body = Never

    package func _shapeSizeThatFits(_ proposal: ProposedViewSize) -> CGSize { shape.sizeThatFits(proposal) }

    package func _paintShape(in bounds: CGRect, environment: EnvironmentValues, into list: inout DisplayList) {
        _paintBackground(background, in: bounds, environment: environment, into: &list)
        let color = style.resolveColor(in: environment)
        guard color.alpha > 0, strokeStyle.lineWidth > 0 else { return }
        list.append(.strokePath(shape.path(in: bounds), style: strokeStyle, color))
    }
}

/// A shape whose inner edge is stroked with a style, over an optional background shape view.
public struct StrokeBorderShapeView<Content: InsettableShape, Style: ShapeStyle, Background: View> {
    public var shape: Content
    public var style: Style
    public var strokeStyle: StrokeStyle
    public var isAntialiased: Bool
    public var background: Background

    public init(shape: Content, style: Style, strokeStyle: StrokeStyle, isAntialiased: Bool, background: Background) {
        self.shape = shape
        self.style = style
        self.strokeStyle = strokeStyle
        self.isAntialiased = isAntialiased
        self.background = background
    }

}

extension StrokeBorderShapeView: ShapeView, _ShapePainting {
    public typealias Body = Never

    package func _shapeSizeThatFits(_ proposal: ProposedViewSize) -> CGSize { shape.sizeThatFits(proposal) }

    package func _paintShape(in bounds: CGRect, environment: EnvironmentValues, into list: inout DisplayList) {
        _paintBackground(background, in: bounds, environment: environment, into: &list)
        let color = style.resolveColor(in: environment)
        guard color.alpha > 0, strokeStyle.lineWidth > 0 else { return }
        list.append(.strokePath(shape.inset(by: strokeStyle.lineWidth / 2).path(in: bounds), style: strokeStyle, color))
    }
}

/// A shape that is the stroked outline of another; painters stroke the base natively.
package protocol _StrokeOutline {
    nonisolated func _basePath(in rect: CGRect) -> Path
    nonisolated var _strokeStyle: StrokeStyle { get }
}

/// The cheapest command that fills `shape` in `bounds`.
@MainActor
package func _fillCommand<S: Shape>(_ shape: S, in bounds: CGRect, color: RGBA, fillStyle: FillStyle = FillStyle()) -> DisplayCommand {
    if let outline = shape as? any _StrokeOutline {
        return .strokePath(outline._basePath(in: bounds), style: outline._strokeStyle, color)
    }
    if !fillStyle.isEOFilled {
        if S.self == Rectangle.self {
            return .fillRect(bounds, color)
        }
        if let rounded = shape as? RoundedRectangle, rounded.cornerSize.width == rounded.cornerSize.height, rounded.style == .circular {
            return .fillRRect(bounds, cornerRadius: rounded.cornerSize.width, color)
        }
        if let capsule = shape as? Capsule, capsule.style == .circular {
            return .fillRRect(bounds, cornerRadius: min(bounds.width, bounds.height) / 2, color)
        }
    }
    return .fillPath(shape.path(in: bounds), color, eoFill: fillStyle.isEOFilled)
}

@MainActor
package func _clipCommand<S: Shape>(_ shape: S, in bounds: CGRect, fillStyle: FillStyle = FillStyle()) -> DisplayCommand {
    if !fillStyle.isEOFilled {
        if S.self == Rectangle.self {
            return .clipRect(bounds)
        }
        if let rounded = shape as? RoundedRectangle, rounded.cornerSize.width == rounded.cornerSize.height, rounded.style == .circular {
            return .clipRRect(bounds, cornerRadius: rounded.cornerSize.width)
        }
    }
    return .clipPath(shape.path(in: bounds), eoFill: fillStyle.isEOFilled)
}
