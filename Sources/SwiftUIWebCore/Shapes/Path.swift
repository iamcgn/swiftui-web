/// The outline of a 2D shape.
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

    public init(ellipseIn rect: CGRect) {
        self.init()
        addEllipse(in: rect)
    }

    public init(_ callback: (inout Path) -> Void) {
        self.init()
        callback(&self)
    }

    public var isEmpty: Bool { elements.isEmpty }

    /// The bounding rectangle of the path's control points.
    public var boundingRect: CGRect { bounds.isNull ? .zero : bounds }

    public var currentPoint: CGPoint? { current }

    private mutating func include(_ point: CGPoint) {
        bounds = bounds.union(CGRect(origin: point, size: .zero))
    }

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

    public mutating func addRect(_ rect: CGRect) {
        move(to: CGPoint(x: rect.minX, y: rect.minY))
        addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        closeSubpath()
    }

    public mutating func addRects(_ rects: [CGRect]) {
        for rect in rects { addRect(rect) }
    }

    public mutating func addLines(_ points: [CGPoint]) {
        guard let first = points.first else { return }
        move(to: first)
        for point in points.dropFirst() { addLine(to: point) }
    }

    /// Kappa for approximating a quarter circle with one cubic Bézier.
    private static let kappa: CGFloat = 0.5522847498307936

    public mutating func addEllipse(in rect: CGRect) {
        let k = Self.kappa
        let cx = rect.midX, cy = rect.midY, rx = rect.width / 2, ry = rect.height / 2
        move(to: CGPoint(x: cx + rx, y: cy))
        addCurve(to: CGPoint(x: cx, y: cy + ry), control1: CGPoint(x: cx + rx, y: cy + ry * k), control2: CGPoint(x: cx + rx * k, y: cy + ry))
        addCurve(to: CGPoint(x: cx - rx, y: cy), control1: CGPoint(x: cx - rx * k, y: cy + ry), control2: CGPoint(x: cx - rx, y: cy + ry * k))
        addCurve(to: CGPoint(x: cx, y: cy - ry), control1: CGPoint(x: cx - rx, y: cy - ry * k), control2: CGPoint(x: cx - rx * k, y: cy - ry))
        addCurve(to: CGPoint(x: cx + rx, y: cy), control1: CGPoint(x: cx + rx * k, y: cy - ry), control2: CGPoint(x: cx + rx, y: cy - ry * k))
        closeSubpath()
    }

    public mutating func addRoundedRect(in rect: CGRect, cornerSize: CGSize, style: RoundedCornerStyle = .continuous) {
        let rx = min(cornerSize.width, rect.width / 2), ry = min(cornerSize.height, rect.height / 2)
        guard rx > 0, ry > 0 else { addRect(rect); return }
        let k = Self.kappa
        move(to: CGPoint(x: rect.minX + rx, y: rect.minY))
        addLine(to: CGPoint(x: rect.maxX - rx, y: rect.minY))
        addCurve(to: CGPoint(x: rect.maxX, y: rect.minY + ry),
                 control1: CGPoint(x: rect.maxX - rx + rx * k, y: rect.minY), control2: CGPoint(x: rect.maxX, y: rect.minY + ry - ry * k))
        addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - ry))
        addCurve(to: CGPoint(x: rect.maxX - rx, y: rect.maxY),
                 control1: CGPoint(x: rect.maxX, y: rect.maxY - ry + ry * k), control2: CGPoint(x: rect.maxX - rx + rx * k, y: rect.maxY))
        addLine(to: CGPoint(x: rect.minX + rx, y: rect.maxY))
        addCurve(to: CGPoint(x: rect.minX, y: rect.maxY - ry),
                 control1: CGPoint(x: rect.minX + rx - rx * k, y: rect.maxY), control2: CGPoint(x: rect.minX, y: rect.maxY - ry + ry * k))
        addLine(to: CGPoint(x: rect.minX, y: rect.minY + ry))
        addCurve(to: CGPoint(x: rect.minX + rx, y: rect.minY),
                 control1: CGPoint(x: rect.minX, y: rect.minY + ry - ry * k), control2: CGPoint(x: rect.minX + rx - rx * k, y: rect.minY))
        closeSubpath()
    }

    public mutating func addPath(_ path: Path) {
        for element in path.elements {
            switch element {
            case .move(let p): move(to: p)
            case .line(let p): addLine(to: p)
            case .quadCurve(let p, let c): addQuadCurve(to: p, control: c)
            case .curve(let p, let c1, let c2): addCurve(to: p, control1: c1, control2: c2)
            case .closeSubpath: closeSubpath()
            }
        }
    }

    /// Returns a path translated by `offset`.
    public func offsetBy(dx: CGFloat, dy: CGFloat) -> Path {
        var result = Path()
        func t(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x + dx, y: p.y + dy) }
        for element in elements {
            switch element {
            case .move(let p): result.move(to: t(p))
            case .line(let p): result.addLine(to: t(p))
            case .quadCurve(let p, let c): result.addQuadCurve(to: t(p), control: t(c))
            case .curve(let p, let c1, let c2): result.addCurve(to: t(p), control1: t(c1), control2: t(c2))
            case .closeSubpath: result.closeSubpath()
            }
        }
        return result
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

/// Defines the shape of a rounded rectangle's corners.
public enum RoundedCornerStyle: Hashable, Sendable {
    case circular
    case continuous
}
