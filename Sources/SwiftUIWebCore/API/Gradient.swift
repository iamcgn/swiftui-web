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
}

extension Gradient {
    /// The stops for the display list. SwiftUI blends gradients perceptually (measured against
    /// Apple's pixels: Oklab reproduces the midpoint of red → blue exactly, sRGB blending is far
    /// off), and Canvas2D blends in sRGB, so each pair of stops is expanded into sub-stops
    /// interpolated in Oklab that the painter joins with short sRGB segments.
    @MainActor package func resolvedStops(in environment: EnvironmentValues) -> [DisplayGradient.Stop] {
        let resolved = stops.map { DisplayGradient.Stop(location: Double(min(max($0.location, 0), 1)), color: $0.color.resolve(in: environment)) }
        guard resolved.count > 1 else { return resolved }
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

/// A colour in Oklab, for perceptual blending.
package struct _Oklab {
    package var L: Double, a: Double, b: Double

    package init(L: Double, a: Double, b: Double) { self.L = L; self.a = a; self.b = b }

    package init(_ color: RGBA) {
        let r = Self.linear(color.red), g = Self.linear(color.green), bl = Self.linear(color.blue)
        let l = _cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * bl)
        let m = _cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * bl)
        let s = _cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * bl)
        L = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s
        a = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s
        b = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
    }

    package func mixed(with other: _Oklab, t: Double) -> _Oklab {
        _Oklab(L: L + (other.L - L) * t, a: a + (other.a - a) * t, b: b + (other.b - b) * t)
    }

    package func rgba(alpha: Double) -> RGBA {
        let l_ = L + 0.3963377774 * a + 0.2158037573 * b
        let m_ = L - 0.1055613458 * a - 0.0638541728 * b
        let s_ = L - 0.0894841775 * a - 1.2914855480 * b
        let l = l_ * l_ * l_, m = m_ * m_ * m_, s = s_ * s_ * s_
        let r = 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s
        let g = -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s
        let bl = -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s
        return RGBA(red: Self.encoded(r), green: Self.encoded(g), blue: Self.encoded(bl), alpha: alpha)
    }

    private static func linear(_ c: Double) -> Double {
        c <= 0.04045 ? c / 12.92 : _pow((c + 0.055) / 1.055, 2.4)
    }

    private static func encoded(_ c: Double) -> Double {
        let v = min(max(c, 0), 1)
        return v <= 0.0031308 ? v * 12.92 : 1.055 * _pow(v, 1 / 2.4) - 0.055
    }
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

extension LinearGradient: _GradientStyle {
    package func _resolveGradient(in bounds: CGRect, environment: EnvironmentValues) -> DisplayGradient {
        DisplayGradient(kind: .linear(start: CGPoint(x: bounds.minX + bounds.width * startPoint.x, y: bounds.minY + bounds.height * startPoint.y),
                                      end: CGPoint(x: bounds.minX + bounds.width * endPoint.x, y: bounds.minY + bounds.height * endPoint.y)),
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
        let c = CGPoint(x: bounds.minX + bounds.width * center.x, y: bounds.minY + bounds.height * center.y)
        return DisplayGradient(kind: .radial(center: c, startRadius: startRadius, endRadius: endRadius), stops: gradient.resolvedStops(in: environment))
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
        let c = CGPoint(x: bounds.minX + bounds.width * center.x, y: bounds.minY + bounds.height * center.y)
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

/// A resolved gradient for the display list, in absolute coordinates.
public struct DisplayGradient: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case linear(start: CGPoint, end: CGPoint)
        case radial(center: CGPoint, startRadius: CGFloat, endRadius: CGFloat)
        case angular(center: CGPoint, startAngle: Double)
    }

    public struct Stop: Equatable, Sendable {
        public var location: Double
        public var color: RGBA
        public init(location: Double, color: RGBA) {
            self.location = location
            self.color = color
        }
    }

    public var kind: Kind
    public var stops: [Stop]

    public init(kind: Kind, stops: [Stop]) {
        self.kind = kind
        self.stops = stops
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
