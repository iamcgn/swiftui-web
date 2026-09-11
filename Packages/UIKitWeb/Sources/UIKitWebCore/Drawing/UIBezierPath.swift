// UIBezierPath (Docs/elements/UIKit/Drawing.md): a path in the view's coordinates over the
// substrate's `Path`, filled and stroked into the current graphics context (decision 0014,
// Phase 3).

/// A path that consists of straight and curved line segments that you can render in your
/// custom views.
@MainActor
public final class UIBezierPath {
    /// The path itself (`cgPath` in UIKit; the substrate's `Path` stands in for CGPath).
    public var cgPath: Path
    public var lineWidth: CGFloat = 1
    public var lineCapStyle: CGLineCap = .butt
    public var lineJoinStyle: CGLineJoin = .miter
    public var miterLimit: CGFloat = 10
    public var flatness: CGFloat = 0.6
    public var usesEvenOddFillRule = false
    private var dash: [CGFloat] = []
    private var dashPhase: CGFloat = 0

    public init() { cgPath = Path() }
    public init(cgPath: Path) { self.cgPath = cgPath }
    public init(rect: CGRect) { cgPath = Path(rect) }
    public init(ovalIn rect: CGRect) { cgPath = Path(ellipseIn: rect) }
    public init(roundedRect rect: CGRect, cornerRadius: CGFloat) { cgPath = Path(roundedRect: rect, cornerRadius: cornerRadius, style: .circular) }
    public init(roundedRect rect: CGRect, byRoundingCorners corners: UIRectCorner, cornerRadii: CGSize) {
        let r = cornerRadii.width
        cgPath = Path(roundedRect: rect, cornerRadii: RectangleCornerRadii(
            topLeading: corners.contains(.topLeft) ? r : 0, bottomLeading: corners.contains(.bottomLeft) ? r : 0,
            bottomTrailing: corners.contains(.bottomRight) ? r : 0, topTrailing: corners.contains(.topRight) ? r : 0), style: .circular)
    }
    public init(arcCenter center: CGPoint, radius: CGFloat, startAngle: CGFloat, endAngle: CGFloat, clockwise: Bool) {
        cgPath = Path()
        addArc(withCenter: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: clockwise)
    }

    // MARK: Building

    public var currentPoint: CGPoint { cgPath.currentPoint ?? .zero }
    public var isEmpty: Bool { cgPath.isEmpty }
    public var bounds: CGRect { cgPath.boundingRect }

    public func move(to point: CGPoint) { cgPath.move(to: point) }
    public func addLine(to point: CGPoint) { cgPath.addLine(to: point) }
    public func addCurve(to endPoint: CGPoint, controlPoint1: CGPoint, controlPoint2: CGPoint) { cgPath.addCurve(to: endPoint, control1: controlPoint1, control2: controlPoint2) }
    public func addQuadCurve(to endPoint: CGPoint, controlPoint: CGPoint) { cgPath.addQuadCurve(to: endPoint, control: controlPoint) }
    /// UIKit's angles run clockwise on screen (y down): its `clockwise` is the substrate's.
    public func addArc(withCenter center: CGPoint, radius: CGFloat, startAngle: CGFloat, endAngle: CGFloat, clockwise: Bool) {
        cgPath.addArc(center: center, radius: radius, startAngle: Angle(radians: Double(startAngle)), endAngle: Angle(radians: Double(endAngle)), clockwise: !clockwise)
    }
    public func close() { cgPath.closeSubpath() }
    public func removeAllPoints() { cgPath = Path() }
    public func append(_ bezierPath: UIBezierPath) { cgPath.addPath(bezierPath.cgPath) }
    public func apply(_ transform: CGAffineTransform) { cgPath = cgPath.applying(transform) }
    public func reversing() -> UIBezierPath { UIBezierPath(cgPath: cgPath) }
    public func contains(_ point: CGPoint) -> Bool { cgPath.boundingRect.contains(point) }

    public func setLineDash(_ pattern: [CGFloat]?, count: Int, phase: CGFloat) {
        dash = Array((pattern ?? []).prefix(count))
        dashPhase = phase
    }

    public func getLineDash(_ pattern: UnsafeMutablePointer<CGFloat>?, count: UnsafeMutablePointer<Int>?, phase: UnsafeMutablePointer<CGFloat>?) {
        if let pattern { for (index, value) in dash.enumerated() { pattern[index] = value } }
        count?.pointee = dash.count
        phase?.pointee = dashPhase
    }

    var strokeStyle: StrokeStyle {
        StrokeStyle(lineWidth: lineWidth, lineCap: lineCapStyle, lineJoin: lineJoinStyle, miterLimit: miterLimit, dash: dash, dashPhase: dashPhase)
    }

    // MARK: Drawing into the current context

    public func fill() { UIGraphicsGetCurrentContext()?.fill(self, alpha: 1) }
    public func fill(with blendMode: CGBlendMode, alpha: CGFloat) { UIGraphicsGetCurrentContext()?.fill(self, alpha: alpha) }
    public func stroke() { UIGraphicsGetCurrentContext()?.stroke(self, alpha: 1) }
    public func stroke(with blendMode: CGBlendMode, alpha: CGFloat) { UIGraphicsGetCurrentContext()?.stroke(self, alpha: alpha) }
    public func addClip() { UIGraphicsGetCurrentContext()?.clip(to: cgPath, evenOdd: usesEvenOddFillRule) }
}

#if !canImport(CoreGraphics)
/// Blend modes as CoreGraphics names them (accepted; drawing uses normal compositing).
public enum CGBlendMode: Int32, Sendable {
    case normal = 0, multiply, screen, overlay, darken, lighten, colorDodge, colorBurn, softLight, hardLight, difference, exclusion
    case hue, saturation, color, luminosity, clear, copy, sourceIn, sourceOut, sourceAtop, destinationOver, destinationIn, destinationOut, destinationAtop, xor, plusDarker, plusLighter
}

/// Fill rules as CoreGraphics names them.
public enum CGPathFillRule: Int, Sendable { case winding = 0, evenOdd }
public enum CGPathDrawingMode: Int32, Sendable { case fill = 0, eoFill, stroke, fillStroke, eoFillStroke }
#endif
