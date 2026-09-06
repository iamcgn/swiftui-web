// Rounded-rectangle geometry, reproducing SwiftUI's paths element for element
// (`Docs/elements/Shape.md`, "Corner geometry"): circular corners are quarter ellipses with the
// usual Bézier kappa; continuous corners are three cubics whose extent along each edge is
// 1.528665 × radius, compressed linearly towards a 1 × radius extent when the edge is too short.

/// The resolved x and y radius of each corner.
struct _CornerRadii {
    var topLeading: CGSize
    var topTrailing: CGSize
    var bottomTrailing: CGSize
    var bottomLeading: CGSize

    /// Uniform corners (`RoundedRectangle`); the caller has already limited the radii.
    init(uniform rx: CGFloat, _ ry: CGFloat) {
        let size = CGSize(width: rx, height: ry)
        topLeading = size; topTrailing = size; bottomTrailing = size; bottomLeading = size
    }

    /// Per-corner radii (`UnevenRoundedRectangle`): each is limited, per adjacent edge, to the
    /// larger of half the edge and the edge minus the neighbouring corner's radius.
    init(uneven radii: RectangleCornerRadii, in rect: CGRect) {
        let w = rect.width, h = rect.height
        func limit(_ r: CGFloat, horizontalNeighbour: CGFloat, verticalNeighbour: CGFloat) -> CGSize {
            let value = max(0, min(r, max(w / 2, w - horizontalNeighbour), max(h / 2, h - verticalNeighbour)))
            return CGSize(width: value, height: value)
        }
        topLeading = limit(radii.topLeading, horizontalNeighbour: radii.topTrailing, verticalNeighbour: radii.bottomLeading)
        topTrailing = limit(radii.topTrailing, horizontalNeighbour: radii.topLeading, verticalNeighbour: radii.bottomTrailing)
        bottomTrailing = limit(radii.bottomTrailing, horizontalNeighbour: radii.bottomLeading, verticalNeighbour: radii.topTrailing)
        bottomLeading = limit(radii.bottomLeading, horizontalNeighbour: radii.bottomTrailing, verticalNeighbour: radii.topLeading)
    }
}

struct _RoundedRect {
    var rect: CGRect
    var radii: _CornerRadii
    var style: RoundedCornerStyle

    /// Unit continuous corner, measured from Apple's paths: (distance back along the incoming
    /// edge, distance along the outgoing edge), each scaled by that axis's radius.
    private static let extent: CGFloat = 1.528665
    private static let control1: CGFloat = 1.08849
    private static let control2: CGFloat = 0.868407
    /// The control points move towards 0.96 and 0.82 as the extent is compressed to 1.
    private static let compressedControl1: CGFloat = 0.96
    private static let compressedControl2: CGFloat = 0.82
    private static let inner: (CGFloat, CGFloat) = (0.631494, 0.0749114)
    private static let middle: (CGFloat, CGFloat) = (0.372824, 0.169060)

    /// How far a continuous corner reaches along an edge shared with a neighbour: the full extent
    /// when the edge has room, otherwise the edge split in proportion to the two radii.
    private static func reach(_ radius: CGFloat, neighbour: CGFloat, edge: CGFloat) -> CGFloat {
        guard radius > 0 else { return 0 }
        return min(extent * radius, edge * radius / (radius + neighbour))
    }

    func add(to path: inout Path, transform: CGAffineTransform) {
        let r = rect, w = r.width, h = r.height
        let br = radii.bottomTrailing, bl = radii.bottomLeading, tl = radii.topLeading, tr = radii.topTrailing
        // Clockwise on screen from the middle of the trailing edge's straight part (between the
        // two corner radii): bottom-trailing, bottom-leading, top-leading, top-trailing. Each
        // corner: the incoming edge direction, the outgoing one, and the reach along each (the
        // radius itself for circular corners).
        path.move(to: CGPoint(x: r.maxX, y: r.minY + (tr.height + h - br.height) / 2).applying(transform))
        let continuous = style == .continuous
        func reach(_ radius: CGFloat, _ neighbour: CGFloat, _ edge: CGFloat) -> CGFloat {
            continuous ? Self.reach(radius, neighbour: neighbour, edge: edge) : radius
        }
        corner(&path, at: CGPoint(x: r.maxX, y: r.maxY), incoming: CGPoint(x: 0, y: 1), outgoing: CGPoint(x: -1, y: 0),
               radiusIn: br.height, radiusOut: br.width,
               reachIn: reach(br.height, tr.height, h), reachOut: reach(br.width, bl.width, w), transform: transform)
        corner(&path, at: CGPoint(x: r.minX, y: r.maxY), incoming: CGPoint(x: -1, y: 0), outgoing: CGPoint(x: 0, y: -1),
               radiusIn: bl.width, radiusOut: bl.height,
               reachIn: reach(bl.width, br.width, w), reachOut: reach(bl.height, tl.height, h), transform: transform)
        corner(&path, at: CGPoint(x: r.minX, y: r.minY), incoming: CGPoint(x: 0, y: -1), outgoing: CGPoint(x: 1, y: 0),
               radiusIn: tl.height, radiusOut: tl.width,
               reachIn: reach(tl.height, bl.height, h), reachOut: reach(tl.width, tr.width, w), transform: transform)
        corner(&path, at: CGPoint(x: r.maxX, y: r.minY), incoming: CGPoint(x: 1, y: 0), outgoing: CGPoint(x: 0, y: 1),
               radiusIn: tr.width, radiusOut: tr.height,
               reachIn: reach(tr.width, tl.width, w), reachOut: reach(tr.height, br.height, h), transform: transform)
        path.closeSubpath()
    }

    private func corner(_ path: inout Path, at c: CGPoint, incoming: CGPoint, outgoing: CGPoint,
                        radiusIn: CGFloat, radiusOut: CGFloat, reachIn: CGFloat, reachOut: CGFloat, transform: CGAffineTransform) {
        /// `a` back along the incoming edge, `b` along the outgoing edge.
        func p(_ a: CGFloat, _ b: CGFloat) -> CGPoint {
            CGPoint(x: c.x - incoming.x * a + outgoing.x * b, y: c.y - incoming.y * a + outgoing.y * b).applying(transform)
        }
        path.addLine(to: p(reachIn, 0))
        switch style {
        case .circular:
            let k = 1 - _kappa
            path.addCurve(to: p(0, radiusOut), control1: p(radiusIn * k, 0), control2: p(0, radiusOut * k))
        case .continuous:
            func controls(_ radius: CGFloat, reach: CGFloat) -> (CGFloat, CGFloat) {
                guard radius > 0 else { return (0, 0) }
                let t = max(0, min(1, (Self.extent * radius - reach) / ((Self.extent - 1) * radius)))
                return ((Self.control1 + (Self.compressedControl1 - Self.control1) * t) * radius,
                        (Self.control2 + (Self.compressedControl2 - Self.control2) * t) * radius)
            }
            let (in1, in2) = controls(radiusIn, reach: reachIn)
            let (out1, out2) = controls(radiusOut, reach: reachOut)
            let (inner, innerAcross) = Self.inner
            let (middle, middleAcross) = Self.middle
            path.addCurve(to: p(inner * radiusIn, innerAcross * radiusOut), control1: p(in1, 0), control2: p(in2, 0))
            path.addCurve(to: p(innerAcross * radiusIn, inner * radiusOut),
                          control1: p(middle * radiusIn, middleAcross * radiusOut), control2: p(middleAcross * radiusIn, middle * radiusOut))
            path.addCurve(to: p(0, reachOut), control1: p(0, out2), control2: p(0, out1))
        }
    }
}
