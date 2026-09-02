// Geometry types (decision 0006). Apple platforms use CoreGraphics; Linux uses
// swift-corelibs-foundation's declarations (free natively); wasm gets these declarations so the
// core never links Foundation's 12 MB of ICU data. `CGFloat` is a typealias of `Double` here:
// Swift already converts implicitly between the two on Apple platforms, so unmodified sources
// keep compiling, at the cost of not being able to overload on both.
#if os(WASI)

public typealias CGFloat = Double

public struct CGPoint: Equatable, Hashable, Sendable {
    public var x: CGFloat
    public var y: CGFloat

    public init() { x = 0; y = 0 }
    public init(x: CGFloat, y: CGFloat) { self.x = x; self.y = y }
    public init(x: Int, y: Int) { self.x = CGFloat(x); self.y = CGFloat(y) }

    public static let zero = CGPoint()

    public func applying(_ t: CGAffineTransform) -> CGPoint {
        CGPoint(x: t.a * x + t.c * y + t.tx, y: t.b * x + t.d * y + t.ty)
    }
}

public struct CGSize: Equatable, Hashable, Sendable {
    public var width: CGFloat
    public var height: CGFloat

    public init() { width = 0; height = 0 }
    public init(width: CGFloat, height: CGFloat) { self.width = width; self.height = height }
    public init(width: Int, height: Int) { self.width = CGFloat(width); self.height = CGFloat(height) }

    public static let zero = CGSize()

    public func applying(_ t: CGAffineTransform) -> CGSize {
        CGSize(width: t.a * width + t.c * height, height: t.b * width + t.d * height)
    }
}

public struct CGVector: Equatable, Hashable, Sendable {
    public var dx: CGFloat
    public var dy: CGFloat

    public init() { dx = 0; dy = 0 }
    public init(dx: CGFloat, dy: CGFloat) { self.dx = dx; self.dy = dy }

    public static let zero = CGVector()
}

public struct CGRect: Equatable, Hashable, Sendable {
    public var origin: CGPoint
    public var size: CGSize

    public init() { origin = .zero; size = .zero }
    public init(origin: CGPoint, size: CGSize) { self.origin = origin; self.size = size }
    public init(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) {
        origin = CGPoint(x: x, y: y)
        size = CGSize(width: width, height: height)
    }
    public init(x: Int, y: Int, width: Int, height: Int) {
        self.init(x: CGFloat(x), y: CGFloat(y), width: CGFloat(width), height: CGFloat(height))
    }

    public static let zero = CGRect()
    public static let null = CGRect(x: .infinity, y: .infinity, width: 0, height: 0)
    public static let infinite = CGRect(x: -.greatestFiniteMagnitude / 2, y: -.greatestFiniteMagnitude / 2,
                                        width: .greatestFiniteMagnitude, height: .greatestFiniteMagnitude)

    public var isNull: Bool { origin.x == .infinity || origin.y == .infinity }
    public var isEmpty: Bool { isNull || size.width <= 0 || size.height <= 0 }
    public var isInfinite: Bool { self == .infinite }

    public var standardized: CGRect {
        if isNull { return self }
        var r = self
        if r.size.width < 0 { r.origin.x += r.size.width; r.size.width = -r.size.width }
        if r.size.height < 0 { r.origin.y += r.size.height; r.size.height = -r.size.height }
        return r
    }

    public var width: CGFloat { abs(size.width) }
    public var height: CGFloat { abs(size.height) }
    public var minX: CGFloat { standardized.origin.x }
    public var midX: CGFloat { minX + width / 2 }
    public var maxX: CGFloat { minX + width }
    public var minY: CGFloat { standardized.origin.y }
    public var midY: CGFloat { minY + height / 2 }
    public var maxY: CGFloat { minY + height }

    public var integral: CGRect {
        if isNull { return self }
        let s = standardized
        let x0 = s.minX.rounded(.down), y0 = s.minY.rounded(.down)
        return CGRect(x: x0, y: y0, width: s.maxX.rounded(.up) - x0, height: s.maxY.rounded(.up) - y0)
    }

    public func insetBy(dx: CGFloat, dy: CGFloat) -> CGRect {
        if isNull { return self }
        let r = CGRect(x: minX + dx, y: minY + dy, width: width - 2 * dx, height: height - 2 * dy)
        return r.size.width < 0 || r.size.height < 0 ? .null : r
    }

    public func offsetBy(dx: CGFloat, dy: CGFloat) -> CGRect {
        if isNull { return self }
        return CGRect(x: minX + dx, y: minY + dy, width: width, height: height)
    }

    public func union(_ other: CGRect) -> CGRect {
        if isNull { return other }
        if other.isNull { return self }
        let x0 = min(minX, other.minX), y0 = min(minY, other.minY)
        return CGRect(x: x0, y: y0, width: max(maxX, other.maxX) - x0, height: max(maxY, other.maxY) - y0)
    }

    public func intersection(_ other: CGRect) -> CGRect {
        if isNull || other.isNull { return .null }
        let x0 = max(minX, other.minX), y0 = max(minY, other.minY)
        let x1 = min(maxX, other.maxX), y1 = min(maxY, other.maxY)
        if x1 < x0 || y1 < y0 { return .null }
        return CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }

    public func intersects(_ other: CGRect) -> Bool { !intersection(other).isNull }

    public func contains(_ point: CGPoint) -> Bool {
        !isNull && point.x >= minX && point.x < maxX && point.y >= minY && point.y < maxY
    }

    public func contains(_ rect: CGRect) -> Bool {
        union(rect) == standardized
    }

    public func applying(_ t: CGAffineTransform) -> CGRect {
        if isNull { return self }
        let corners = [
            CGPoint(x: minX, y: minY).applying(t), CGPoint(x: maxX, y: minY).applying(t),
            CGPoint(x: minX, y: maxY).applying(t), CGPoint(x: maxX, y: maxY).applying(t),
        ]
        let xs = corners.map(\.x), ys = corners.map(\.y)
        return CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
    }
}

public struct CGAffineTransform: Equatable, Hashable, Sendable {
    public var a: CGFloat, b: CGFloat, c: CGFloat, d: CGFloat, tx: CGFloat, ty: CGFloat

    public init() { self.init(a: 1, b: 0, c: 0, d: 1, tx: 0, ty: 0) }
    public init(a: CGFloat, b: CGFloat, c: CGFloat, d: CGFloat, tx: CGFloat, ty: CGFloat) {
        self.a = a; self.b = b; self.c = c; self.d = d; self.tx = tx; self.ty = ty
    }
    public init(translationX tx: CGFloat, y ty: CGFloat) { self.init(a: 1, b: 0, c: 0, d: 1, tx: tx, ty: ty) }
    public init(scaleX sx: CGFloat, y sy: CGFloat) { self.init(a: sx, b: 0, c: 0, d: sy, tx: 0, ty: 0) }
    public init(rotationAngle angle: CGFloat) {
        let cs = _cos(angle), sn = _sin(angle)
        self.init(a: cs, b: sn, c: -sn, d: cs, tx: 0, ty: 0)
    }

    public static let identity = CGAffineTransform()
    public var isIdentity: Bool { self == .identity }

    public func concatenating(_ t: CGAffineTransform) -> CGAffineTransform {
        CGAffineTransform(
            a: a * t.a + b * t.c, b: a * t.b + b * t.d,
            c: c * t.a + d * t.c, d: c * t.b + d * t.d,
            tx: tx * t.a + ty * t.c + t.tx, ty: tx * t.b + ty * t.d + t.ty)
    }
    public func translatedBy(x: CGFloat, y: CGFloat) -> CGAffineTransform {
        CGAffineTransform(translationX: x, y: y).concatenating(self)
    }
    public func scaledBy(x: CGFloat, y: CGFloat) -> CGAffineTransform {
        CGAffineTransform(scaleX: x, y: y).concatenating(self)
    }
    public func rotated(by angle: CGFloat) -> CGAffineTransform {
        CGAffineTransform(rotationAngle: angle).concatenating(self)
    }
    public func inverted() -> CGAffineTransform {
        let det = a * d - b * c
        guard det != 0 else { return self }
        return CGAffineTransform(
            a: d / det, b: -b / det, c: -c / det, d: a / det,
            tx: (c * ty - d * tx) / det, ty: (b * tx - a * ty) / det)
    }
}

// Minimal trig without libm's Foundation wrapper: wasi-libc provides these C symbols.
@_silgen_name("cos") private func _c_cos(_ x: Double) -> Double
@_silgen_name("sin") private func _c_sin(_ x: Double) -> Double
@inline(__always) package func _cos(_ x: Double) -> Double { _c_cos(x) }
@inline(__always) package func _sin(_ x: Double) -> Double { _c_sin(x) }

#endif
