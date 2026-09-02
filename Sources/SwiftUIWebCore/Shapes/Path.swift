/// The outline of a 2D shape.
///
/// Construction follows Apple's element order exactly (rounded rectangles start at the middle
/// of the trailing edge and run clockwise on screen, ellipses start at the trailing extreme),
/// so `trim` and `description` agree with SwiftUI's; the continuous corner geometry is measured
/// in `Docs/elements/Shape.md`.
public struct Path: Equatable, Sendable {
    /// An element of a path.
    public enum Element: Equatable, Sendable {
        case move(to: CGPoint)
        case line(to: CGPoint)
        case quadCurve(to: CGPoint, control: CGPoint)
        case curve(to: CGPoint, control1: CGPoint, control2: CGPoint)
        case closeSubpath
    }

    public private(set) var elements: [Element] = []
    private var current: CGPoint?
    private var start: CGPoint?
    private var bounds = CGRect.null

    public init() {}

    public init(_ rect: CGRect) {
        self.init()
        addRect(rect)
    }

    public init(roundedRect rect: CGRect, cornerRadius: CGFloat, style: RoundedCornerStyle = .continuous) {
        self.init()
        addRoundedRect(in: rect, cornerSize: CGSize(width: cornerRadius, height: cornerRadius), style: style)
    }

    public init(roundedRect rect: CGRect, cornerSize: CGSize, style: RoundedCornerStyle = .continuous) {
        self.init()
        addRoundedRect(in: rect, cornerSize: cornerSize, style: style)
    }

    public init(roundedRect rect: CGRect, cornerRadii: RectangleCornerRadii, style: RoundedCornerStyle = .continuous) {
        self.init()
        addRoundedRect(in: rect, cornerRadii: cornerRadii, style: style)
    }

    public init(ellipseIn rect: CGRect) {
        self.init()
        addEllipse(in: rect)
    }

    public init(_ callback: (inout Path) -> Void) {
        self.init()
        callback(&self)
    }

    /// Parses the format `description` writes: postfix operators `m l q c h` after their
    /// coordinates. Returns `nil` for any other token; trailing coordinates without an operator
    /// are ignored.
    public init?(_ string: String) {
        self.init()
        var numbers: [CGFloat] = []
        for token in string.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }) {
            switch token {
            case "m":
                guard numbers.count == 2 else { return nil }
                move(to: CGPoint(x: numbers[0], y: numbers[1]))
            case "l":
                guard numbers.count == 2 else { return nil }
                addLine(to: CGPoint(x: numbers[0], y: numbers[1]))
            case "q":
                guard numbers.count == 4 else { return nil }
                addQuadCurve(to: CGPoint(x: numbers[2], y: numbers[3]), control: CGPoint(x: numbers[0], y: numbers[1]))
            case "c":
                guard numbers.count == 6 else { return nil }
                addCurve(to: CGPoint(x: numbers[4], y: numbers[5]), control1: CGPoint(x: numbers[0], y: numbers[1]),
                         control2: CGPoint(x: numbers[2], y: numbers[3]))
            case "h":
                guard numbers.isEmpty else { return nil }
                closeSubpath()
            default:
                guard let value = Double(token) else { return nil }
                numbers.append(value)
                continue
            }
            numbers.removeAll(keepingCapacity: true)
        }
    }

    public var isEmpty: Bool { elements.isEmpty }

    /// The bounding rectangle of the path's control points (`CGRect.null` for an empty path).
    public var boundingRect: CGRect { bounds }

    public var currentPoint: CGPoint? { current }

    private mutating func include(_ point: CGPoint) {
        bounds = bounds.union(CGRect(origin: point, size: .zero))
    }

    // MARK: Building

    public mutating func move(to point: CGPoint) {
        elements.append(.move(to: point))
        current = point
        start = point
        include(point)
    }

    public mutating func addLine(to point: CGPoint) {
        elements.append(.line(to: point))
        current = point
        include(point)
    }

    public mutating func addQuadCurve(to point: CGPoint, control: CGPoint) {
        elements.append(.quadCurve(to: point, control: control))
        current = point
        include(point)
        include(control)
    }

    public mutating func addCurve(to point: CGPoint, control1: CGPoint, control2: CGPoint) {
        elements.append(.curve(to: point, control1: control1, control2: control2))
        current = point
        include(point)
        include(control1)
        include(control2)
    }

    public mutating func closeSubpath() {
        elements.append(.closeSubpath)
        current = start
    }

    public mutating func addRect(_ rect: CGRect, transform: CGAffineTransform = .identity) {
        move(to: CGPoint(x: rect.minX, y: rect.minY).applying(transform))
        addLine(to: CGPoint(x: rect.maxX, y: rect.minY).applying(transform))
        addLine(to: CGPoint(x: rect.maxX, y: rect.maxY).applying(transform))
        addLine(to: CGPoint(x: rect.minX, y: rect.maxY).applying(transform))
        closeSubpath()
    }

    public mutating func addRects(_ rects: [CGRect], transform: CGAffineTransform = .identity) {
        for rect in rects { addRect(rect, transform: transform) }
    }

    public mutating func addLines(_ points: [CGPoint]) {
        guard let first = points.first else { return }
        move(to: first)
        for point in points.dropFirst() { addLine(to: point) }
    }

    public mutating func addEllipse(in rect: CGRect, transform: CGAffineTransform = .identity) {
        let k = _kappa
        let cx = rect.midX, cy = rect.midY, rx = rect.width / 2, ry = rect.height / 2
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y).applying(transform) }
        move(to: p(cx + rx, cy))
        addCurve(to: p(cx, cy + ry), control1: p(cx + rx, cy + ry * k), control2: p(cx + rx * k, cy + ry))
        addCurve(to: p(cx - rx, cy), control1: p(cx - rx * k, cy + ry), control2: p(cx - rx, cy + ry * k))
        addCurve(to: p(cx, cy - ry), control1: p(cx - rx, cy - ry * k), control2: p(cx - rx * k, cy - ry))
        addCurve(to: p(cx + rx, cy), control1: p(cx + rx * k, cy - ry), control2: p(cx + rx, cy - ry * k))
        closeSubpath()
    }

    /// Adds a rounded rectangle. Both radii are limited to half the smaller side; a zero radius
    /// adds a plain rectangle.
    public mutating func addRoundedRect(in rect: CGRect, cornerSize: CGSize, style: RoundedCornerStyle = .continuous,
                                        transform: CGAffineTransform = .identity) {
        let limit = min(rect.width, rect.height) / 2
        let rx = min(cornerSize.width, limit), ry = min(cornerSize.height, limit)
        guard rx > 0, ry > 0 else { addRect(rect, transform: transform); return }
        let radii = _CornerRadii(uniform: rx, ry)
        _RoundedRect(rect: rect, radii: radii, style: style).add(to: &self, transform: transform)
    }

    /// Adds a rectangle with a radius per corner. Every corner is emitted (as degenerate curves
    /// when its radius is zero), as SwiftUI does for `UnevenRoundedRectangle`.
    public mutating func addRoundedRect(in rect: CGRect, cornerRadii: RectangleCornerRadii, style: RoundedCornerStyle = .continuous,
                                        transform: CGAffineTransform = .identity) {
        let radii = _CornerRadii(uneven: cornerRadii, in: rect)
        _RoundedRect(rect: rect, radii: radii, style: style).add(to: &self, transform: transform)
    }

    /// Adds an arc of a circle. Angles are measured from the positive x axis towards positive
    /// y (downwards on screen), so `clockwise: false` sweeps towards increasing angles, which
    /// appears clockwise on screen; SwiftUI's `clockwise` refers to a y-up space.
    public mutating func addArc(center: CGPoint, radius: CGFloat, startAngle: Angle, endAngle: Angle, clockwise: Bool,
                                transform: CGAffineTransform = .identity) {
        let delta = endAngle.radians - startAngle.radians
        let twoPi = 2 * Double.pi
        let epsilon = 1e-9
        let closes = abs(delta - twoPi) < 1e-6
        var sweep: Double
        if abs(delta) < epsilon {
            sweep = 0
        } else if clockwise {
            sweep = delta > 0 ? twoPi - delta.truncatingRemainder(dividingBy: twoPi) : -delta
        } else {
            sweep = delta > 0 ? delta : twoPi - (-delta).truncatingRemainder(dividingBy: twoPi)
        }
        if closes { sweep = twoPi }
        addArcSegments(center: center, radius: radius, start: startAngle.radians, sweep: clockwise ? -sweep : sweep, transform: transform)
        if closes { closeSubpath() }
    }

    /// Adds an arc of a circle sweeping `delta` from `startAngle` (negative sweeps decrease the angle).
    public mutating func addRelativeArc(center: CGPoint, radius: CGFloat, startAngle: Angle, delta: Angle,
                                        transform: CGAffineTransform = .identity) {
        addArcSegments(center: center, radius: radius, start: startAngle.radians, sweep: delta.radians, transform: transform)
    }

    /// Emits the arc as at most-quarter-turn cubics: full quarters first, then the remainder.
    /// A line (or a move when the path is empty) leads to the arc's start point.
    private mutating func addArcSegments(center: CGPoint, radius: CGFloat, start: Double, sweep: Double, transform: CGAffineTransform) {
        func point(_ angle: Double) -> CGPoint {
            CGPoint(x: center.x + radius * _cos(angle), y: center.y + radius * _sin(angle)).applying(transform)
        }
        let first = point(start)
        if current == nil { move(to: first) } else { addLine(to: first) }
        let quarter = Double.pi / 2
        var remaining = abs(sweep)
        let direction: Double = sweep < 0 ? -1 : 1
        var angle = start
        while remaining > 1e-12 {
            let step = min(quarter, remaining)
            let next = angle + direction * step
            let k = 4.0 / 3.0 * _tan(step / 4) * radius
            let control1 = CGPoint(x: center.x + radius * _cos(angle) - direction * k * _sin(angle),
                                   y: center.y + radius * _sin(angle) + direction * k * _cos(angle))
            let control2 = CGPoint(x: center.x + radius * _cos(next) + direction * k * _sin(next),
                                   y: center.y + radius * _sin(next) - direction * k * _cos(next))
            addCurve(to: point(next), control1: control1.applying(transform), control2: control2.applying(transform))
            angle = next
            remaining -= step
        }
    }

    /// Adds an arc tangent to the lines from the current point to `tangent1End` and from there
    /// to `tangent2End`, as `CGPathAddArcToPoint` does (not verified against SwiftUI's output).
    public mutating func addArc(tangent1End: CGPoint, tangent2End: CGPoint, radius: CGFloat, transform: CGAffineTransform = .identity) {
        guard let from = current else { move(to: tangent1End.applying(transform)); return }
        let v1 = CGPoint(x: from.x - tangent1End.x, y: from.y - tangent1End.y)
        let v2 = CGPoint(x: tangent2End.x - tangent1End.x, y: tangent2End.y - tangent1End.y)
        let l1 = _hypot(v1.x, v1.y), l2 = _hypot(v2.x, v2.y)
        guard l1 > 0, l2 > 0, radius > 0 else { addLine(to: tangent1End.applying(transform)); return }
        let u1 = CGPoint(x: v1.x / l1, y: v1.y / l1), u2 = CGPoint(x: v2.x / l2, y: v2.y / l2)
        let cosTheta = max(-1, min(1, u1.x * u2.x + u1.y * u2.y))
        let theta = _acos(cosTheta)
        guard theta > 1e-9, theta < .pi - 1e-9 else { addLine(to: tangent1End.applying(transform)); return }
        let distance = radius / _tan(theta / 2)
        let a = CGPoint(x: tangent1End.x + u1.x * distance, y: tangent1End.y + u1.y * distance)
        let bisector = CGPoint(x: u1.x + u2.x, y: u1.y + u2.y)
        let bl = _hypot(bisector.x, bisector.y)
        let centerDistance = radius / _sin(theta / 2)
        let center = CGPoint(x: tangent1End.x + bisector.x / bl * centerDistance, y: tangent1End.y + bisector.y / bl * centerDistance)
        let startAngle = _atan2(a.y - center.y, a.x - center.x)
        let cross = u1.x * u2.y - u1.y * u2.x
        let sweep = (Double.pi - theta) * (cross > 0 ? -1 : 1)
        addLine(to: a.applying(transform))
        addArcSegments(center: center, radius: radius, start: startAngle, sweep: sweep, transform: transform)
    }

    public mutating func addPath(_ path: Path, transform: CGAffineTransform = .identity) {
        for element in path.elements {
            switch element {
            case .move(let p): move(to: p.applying(transform))
            case .line(let p): addLine(to: p.applying(transform))
            case .quadCurve(let p, let c): addQuadCurve(to: p.applying(transform), control: c.applying(transform))
            case .curve(let p, let c1, let c2): addCurve(to: p.applying(transform), control1: c1.applying(transform), control2: c2.applying(transform))
            case .closeSubpath: closeSubpath()
            }
        }
    }

    // MARK: Derived paths

    /// Calls `body` with each element of the path.
    public func forEach(_ body: (Element) -> Void) {
        for element in elements { body(element) }
    }

    /// Returns a path with `transform` applied to every point.
    public func applying(_ transform: CGAffineTransform) -> Path {
        var result = Path()
        result.addPath(self, transform: transform)
        return result
    }

    /// Returns a path translated by `offset`.
    public func offsetBy(dx: CGFloat, dy: CGFloat) -> Path {
        applying(CGAffineTransform(translationX: dx, y: dy))
    }

    /// Whether the rectangle path is an axis-aligned rectangle (lets painters use `fillRect`).
    package var asRect: CGRect? {
        guard elements.count == 5,
              case .move(let a) = elements[0], case .line(let b) = elements[1],
              case .line(let c) = elements[2], case .line(let d) = elements[3],
              case .closeSubpath = elements[4],
              a.y == b.y, b.x == c.x, c.y == d.y, d.x == a.x else { return nil }
        return CGRect(x: min(a.x, b.x), y: min(a.y, c.y), width: abs(b.x - a.x), height: abs(c.y - a.y))
    }
}

/// Kappa: the control distance that makes one cubic Bézier approximate a quarter circle.
let _kappa: CGFloat = 0.5522847498307936

/// Defines the shape of a rounded rectangle's corners.
public enum RoundedCornerStyle: Hashable, Sendable {
    case circular
    case continuous
}

/// The radii of each corner of a rounded rectangle.
@frozen
public struct RectangleCornerRadii: Equatable, Hashable, Sendable {
    public var topLeading: CGFloat
    public var bottomLeading: CGFloat
    public var bottomTrailing: CGFloat
    public var topTrailing: CGFloat

    @inlinable public init(topLeading: CGFloat = 0, bottomLeading: CGFloat = 0, bottomTrailing: CGFloat = 0, topTrailing: CGFloat = 0) {
        self.topLeading = topLeading
        self.bottomLeading = bottomLeading
        self.bottomTrailing = bottomTrailing
        self.topTrailing = topTrailing
    }
}

extension RectangleCornerRadii: Animatable {
    public typealias AnimatableData = AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>>
    public var animatableData: AnimatableData {
        get { .init(.init(topLeading, bottomLeading), .init(bottomTrailing, topTrailing)) }
        set {
            topLeading = newValue.first.first
            bottomLeading = newValue.first.second
            bottomTrailing = newValue.second.first
            topTrailing = newValue.second.second
        }
    }
}

extension Path: LosslessStringConvertible {
    /// The elements in Apple's format: coordinates then a postfix operator (`m l q c h`),
    /// six significant digits.
    public var description: String {
        var parts: [String] = []
        parts.reserveCapacity(elements.count * 3)
        func p(_ point: CGPoint) { parts.append(_formatG(point.x)); parts.append(_formatG(point.y)) }
        for element in elements {
            switch element {
            case .move(let to): p(to); parts.append("m")
            case .line(let to): p(to); parts.append("l")
            case .quadCurve(let to, let control): p(control); p(to); parts.append("q")
            case .curve(let to, let c1, let c2): p(c1); p(c2); p(to); parts.append("c")
            case .closeSubpath: parts.append("h")
            }
        }
        return parts.joined(separator: " ")
    }
}

extension Path: Shape {
    nonisolated public func path(in rect: CGRect) -> Path { self }
    public typealias AnimatableData = EmptyAnimatableData
}

/// C's `%g`: six significant digits, trailing zeros removed, exponent form outside 1e-5…1e6.
/// Rounds the shortest round-trip decimal digits (ties to even), like printf on the exact value.
package func _formatG(_ value: Double) -> String {
    if value.isNaN { return "nan" }
    if value.isInfinite { return value < 0 ? "-inf" : "inf" }
    if value == 0 { return "0" }
    // Shortest round-trip text: "123.456", "1.2345e-05", "1e+06".
    var text = Substring("\(abs(value))")
    var exponent = 0
    if let e = text.firstIndex(where: { $0 == "e" || $0 == "E" }) {
        exponent = Int(String(text[text.index(after: e)...].filter { $0 != "+" })) ?? 0
        text = text[..<e]
    }
    var digits: [UInt8] = []
    var pointPosition: Int?   // number of digits before the decimal point
    for c in text.utf8 {
        if c == UInt8(ascii: ".") { pointPosition = digits.count } else { digits.append(c - UInt8(ascii: "0")) }
    }
    var decimalExponent = (pointPosition ?? digits.count) - 1 + exponent   // value = d.ddd × 10^decimalExponent
    // Strip leading zeros (0.00123 → 123, exponent adjusted).
    while digits.count > 1, digits[0] == 0 { digits.removeFirst(); decimalExponent -= 1 }
    // Round to six significant digits, ties to even.
    if digits.count > 6 {
        let rest = digits[6...]
        let roundUp: Bool
        if rest[rest.startIndex] > 5 || (rest[rest.startIndex] == 5 && rest.dropFirst().contains { $0 != 0 }) {
            roundUp = true
        } else if rest[rest.startIndex] == 5 {
            roundUp = digits[5] % 2 == 1
        } else {
            roundUp = false
        }
        digits.removeSubrange(6...)
        if roundUp {
            var i = 5
            while i >= 0 {
                if digits[i] == 9 { digits[i] = 0; i -= 1 } else { digits[i] += 1; break }
            }
            if i < 0 { digits.insert(1, at: 0); digits.removeLast(); decimalExponent += 1 }
        }
    }
    while digits.count < 6 { digits.append(0) }
    while digits.count > 1, digits.last == 0 { digits.removeLast() }
    let chars = digits.map { String($0) }
    var result: String
    if decimalExponent < -4 || decimalExponent >= 6 {
        result = chars[0] + (chars.count > 1 ? "." + chars.dropFirst().joined() : "")
        let magnitude = abs(decimalExponent)
        result += (decimalExponent < 0 ? "e-" : "e+") + (magnitude < 10 ? "0" : "") + String(magnitude)
    } else if decimalExponent >= 0 {
        let integerCount = decimalExponent + 1
        let integer = chars.prefix(integerCount).joined() + String(repeating: "0", count: max(0, integerCount - chars.count))
        let fraction = chars.dropFirst(integerCount).joined()
        result = integer + (fraction.isEmpty ? "" : "." + fraction)
    } else {
        result = "0." + String(repeating: "0", count: -decimalExponent - 1) + chars.joined()
    }
    return value < 0 ? "-" + result : result
}
