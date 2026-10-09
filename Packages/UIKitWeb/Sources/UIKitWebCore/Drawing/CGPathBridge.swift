// CGPath and CGMutablePath (uk-drawing-rest, Docs/elements/UIKit/Drawing.md). On Apple
// platforms the classes are CoreGraphics's and a path made with them converts to the
// substrate's `Path` for `UIBezierPath(cgPath:)`, `addPath` and `CAShapeLayer.path`; on wasm
// the module provides the classes over a `Path`, so a file written against CoreGraphics
// (`CGMutablePath()`, `move(to:)`, `addArc(center:…)`, `addPath`, `closeSubpath`) compiles
// unchanged. `UIBezierPath.cgPath` stays the substrate's `Path` on both.

#if canImport(CoreGraphics)
import CoreGraphics

extension Path {
    /// The substrate path with the elements of a CoreGraphics path.
    public init(cgPath: CGPath) {
        var path = Path()
        cgPath.applyWithBlock { element in
            let points = element.pointee.points
            switch element.pointee.type {
            case .moveToPoint: path.move(to: points[0])
            case .addLineToPoint: path.addLine(to: points[0])
            case .addQuadCurveToPoint: path.addQuadCurve(to: points[1], control: points[0])
            case .addCurveToPoint: path.addCurve(to: points[2], control1: points[0], control2: points[1])
            case .closeSubpath: path.closeSubpath()
            @unknown default: break
            }
        }
        self = path
    }
}

extension UIBezierPath {
    /// A path with a CoreGraphics path's elements.
    public convenience init(cgPath: CGPath) { self.init(cgPath: Path(cgPath: cgPath)) }
    /// Appends a CoreGraphics path's elements.
    public func append(_ cgPath: CGPath) { self.cgPath.addPath(Path(cgPath: cgPath)) }
}

extension UIGraphicsRecordingContext {
    /// Adds a CoreGraphics path to the current path.
    public func addPath(_ cgPath: CGPath) { addPath(Path(cgPath: cgPath)) }
}

extension CAShapeLayer {
    /// Sets the layer's path from a CoreGraphics path.
    public func setPath(_ cgPath: CGPath?) { path = cgPath.map { Path(cgPath: $0) } }
}
#else
/// An immutable path of lines and curves, as CoreGraphics names it: a `Path` the mutable
/// subclass builds.
open class CGPath: @unchecked Sendable {
    public internal(set) var path: Path

    public init(rect: CGRect, transform: UnsafePointer<CGAffineTransform>? = nil) { path = Self.transformed(Path(rect), transform) }
    public init(ellipseIn rect: CGRect, transform: UnsafePointer<CGAffineTransform>? = nil) { path = Self.transformed(Path(ellipseIn: rect), transform) }
    public init(roundedRect rect: CGRect, cornerWidth: CGFloat, cornerHeight: CGFloat, transform: UnsafePointer<CGAffineTransform>? = nil) {
        path = Self.transformed(Path(roundedRect: rect, cornerSize: CGSize(width: cornerWidth, height: cornerHeight), style: .circular), transform)
    }
    init(path: Path) { self.path = path }

    static func transformed(_ path: Path, _ transform: UnsafePointer<CGAffineTransform>?) -> Path {
        transform.map { path.applying($0.pointee) } ?? path
    }

    public var isEmpty: Bool { path.isEmpty }
    public var boundingBox: CGRect { path.boundingRect }
    public var boundingBoxOfPath: CGRect { path.boundingRect }
    public var currentPoint: CGPoint { path.currentPoint ?? .zero }
    public func contains(_ point: CGPoint, using rule: CGPathFillRule = .winding, transform: CGAffineTransform = .identity) -> Bool {
        path.applying(transform).contains(point, eoFill: rule == .evenOdd)
    }
    public func copy() -> CGPath? { CGPath(path: path) }
    public func copy(using transform: UnsafePointer<CGAffineTransform>?) -> CGPath? { CGPath(path: Self.transformed(path, transform)) }
    public func mutableCopy() -> CGMutablePath? { CGMutablePath(path: path) }
    public func mutableCopy(using transform: UnsafePointer<CGAffineTransform>?) -> CGMutablePath? { CGMutablePath(path: Self.transformed(path, transform)) }
}

/// A path being built.
public final class CGMutablePath: CGPath, @unchecked Sendable {
    public init() { super.init(path: Path()) }
    override init(path: Path) { super.init(path: path) }

    public func move(to point: CGPoint, transform: CGAffineTransform = .identity) { path.move(to: point.applying(transform)) }
    public func addLine(to point: CGPoint, transform: CGAffineTransform = .identity) { path.addLine(to: point.applying(transform)) }
    public func addLines(between points: [CGPoint], transform: CGAffineTransform = .identity) { path.addLines(points.map { $0.applying(transform) }) }
    public func addCurve(to end: CGPoint, control1: CGPoint, control2: CGPoint, transform: CGAffineTransform = .identity) {
        path.addCurve(to: end.applying(transform), control1: control1.applying(transform), control2: control2.applying(transform))
    }
    public func addQuadCurve(to end: CGPoint, control: CGPoint, transform: CGAffineTransform = .identity) {
        path.addQuadCurve(to: end.applying(transform), control: control.applying(transform))
    }
    public func addRect(_ rect: CGRect, transform: CGAffineTransform = .identity) { path.addPath(Path(rect).applying(transform)) }
    public func addRects(_ rects: [CGRect], transform: CGAffineTransform = .identity) { for rect in rects { addRect(rect, transform: transform) } }
    public func addEllipse(in rect: CGRect, transform: CGAffineTransform = .identity) { path.addPath(Path(ellipseIn: rect).applying(transform)) }
    public func addRoundedRect(in rect: CGRect, cornerWidth: CGFloat, cornerHeight: CGFloat, transform: CGAffineTransform = .identity) {
        path.addPath(Path(roundedRect: rect, cornerSize: CGSize(width: cornerWidth, height: cornerHeight), style: .circular).applying(transform))
    }
    public func addArc(center: CGPoint, radius: CGFloat, startAngle: CGFloat, endAngle: CGFloat, clockwise: Bool, transform: CGAffineTransform = .identity) {
        // CoreGraphics's `clockwise` is in its own (y-up) sense: in UIKit's flipped space
        // `clockwise: false` runs through increasing angles, the substrate's `clockwise: false`
        // (uikit/draw/rest); `UIBezierPath`'s flag is the screen's and flips.
        path.addArc(center: center, radius: radius, startAngle: Angle(radians: Double(startAngle)), endAngle: Angle(radians: Double(endAngle)), clockwise: clockwise, transform: transform)
    }
    public func addArc(tangent1End: CGPoint, tangent2End: CGPoint, radius: CGFloat, transform: CGAffineTransform = .identity) {
        path.addArc(tangent1End: tangent1End.applying(transform), tangent2End: tangent2End.applying(transform), radius: radius)
    }
    public func addPath(_ other: CGPath, transform: CGAffineTransform = .identity) { path.addPath(other.path.applying(transform)) }
    public func closeSubpath() { path.closeSubpath() }
}

extension UIBezierPath {
    /// A path with a `CGPath`'s elements.
    public convenience init(cgPath: CGPath) { self.init(cgPath: cgPath.path) }
    public func append(_ cgPath: CGPath) { self.cgPath.addPath(cgPath.path) }
}

extension UIGraphicsRecordingContext {
    public func addPath(_ cgPath: CGPath) { addPath(cgPath.path) }
}

extension CAShapeLayer {
    public func setPath(_ cgPath: CGPath?) { path = cgPath?.path }
}
#endif
