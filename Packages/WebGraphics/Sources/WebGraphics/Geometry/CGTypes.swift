// Geometry types (decision 0006). Apple platforms use CoreGraphics; Linux keeps Foundation's
// CGFloat, CGPoint, CGSize and CGRect, with the missing CoreGraphics APIs supplied below.
// wasm gets all the declarations so the core never links Foundation's 12 MB of ICU data.
// Its CGFloat is a Double alias; native platforms retain their existing CGFloat type.
#if !canImport(CoreGraphics) && !os(WASI)
import Foundation
#endif

#if os(WASI)

public typealias CGFloat = Double

#if canImport(ObjectiveC)
// With the Objective-C runtime the three are C structs (WebCGGeometry's header), as
// CoreGraphics's are on iOS: an `@objc` method or block can then take or return them
// (CVCalendar's `@objc func updateFrames(_ frame: CGRect)` and its delegate's
// `selectionViewPath() -> ((CGRect) -> UIBezierPath)`). A Swift struct never can.
@_exported import WebCGGeometry

extension CGPoint: @retroactive Equatable, @retroactive Hashable {
    public static func == (lhs: CGPoint, rhs: CGPoint) -> Bool { lhs.x == rhs.x && lhs.y == rhs.y }
    public func hash(into hasher: inout Hasher) { hasher.combine(x); hasher.combine(y) }
}

extension CGSize: @retroactive Equatable, @retroactive Hashable {
    public static func == (lhs: CGSize, rhs: CGSize) -> Bool { lhs.width == rhs.width && lhs.height == rhs.height }
    public func hash(into hasher: inout Hasher) { hasher.combine(width); hasher.combine(height) }
}

extension CGRect: @retroactive Equatable, @retroactive Hashable {
    public static func == (lhs: CGRect, rhs: CGRect) -> Bool { lhs.origin == rhs.origin && lhs.size == rhs.size }
    public func hash(into hasher: inout Hasher) { hasher.combine(origin); hasher.combine(size) }
}
#else
public struct CGPoint: Equatable, Hashable, Sendable {
    public var x: CGFloat
    public var y: CGFloat

    public init() { x = 0; y = 0 }
    public init(x: CGFloat, y: CGFloat) { self.x = x; self.y = y }
}

public struct CGSize: Equatable, Hashable, Sendable {
    public var width: CGFloat
    public var height: CGFloat

    public init() { width = 0; height = 0 }
    public init(width: CGFloat, height: CGFloat) { self.width = width; self.height = height }
}

public struct CGRect: Equatable, Hashable, Sendable {
    public var origin: CGPoint
    public var size: CGSize

    public init() { origin = .zero; size = .zero }
    public init(origin: CGPoint, size: CGSize) { self.origin = origin; self.size = size }
}
#endif

extension CGPoint {
    public init(x: Int, y: Int) { self.init(x: CGFloat(x), y: CGFloat(y)) }

    public static let zero = CGPoint()
}

extension CGSize {
    public init(width: Int, height: Int) { self.init(width: CGFloat(width), height: CGFloat(height)) }

    public static let zero = CGSize()
}

extension CGRect {
    public init(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) {
        self.init(origin: CGPoint(x: x, y: y), size: CGSize(width: width, height: height))
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
}

#endif

#if !canImport(CoreGraphics) || os(WASI)

public struct CGVector: Equatable, Hashable, Sendable {
    public var dx: CGFloat
    public var dy: CGFloat

    public init() { dx = 0; dy = 0 }
    public init(dx: CGFloat, dy: CGFloat) { self.dx = dx; self.dy = dy }

    public static let zero = CGVector()
}

extension CGPoint {
    public func applying(_ t: CGAffineTransform) -> CGPoint {
        CGPoint(x: t.a * x + t.c * y + t.tx, y: t.b * x + t.d * y + t.ty)
    }
}

extension CGSize {
    public func applying(_ t: CGAffineTransform) -> CGSize {
        CGSize(width: t.a * width + t.c * height, height: t.b * width + t.d * height)
    }
}

extension CGRect {
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

// Linux Foundation has its own edges and division; wasm gets these.
#if os(WASI)
// CoreGraphics' equality functions, as Swift spells them.
extension CGPoint { public func equalTo(_ point2: CGPoint) -> Bool { self == point2 } }
extension CGSize { public func equalTo(_ size2: CGSize) -> Bool { self == size2 } }
extension CGRect { public func equalTo(_ rect2: CGRect) -> Bool { self == rect2 } }

/// A side of a rectangle, as `CGRect.divided(atDistance:from:)` names it.
public enum CGRectEdge: UInt32, Sendable {
    case minXEdge, minYEdge, maxXEdge, maxYEdge
}

extension CGRect {
    /// The strip `distance` wide along `edge` (clamped to the rectangle) and what is left, as
    /// CoreGraphics divides a standardized rectangle.
    public func divided(atDistance distance: CGFloat, from edge: CGRectEdge) -> (slice: CGRect, remainder: CGRect) {
        if isNull { return (.null, .null) }
        let r = standardized
        switch edge {
        case .minXEdge, .maxXEdge:
            let d = min(max(distance, 0), r.width)
            let sliceX = edge == .minXEdge ? r.minX : r.maxX - d
            let restX = edge == .minXEdge ? r.minX + d : r.minX
            return (CGRect(x: sliceX, y: r.minY, width: d, height: r.height), CGRect(x: restX, y: r.minY, width: r.width - d, height: r.height))
        case .minYEdge, .maxYEdge:
            let d = min(max(distance, 0), r.height)
            let sliceY = edge == .minYEdge ? r.minY : r.maxY - d
            let restY = edge == .minYEdge ? r.minY + d : r.minY
            return (CGRect(x: r.minX, y: sliceY, width: r.width, height: d), CGRect(x: r.minX, y: restY, width: r.width, height: r.height - d))
        }
    }
}
#endif

public struct CGAffineTransform: Equatable, Hashable, Sendable {
    public var a: CGFloat, b: CGFloat, c: CGFloat, d: CGFloat, tx: CGFloat, ty: CGFloat

    public init() { self.init(a: 1, b: 0, c: 0, d: 1, tx: 0, ty: 0) }
    public init(a: CGFloat, b: CGFloat, c: CGFloat, d: CGFloat, tx: CGFloat, ty: CGFloat) {
        self.a = a; self.b = b; self.c = c; self.d = d; self.tx = tx; self.ty = ty
    }
    public init(translationX tx: CGFloat, y ty: CGFloat) { self.init(a: 1, b: 0, c: 0, d: 1, tx: tx, ty: ty) }
    public init(scaleX sx: CGFloat, y sy: CGFloat) { self.init(a: sx, b: 0, c: 0, d: sy, tx: 0, ty: 0) }
    public init(rotationAngle angle: CGFloat) {
        let cs = CGFloat(_cos(Double(angle))), sn = CGFloat(_sin(Double(angle)))
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

/// A colour as CoreAnimation and UIKit name it (`layer.backgroundColor`, `UIColor.cgColor`):
/// straight-alpha sRGB components. On Apple platforms this is CoreGraphics's class.
public final class CGColor: @unchecked Sendable {
    /// Red, green, blue and alpha in 0…1.
    public let components: [CGFloat]?

    public init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        components = [red, green, blue, alpha]
    }

    public init(gray: CGFloat, alpha: CGFloat) {
        components = [gray, gray, gray, alpha]
    }

    public var alpha: CGFloat { components?.last ?? 1 }
    public var numberOfComponents: Int { components?.count ?? 0 }
}

/// How the ends of an open path are drawn when stroked.
public enum CGLineCap: Int32, Sendable {
    case butt = 0
    case round = 1
    case square = 2
}

/// How the joints between path segments are drawn when stroked.
public enum CGLineJoin: Int32, Sendable {
    case miter = 0
    case round = 1
    case bevel = 2
}

#endif
