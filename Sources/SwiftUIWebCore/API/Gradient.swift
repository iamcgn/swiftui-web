/// Gradients as shape styles (`Docs/elements/Gradient.md`): linear, radial and angular gradients
/// resolve to a `DisplayGradient` over the shape's bounds and paint through the display list's
/// gradient fill and stroke ops.

/// A color gradient represented as an array of color stops, each having a parametric location value.
public struct Gradient: Equatable, Sendable {
    /// One color stop in the gradient.
    public struct Stop: Equatable, Sendable {
        public var color: Color
        public var location: CGFloat
        public init(color: Color, location: CGFloat) {
            self.color = color
            self.location = location
        }
    }

    public var stops: [Stop]

    /// Creates a gradient from an array of color stops.
    public init(stops: [Stop]) { self.stops = stops }

    /// Creates a gradient from an array of colors, evenly spaced.
    public init(colors: [Color]) {
        let count = max(colors.count - 1, 1)
        stops = colors.enumerated().map { Stop(color: $1, location: colors.count == 1 ? 0 : CGFloat($0) / CGFloat(count)) }
    }
}

/// A style that resolves to a display-list gradient over the painted bounds.
@MainActor
package protocol _GradientStyle: ShapeStyle {
    func _resolveGradient(in bounds: CGRect, environment: EnvironmentValues) -> DisplayGradient
    /// Fills `path` (absolute) with the style resolved over `bounds`; a mesh clips and draws a
    /// bitmap instead of a gradient op.
    func _fill(_ path: Path, in bounds: CGRect, eoFill: Bool, environment: EnvironmentValues, scale: CGFloat, into list: inout DisplayList)
    func _stroke(_ path: Path, style: StrokeStyle, in bounds: CGRect, environment: EnvironmentValues, scale: CGFloat, into list: inout DisplayList)
}

extension _GradientStyle {
    package func _fill(_ path: Path, in bounds: CGRect, eoFill: Bool, environment: EnvironmentValues, scale: CGFloat, into list: inout DisplayList) {
        list.append(.fillGradient(path, _resolveGradient(in: bounds, environment: environment), eoFill: eoFill))
    }

    package func _stroke(_ path: Path, style: StrokeStyle, in bounds: CGRect, environment: EnvironmentValues, scale: CGFloat, into list: inout DisplayList) {
        list.append(.strokeGradient(path, style: style, _resolveGradient(in: bounds, environment: environment)))
    }
}

/// A gradient style modified by `opacity`, a hierarchical level or `in(_:)`: the stops' alpha is
/// multiplied, the frame replaced by the rect (in the view's space). Measured 2026-10-11:
/// `.secondary` … `.quinary` on a gradient multiply alpha by 0.5, 0.25, 0.18 and 0.18.
public struct _ModifiedGradientStyle<Base: ShapeStyle>: ShapeStyle, _ModifiedStyle {
    package var base: Base
    package var alpha: Double = 1
    package var rect: CGRect?

    package var _alpha: Double { alpha }
    package func _resolveBaseColor(in environment: EnvironmentValues) -> RGBA { base.resolveColor(in: environment) }
}

/// A style wrapping another with an alpha (`resolveColor` unwraps it).
package protocol _ModifiedStyle {
    var _alpha: Double { get }
    func _resolveBaseColor(in environment: EnvironmentValues) -> RGBA
}

extension _ModifiedGradientStyle: _GradientStyle {
    package func _resolveGradient(in bounds: CGRect, environment: EnvironmentValues) -> DisplayGradient {
        var gradient = (base as? any _GradientStyle)?._resolveGradient(in: frame(in: bounds), environment: environment)
            ?? DisplayGradient(kind: .linear(start: bounds.origin, end: bounds.origin), stops: [DisplayGradient.Stop(location: 0, color: base.resolveColor(in: environment))])
        if alpha != 1 { gradient.stops = gradient.stops.map { DisplayGradient.Stop(location: $0.location, color: $0.color.multiplyingAlpha(by: alpha)) } }
        return gradient
    }

    package func _fill(_ path: Path, in bounds: CGRect, eoFill: Bool, environment: EnvironmentValues, scale: CGFloat, into list: inout DisplayList) {
        guard let mesh = base as? MeshGradient else {
            list.append(.fillGradient(path, _resolveGradient(in: bounds, environment: environment), eoFill: eoFill))
            return
        }
        mesh._fill(path, in: frame(in: bounds), eoFill: eoFill, environment: environment, scale: scale, alpha: alpha, into: &list)
    }

    package func _stroke(_ path: Path, style: StrokeStyle, in bounds: CGRect, environment: EnvironmentValues, scale: CGFloat, into list: inout DisplayList) {
        guard let mesh = base as? MeshGradient else {
            list.append(.strokeGradient(path, style: style, _resolveGradient(in: bounds, environment: environment)))
            return
        }
        mesh._stroke(path, style: style, in: frame(in: bounds), environment: environment, scale: scale, alpha: alpha, into: &list)
    }

    private func frame(in bounds: CGRect) -> CGRect {
        guard let rect else { return bounds }
        return rect.offsetBy(dx: bounds.minX, dy: bounds.minY)
    }
}

extension ShapeStyle {
    /// The style at an opacity (a colour's own `opacity` returns a colour).
    nonisolated public func opacity(_ opacity: Double) -> _ModifiedGradientStyle<Self> {
        _ModifiedGradientStyle(base: self, alpha: opacity)
    }

    /// The style resolved against `rect` (in the view's coordinate space) instead of the view's frame.
    nonisolated public func `in`(_ rect: CGRect) -> _ModifiedGradientStyle<Self> {
        _ModifiedGradientStyle(base: self, rect: rect)
    }

    nonisolated public var secondary: _ModifiedGradientStyle<Self> { _ModifiedGradientStyle(base: self, alpha: 0.5) }
    nonisolated public var tertiary: _ModifiedGradientStyle<Self> { _ModifiedGradientStyle(base: self, alpha: 0.25) }
    nonisolated public var quaternary: _ModifiedGradientStyle<Self> { _ModifiedGradientStyle(base: self, alpha: 0.18) }
    nonisolated public var quinary: _ModifiedGradientStyle<Self> { _ModifiedGradientStyle(base: self, alpha: 0.18) }
}

extension _ModifiedGradientStyle {
    nonisolated public func opacity(_ opacity: Double) -> _ModifiedGradientStyle<Base> { _ModifiedGradientStyle(base: base, alpha: alpha * opacity, rect: rect) }
    nonisolated public func `in`(_ rect: CGRect) -> _ModifiedGradientStyle<Base> { _ModifiedGradientStyle(base: base, alpha: alpha, rect: rect) }
    nonisolated public var secondary: _ModifiedGradientStyle<Base> { opacity(0.5) }
    nonisolated public var tertiary: _ModifiedGradientStyle<Base> { opacity(0.25) }
    nonisolated public var quaternary: _ModifiedGradientStyle<Base> { opacity(0.18) }
    nonisolated public var quinary: _ModifiedGradientStyle<Base> { opacity(0.18) }
}

/// A type-erased shape style.
public struct AnyShapeStyle: ShapeStyle {
    package let base: any ShapeStyle
    public init<S: ShapeStyle>(_ style: S) { base = style }
}

extension AnyShapeStyle: _GradientStyle {
    package func _resolveGradient(in bounds: CGRect, environment: EnvironmentValues) -> DisplayGradient {
        (base as? any _GradientStyle)?._resolveGradient(in: bounds, environment: environment)
            ?? DisplayGradient(kind: .linear(start: bounds.origin, end: bounds.origin), stops: [DisplayGradient.Stop(location: 0, color: base.resolveColor(in: environment))])
    }
    package func _fill(_ path: Path, in bounds: CGRect, eoFill: Bool, environment: EnvironmentValues, scale: CGFloat, into list: inout DisplayList) {
        if let gradient = base as? any _GradientStyle {
            gradient._fill(path, in: bounds, eoFill: eoFill, environment: environment, scale: scale, into: &list)
        } else {
            list.append(.fillPath(path, base.resolveColor(in: environment), eoFill: eoFill))
        }
    }
    package func _stroke(_ path: Path, style: StrokeStyle, in bounds: CGRect, environment: EnvironmentValues, scale: CGFloat, into list: inout DisplayList) {
        if let gradient = base as? any _GradientStyle {
            gradient._stroke(path, style: style, in: bounds, environment: environment, scale: scale, into: &list)
        } else {
            list.append(.strokePath(path, style: style, base.resolveColor(in: environment)))
        }
    }
}

extension Gradient {
    /// The stops for the display list. SwiftUI blends gradients perceptually (measured against
    /// Apple's pixels: Oklab reproduces the midpoint of red → blue exactly, sRGB blending is far
    /// off), and Canvas2D blends in sRGB, so each pair of stops is expanded into sub-stops
    /// interpolated in Oklab that the painter joins with short sRGB segments.
    @MainActor package func resolvedStops(in environment: EnvironmentValues) -> [DisplayGradient.Stop] {
        let resolved = stops.map { DisplayGradient.Stop(location: Double(min(max($0.location, 0), 1)), color: $0.color.resolve(in: environment)) }
        guard resolved.count > 1 else { return resolved }
        if let cached = Self.subdividedStops[resolved] { return cached }
        let result = Self.subdivide(resolved)
        if Self.subdividedStops.count >= 256 { Self.subdividedStops.removeAll(keepingCapacity: true) }
        Self.subdividedStops[resolved] = result
        return result
    }

    /// The subdivided stops by their resolved stops: a page's gradients repeat, and every paint
    /// of one would otherwise mix its stops in Oklab (powers and logarithms per step) again.
    @MainActor private static var subdividedStops: [[DisplayGradient.Stop]: [DisplayGradient.Stop]] = [:]

    private static func subdivide(_ resolved: [DisplayGradient.Stop]) -> [DisplayGradient.Stop] {
        var result: [DisplayGradient.Stop] = [resolved[0]]
        for (a, b) in zip(resolved, resolved.dropFirst()) {
            let steps = Self.subdivisions
            if a.color == b.color || b.location <= a.location {
                result.append(b)
                continue
            }
            let la = _Oklab(a.color), lb = _Oklab(b.color)
            for i in 1...steps {
                let t = Double(i) / Double(steps)
                let color = i == steps ? b.color : la.mixed(with: lb, t: t).rgba(alpha: a.color.alpha + (b.color.alpha - a.color.alpha) * t)
                result.append(DisplayGradient.Stop(location: a.location + (b.location - a.location) * t, color: color))
            }
        }
        return result
    }

    package static let subdivisions = 8
}

/// A linear gradient: colors along an axis from a start point to an end point of the bounds.
public struct LinearGradient: ShapeStyle, Sendable {
    package let gradient: Gradient
    package let startPoint: UnitPoint
    package let endPoint: UnitPoint

    public init(gradient: Gradient, startPoint: UnitPoint, endPoint: UnitPoint) {
        self.gradient = gradient
        self.startPoint = startPoint
        self.endPoint = endPoint
    }

    public init(colors: [Color], startPoint: UnitPoint, endPoint: UnitPoint) {
        self.init(gradient: Gradient(colors: colors), startPoint: startPoint, endPoint: endPoint)
    }

    public init(stops: [Gradient.Stop], startPoint: UnitPoint, endPoint: UnitPoint) {
        self.init(gradient: Gradient(stops: stops), startPoint: startPoint, endPoint: endPoint)
    }
}

extension UnitPoint {
    /// The point in `bounds`; a right-to-left layout mirrors it (`.leading` is the right edge:
    /// `layout/rtl-shapes`, macOS 27).
    package func _resolve(in bounds: CGRect, environment: EnvironmentValues) -> CGPoint {
        let fx = environment.layoutDirection == .rightToLeft ? 1 - x : x
        return CGPoint(x: bounds.minX + bounds.width * fx, y: bounds.minY + bounds.height * y)
    }
}

extension LinearGradient: _GradientStyle {
    package func _resolveGradient(in bounds: CGRect, environment: EnvironmentValues) -> DisplayGradient {
        DisplayGradient(kind: .linear(start: startPoint._resolve(in: bounds, environment: environment), end: endPoint._resolve(in: bounds, environment: environment)),
                        stops: gradient.resolvedStops(in: environment))
    }
}

/// A radial gradient: colors from a start radius to an end radius around a centre.
public struct RadialGradient: ShapeStyle, Sendable {
    package let gradient: Gradient
    package let center: UnitPoint
    package let startRadius: CGFloat
    package let endRadius: CGFloat

    public init(gradient: Gradient, center: UnitPoint, startRadius: CGFloat, endRadius: CGFloat) {
        self.gradient = gradient
        self.center = center
        self.startRadius = startRadius
        self.endRadius = endRadius
    }

    public init(colors: [Color], center: UnitPoint, startRadius: CGFloat, endRadius: CGFloat) {
        self.init(gradient: Gradient(colors: colors), center: center, startRadius: startRadius, endRadius: endRadius)
    }

    public init(stops: [Gradient.Stop], center: UnitPoint, startRadius: CGFloat, endRadius: CGFloat) {
        self.init(gradient: Gradient(stops: stops), center: center, startRadius: startRadius, endRadius: endRadius)
    }
}

extension RadialGradient: _GradientStyle {
    package func _resolveGradient(in bounds: CGRect, environment: EnvironmentValues) -> DisplayGradient {
        let c = center._resolve(in: bounds, environment: environment)
        return DisplayGradient(kind: .radial(center: c, startRadius: startRadius, endRadius: endRadius), stops: gradient.resolvedStops(in: environment))
    }
}

/// An elliptical gradient: a radial gradient whose radii are fractions of the bounds' width and
/// height (an end fraction of 0.5 touches all four edges; measured 2026-10-11).
public struct EllipticalGradient: ShapeStyle, Sendable {
    package let gradient: Gradient
    package let center: UnitPoint
    package let startRadiusFraction: CGFloat
    package let endRadiusFraction: CGFloat

    public init(gradient: Gradient, center: UnitPoint = .center, startRadiusFraction: CGFloat = 0, endRadiusFraction: CGFloat = 0.5) {
        self.gradient = gradient
        self.center = center
        self.startRadiusFraction = startRadiusFraction
        self.endRadiusFraction = endRadiusFraction
    }

    public init(colors: [Color], center: UnitPoint = .center, startRadiusFraction: CGFloat = 0, endRadiusFraction: CGFloat = 0.5) {
        self.init(gradient: Gradient(colors: colors), center: center, startRadiusFraction: startRadiusFraction, endRadiusFraction: endRadiusFraction)
    }

    public init(stops: [Gradient.Stop], center: UnitPoint = .center, startRadiusFraction: CGFloat = 0, endRadiusFraction: CGFloat = 0.5) {
        self.init(gradient: Gradient(stops: stops), center: center, startRadiusFraction: startRadiusFraction, endRadiusFraction: endRadiusFraction)
    }
}

extension EllipticalGradient: _GradientStyle {
    package func _resolveGradient(in bounds: CGRect, environment: EnvironmentValues) -> DisplayGradient {
        let c = center._resolve(in: bounds, environment: environment)
        let stops = gradient.resolvedStops(in: environment)
        guard bounds.width > 0, bounds.height > 0, bounds.width != bounds.height else {
            return DisplayGradient(kind: .radial(center: c, startRadius: bounds.width * startRadiusFraction, endRadius: bounds.width * endRadiusFraction), stops: stops)
        }
        return DisplayGradient(kind: .elliptical(center: c, startRadius: bounds.width * startRadiusFraction, endRadius: bounds.width * endRadiusFraction,
                                                 aspect: bounds.height / bounds.width), stops: stops)
    }
}

extension ShapeStyle where Self == EllipticalGradient {
    public static func ellipticalGradient(_ gradient: Gradient, center: UnitPoint = .center, startRadiusFraction: CGFloat = 0, endRadiusFraction: CGFloat = 0.5) -> EllipticalGradient {
        EllipticalGradient(gradient: gradient, center: center, startRadiusFraction: startRadiusFraction, endRadiusFraction: endRadiusFraction)
    }
    public static func ellipticalGradient(colors: [Color], center: UnitPoint = .center, startRadiusFraction: CGFloat = 0, endRadiusFraction: CGFloat = 0.5) -> EllipticalGradient {
        EllipticalGradient(colors: colors, center: center, startRadiusFraction: startRadiusFraction, endRadiusFraction: endRadiusFraction)
    }
    public static func ellipticalGradient(stops: [Gradient.Stop], center: UnitPoint = .center, startRadiusFraction: CGFloat = 0, endRadiusFraction: CGFloat = 0.5) -> EllipticalGradient {
        EllipticalGradient(stops: stops, center: center, startRadiusFraction: startRadiusFraction, endRadiusFraction: endRadiusFraction)
    }
}

/// An angular (conic) gradient: colors around a centre, starting at the trailing direction and
/// running clockwise.
public struct AngularGradient: ShapeStyle, Sendable {
    package let gradient: Gradient
    package let center: UnitPoint
    package let startAngle: Angle
    package let endAngle: Angle

    public init(gradient: Gradient, center: UnitPoint, startAngle: Angle = .zero, endAngle: Angle = .degrees(360)) {
        self.gradient = gradient
        self.center = center
        self.startAngle = startAngle
        self.endAngle = endAngle
    }

    public init(colors: [Color], center: UnitPoint, startAngle: Angle = .zero, endAngle: Angle = .degrees(360)) {
        self.init(gradient: Gradient(colors: colors), center: center, startAngle: startAngle, endAngle: endAngle)
    }

    public init(stops: [Gradient.Stop], center: UnitPoint, startAngle: Angle = .zero, endAngle: Angle = .degrees(360)) {
        self.init(gradient: Gradient(stops: stops), center: center, startAngle: startAngle, endAngle: endAngle)
    }

    public init(gradient: Gradient, center: UnitPoint, angle: Angle = .zero) {
        self.init(gradient: gradient, center: center, startAngle: angle, endAngle: .radians(angle.radians + 2 * Double.pi))
    }

    public init(colors: [Color], center: UnitPoint, angle: Angle = .zero) {
        self.init(gradient: Gradient(colors: colors), center: center, angle: angle)
    }
}

extension AngularGradient: _GradientStyle {
    package func _resolveGradient(in bounds: CGRect, environment: EnvironmentValues) -> DisplayGradient {
        let c = center._resolve(in: bounds, environment: environment)
        // A partial sweep compresses the stops into its angular range and leaves the rest at the end colour.
        let sweep = (endAngle.radians - startAngle.radians) / (2 * Double.pi)
        var stops = gradient.resolvedStops(in: environment)
        if sweep < 0.9999, sweep > 0 {
            stops = stops.map { DisplayGradient.Stop(location: $0.location * sweep, color: $0.color) }
            if let last = stops.last { stops.append(DisplayGradient.Stop(location: 1, color: last.color)) }
        }
        return DisplayGradient(kind: .angular(center: c, startAngle: startAngle.radians), stops: stops)
    }
}

extension ShapeStyle where Self == LinearGradient {
    public static func linearGradient(_ gradient: Gradient, startPoint: UnitPoint, endPoint: UnitPoint) -> LinearGradient {
        LinearGradient(gradient: gradient, startPoint: startPoint, endPoint: endPoint)
    }
    public static func linearGradient(colors: [Color], startPoint: UnitPoint, endPoint: UnitPoint) -> LinearGradient {
        LinearGradient(colors: colors, startPoint: startPoint, endPoint: endPoint)
    }
    public static func linearGradient(stops: [Gradient.Stop], startPoint: UnitPoint, endPoint: UnitPoint) -> LinearGradient {
        LinearGradient(stops: stops, startPoint: startPoint, endPoint: endPoint)
    }
}

extension ShapeStyle where Self == RadialGradient {
    public static func radialGradient(_ gradient: Gradient, center: UnitPoint, startRadius: CGFloat, endRadius: CGFloat) -> RadialGradient {
        RadialGradient(gradient: gradient, center: center, startRadius: startRadius, endRadius: endRadius)
    }
    public static func radialGradient(colors: [Color], center: UnitPoint, startRadius: CGFloat, endRadius: CGFloat) -> RadialGradient {
        RadialGradient(colors: colors, center: center, startRadius: startRadius, endRadius: endRadius)
    }
}

extension ShapeStyle where Self == AngularGradient {
    public static func angularGradient(_ gradient: Gradient, center: UnitPoint, startAngle: Angle, endAngle: Angle) -> AngularGradient {
        AngularGradient(gradient: gradient, center: center, startAngle: startAngle, endAngle: endAngle)
    }
    public static func angularGradient(colors: [Color], center: UnitPoint, startAngle: Angle, endAngle: Angle) -> AngularGradient {
        AngularGradient(colors: colors, center: center, startAngle: startAngle, endAngle: endAngle)
    }
    public static func conicGradient(colors: [Color], center: UnitPoint, angle: Angle = .zero) -> AngularGradient {
        AngularGradient(colors: colors, center: center, angle: angle)
    }
}

// Gradients are also views: a rectangle filled with the gradient, flexible like `Color`.
extension LinearGradient: View {
    public var body: some View { Rectangle().fill(self) }
}

extension RadialGradient: View {
    public var body: some View { Rectangle().fill(self) }
}

extension AngularGradient: View {
    public var body: some View { Rectangle().fill(self) }
}

extension EllipticalGradient: View {
    public var body: some View { Rectangle().fill(self) }
}

extension MeshGradient: View {
    public var body: some View { Rectangle().fill(self) }
}

extension Gradient {
    /// The space gradients blend in: `device` (sRGB components, a mesh's default) or
    /// `perceptual` (Oklab; linear, radial, angular and elliptical gradients always blend so).
    public struct ColorSpace: Hashable, Sendable {
        package let perceptual: Bool
        public static let device = ColorSpace(perceptual: false)
        public static let perceptual = ColorSpace(perceptual: true)
    }
}

/// A two-dimensional gradient: a grid of positioned colours joined by smooth patches
/// (`MeshRasterizer`, Docs/elements/Gradient.md). Rasterised into a bitmap at the paint scale.
public struct MeshGradient: ShapeStyle, Sendable {
    /// A grid point with its Bézier control points (the mesh's edges leave and enter it along them).
    public struct BezierPoint: Equatable, Sendable {
        public var position: SIMD2<Float>
        public var leadingControlPoint: SIMD2<Float>
        public var topControlPoint: SIMD2<Float>
        public var trailingControlPoint: SIMD2<Float>
        public var bottomControlPoint: SIMD2<Float>
        public var topLeadingControlPoint: SIMD2<Float>
        public var topTrailingControlPoint: SIMD2<Float>
        public var bottomLeadingControlPoint: SIMD2<Float>
        public var bottomTrailingControlPoint: SIMD2<Float>

        public init(position: SIMD2<Float>, leadingControlPoint: SIMD2<Float>, topControlPoint: SIMD2<Float>, trailingControlPoint: SIMD2<Float>, bottomControlPoint: SIMD2<Float>,
                    topLeadingControlPoint: SIMD2<Float>, topTrailingControlPoint: SIMD2<Float>, bottomLeadingControlPoint: SIMD2<Float>, bottomTrailingControlPoint: SIMD2<Float>) {
            self.position = position
            self.leadingControlPoint = leadingControlPoint
            self.topControlPoint = topControlPoint
            self.trailingControlPoint = trailingControlPoint
            self.bottomControlPoint = bottomControlPoint
            self.topLeadingControlPoint = topLeadingControlPoint
            self.topTrailingControlPoint = topTrailingControlPoint
            self.bottomLeadingControlPoint = bottomLeadingControlPoint
            self.bottomTrailingControlPoint = bottomTrailingControlPoint
        }
    }

    /// The grid's locations: plain points (control points derived from the neighbours) or Bézier points.
    public struct Locations: Equatable, Sendable {
        package let points: [SIMD2<Float>]
        public static func points(_ points: [SIMD2<Float>]) -> Locations { Locations(points: points) }
        /// Bézier points: the positions are used, the control points derived (approximate).
        public static func bezierPoints(_ points: [BezierPoint]) -> Locations { Locations(points: points.map(\.position)) }
    }

    /// The grid's colours.
    public struct Colors: Equatable, Sendable {
        package let colors: [Color]
        public static func colors(_ colors: [Color]) -> Colors { Colors(colors: colors) }
    }

    public var width: Int
    public var height: Int
    public var locations: Locations
    public var colors: Colors
    public var background: Color
    public var smoothsColors: Bool
    public var colorSpace: Gradient.ColorSpace

    public init(width: Int, height: Int, locations: Locations, colors: Colors, background: Color = .clear, smoothsColors: Bool = true, colorSpace: Gradient.ColorSpace = .device) {
        self.width = width
        self.height = height
        self.locations = locations
        self.colors = colors
        self.background = background
        self.smoothsColors = smoothsColors
        self.colorSpace = colorSpace
    }

    public init(width: Int, height: Int, points: [SIMD2<Float>], colors: [Color], background: Color = .clear, smoothsColors: Bool = true, colorSpace: Gradient.ColorSpace = .device) {
        self.init(width: width, height: height, locations: .points(points), colors: .colors(colors), background: background, smoothsColors: smoothsColors, colorSpace: colorSpace)
    }

    public init(width: Int, height: Int, bezierPoints: [BezierPoint], colors: [Color], background: Color = .clear, smoothsColors: Bool = true, colorSpace: Gradient.ColorSpace = .device) {
        self.init(width: width, height: height, locations: .bezierPoints(bezierPoints), colors: .colors(colors), background: background, smoothsColors: smoothsColors, colorSpace: colorSpace)
    }
}

extension MeshGradient: _GradientStyle {
    @MainActor package func description(in environment: EnvironmentValues, alpha: Double) -> MeshDescription {
        MeshDescription(width: width, height: height,
                        points: locations.points.map { CGPoint(x: CGFloat($0.x), y: CGFloat($0.y)) },
                        colors: colors.colors.map { $0.resolve(in: environment).multiplyingAlpha(by: alpha) },
                        background: background.resolve(in: environment).multiplyingAlpha(by: alpha),
                        smoothsColors: smoothsColors, perceptual: colorSpace.perceptual)
    }

    /// Text and canvas shadings take a linear gradient of the first row's colours (approximate).
    package func _resolveGradient(in bounds: CGRect, environment: EnvironmentValues) -> DisplayGradient {
        let row = Array(colors.colors.prefix(max(width, 1)))
        return LinearGradient(colors: row.isEmpty ? [.clear] : row, startPoint: .leading, endPoint: .trailing)._resolveGradient(in: bounds, environment: environment)
    }

    package func _fill(_ path: Path, in bounds: CGRect, eoFill: Bool, environment: EnvironmentValues, scale: CGFloat, into list: inout DisplayList) {
        _fill(path, in: bounds, eoFill: eoFill, environment: environment, scale: scale, alpha: 1, into: &list)
    }

    package func _stroke(_ path: Path, style: StrokeStyle, in bounds: CGRect, environment: EnvironmentValues, scale: CGFloat, into list: inout DisplayList) {
        _stroke(path, style: style, in: bounds, environment: environment, scale: scale, alpha: 1, into: &list)
    }

    @MainActor package func _fill(_ path: Path, in bounds: CGRect, eoFill: Bool, environment: EnvironmentValues, scale: CGFloat, alpha: Double, into list: inout DisplayList) {
        guard bounds.width > 0, bounds.height > 0 else { return }
        let bitmap = _MeshCache.bitmap(description(in: environment, alpha: alpha), size: bounds.size, scale: scale)
        list.append(.save)
        list.append(.clipPath(path, eoFill: eoFill))
        list.append(.drawBitmap(bitmap, rect: bounds))
        list.append(.restore)
    }

    /// A stroke clips to the stroked outline.
    @MainActor package func _stroke(_ path: Path, style: StrokeStyle, in bounds: CGRect, environment: EnvironmentValues, scale: CGFloat, alpha: Double, into list: inout DisplayList) {
        let outline = path.strokedPath(style)
        let reach = bounds.union(outline.boundingRect)
        _fill(outline, in: reach, eoFill: false, environment: environment, scale: scale, alpha: alpha, into: &list)
    }
}

/// The last few rasterised meshes: an animated mesh re-rasterises every frame, a still one once.
@MainActor
package enum _MeshCache {
    private static var entries: [(key: MeshDescription, size: CGSize, scale: CGFloat, bitmap: DisplayBitmap)] = []

    package static func bitmap(_ mesh: MeshDescription, size: CGSize, scale: CGFloat) -> DisplayBitmap {
        if let hit = entries.first(where: { $0.key == mesh && $0.size == size && $0.scale == scale }) { return hit.bitmap }
        let bitmap = MeshRasterizer.rasterize(mesh, size: size, scale: scale)
        entries.append((mesh, size, scale, bitmap))
        if entries.count > 8 { entries.removeFirst() }
        return bitmap
    }
}
