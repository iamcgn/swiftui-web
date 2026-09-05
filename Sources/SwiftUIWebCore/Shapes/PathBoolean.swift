// Boolean operations on paths: both paths are flattened to polygons, every edge is split at
// the intersections with the other path, each fragment is classified by whether its middle
// lies inside the other path (winding or even-odd), the fragments the operation keeps are
// chained back into loops, and holes are oriented against their containers so a non-zero
// fill paints the result. Curves are flattened to 16 segments, so curved boundaries are
// polygonal at sub-pixel scale.

package enum PathBooleanOperation {
    case union, intersection, subtraction, symmetricDifference
}

extension Path {
    /// The closed polygons of the path (curves flattened, open subpaths closed).
    package func flattenedPolygons(segments: Int = 16) -> [[CGPoint]] {
        var polygons: [[CGPoint]] = []
        var current: [CGPoint] = []
        var start = CGPoint.zero
        func finish() {
            if current.count >= 3 { polygons.append(current) }
            current = []
        }
        forEach { element in
            switch element {
            case .move(let to):
                finish()
                current = [to]
                start = to
            case .line(let to):
                current.append(to)
            case .quadCurve(let to, let control):
                let from = current.last ?? start
                for i in 1...segments {
                    let t = CGFloat(i) / CGFloat(segments), u = 1 - t
                    current.append(CGPoint(x: u * u * from.x + 2 * u * t * control.x + t * t * to.x,
                                           y: u * u * from.y + 2 * u * t * control.y + t * t * to.y))
                }
            case .curve(let to, let c1, let c2):
                let from = current.last ?? start
                for i in 1...segments {
                    let t = CGFloat(i) / CGFloat(segments), u = 1 - t
                    current.append(CGPoint(x: u * u * u * from.x + 3 * u * u * t * c1.x + 3 * u * t * t * c2.x + t * t * t * to.x,
                                           y: u * u * u * from.y + 3 * u * u * t * c1.y + 3 * u * t * t * c2.y + t * t * t * to.y))
                }
            case .closeSubpath:
                finish()
                current = [start]
            }
        }
        finish()
        return polygons.map { polygon in
            // Drop a closing point equal to the first.
            if polygon.count > 1, let first = polygon.first, let last = polygon.last, first._distance(to: last) < 1e-6 {
                return Array(polygon.dropLast())
            }
            return polygon
        }.filter { $0.count >= 3 }
    }

    /// The open polylines of the path (curves flattened), for the line operations.
    package func flattenedPolylines(segments: Int = 16) -> [[CGPoint]] {
        var lines: [[CGPoint]] = []
        var current: [CGPoint] = []
        var start = CGPoint.zero
        func finish() {
            if current.count >= 2 { lines.append(current) }
            current = []
        }
        forEach { element in
            switch element {
            case .move(let to):
                finish()
                current = [to]
                start = to
            case .line(let to):
                current.append(to)
            case .quadCurve(let to, let control):
                let from = current.last ?? start
                for i in 1...segments {
                    let t = CGFloat(i) / CGFloat(segments), u = 1 - t
                    current.append(CGPoint(x: u * u * from.x + 2 * u * t * control.x + t * t * to.x,
                                           y: u * u * from.y + 2 * u * t * control.y + t * t * to.y))
                }
            case .curve(let to, let c1, let c2):
                let from = current.last ?? start
                for i in 1...segments {
                    let t = CGFloat(i) / CGFloat(segments), u = 1 - t
                    current.append(CGPoint(x: u * u * u * from.x + 3 * u * u * t * c1.x + 3 * u * t * t * c2.x + t * t * t * to.x,
                                           y: u * u * u * from.y + 3 * u * u * t * c1.y + 3 * u * t * t * c2.y + t * t * t * to.y))
                }
            case .closeSubpath:
                if let first = current.first { current.append(first) }
                finish()
                current = [start]
            }
        }
        finish()
        return lines
    }

    /// Combines this path with `other`.
    package func combined(_ operation: PathBooleanOperation, with other: Path, eoFill: Bool = false, otherEOFill: Bool = false) -> Path {
        let a = PathBoolean.normalised(flattenedPolygons()), b = PathBoolean.normalised(other.flattenedPolygons())
        let fragmentsA = PathBoolean.fragments(of: a, cutBy: b)
        let fragmentsB = PathBoolean.fragments(of: b, cutBy: a)
        var kept: [PathBoolean.Fragment] = []
        for f in fragmentsA {
            let inside = PathBoolean.contains(b, f.midpoint, evenOdd: otherEOFill)
            let onEdge = PathBoolean.onBoundary(b, f.midpoint)
            switch operation {
            case .union: if !inside || onEdge { kept.append(f) }
            case .intersection: if inside || onEdge { kept.append(f) }
            case .subtraction: if !inside && !onEdge { kept.append(f) }
            case .symmetricDifference: if !onEdge { kept.append(inside ? f.reversed : f) }
            }
        }
        for f in fragmentsB {
            let inside = PathBoolean.contains(a, f.midpoint, evenOdd: eoFill)
            let onEdge = PathBoolean.onBoundary(a, f.midpoint)
            if onEdge { continue }      // shared boundary: A's copy is kept
            switch operation {
            case .union: if !inside { kept.append(f) }
            case .intersection: if inside { kept.append(f) }
            case .subtraction: if inside { kept.append(f.reversed) }
            case .symmetricDifference: kept.append(inside ? f.reversed : f)
            }
        }
        return PathBoolean.path(chaining: kept)
    }

    /// The parts of this path's outline inside (or outside) `other`, as open lines.
    package func lineClipped(by other: Path, keepInside: Bool, otherEOFill: Bool = false) -> Path {
        let b = other.flattenedPolygons()
        var result = Path()
        for line in flattenedPolylines() {
            var run: [CGPoint] = []
            for i in 0..<(line.count - 1) {
                let p0 = line[i], p1 = line[i + 1]
                var ts: [CGFloat] = [0, 1]
                for polygon in b {
                    for j in 0..<polygon.count {
                        if let t = PathBoolean.intersection(p0, p1, polygon[j], polygon[(j + 1) % polygon.count]).0 { ts.append(t) }
                    }
                }
                ts.sort()
                for k in 0..<(ts.count - 1) where ts[k + 1] - ts[k] > 1e-9 {
                    let s = PathBoolean.lerp(p0, p1, ts[k]), e = PathBoolean.lerp(p0, p1, ts[k + 1])
                    let inside = PathBoolean.contains(b, PathBoolean.lerp(s, e, 0.5), evenOdd: otherEOFill)
                    if inside == keepInside {
                        if run.isEmpty || run.last!._distance(to: s) > 1e-6 {
                            if run.count >= 2 { result.addLines(run) }
                            run = [s]
                        }
                        run.append(e)
                    }
                }
            }
            if run.count >= 2 { result.addLines(run) }
        }
        return result
    }
}

package enum PathBoolean {
    package struct Fragment {
        var start: CGPoint
        var end: CGPoint
        var midpoint: CGPoint { CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2) }
        var reversed: Fragment { Fragment(start: end, end: start) }
    }

    /// Outer loops turned positive, loops nested an odd number deep turned negative, so the
    /// fragments of both paths chain consistently whatever way they were drawn.
    static func normalised(_ polygons: [[CGPoint]]) -> [[CGPoint]] {
        polygons.enumerated().map { i, polygon in
            let depth = polygons.enumerated().filter { $0.offset != i && contains([$0.element], polygon[0], evenOdd: true) }.count
            let wantsPositive = depth % 2 == 0
            return (signedArea(polygon) >= 0) == wantsPositive ? polygon : polygon.reversed()
        }
    }

    static func lerp(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
        CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
    }

    /// Parameters (t on the first segment, u on the second) where two segments cross, if they do.
    static func intersection(_ p0: CGPoint, _ p1: CGPoint, _ q0: CGPoint, _ q1: CGPoint) -> (CGFloat?, CGFloat?) {
        let r = CGPoint(x: p1.x - p0.x, y: p1.y - p0.y), s = CGPoint(x: q1.x - q0.x, y: q1.y - q0.y)
        let denominator = r.x * s.y - r.y * s.x
        guard abs(denominator) > 1e-12 else { return (nil, nil) }
        let qp = CGPoint(x: q0.x - p0.x, y: q0.y - p0.y)
        let t = (qp.x * s.y - qp.y * s.x) / denominator
        let u = (qp.x * r.y - qp.y * r.x) / denominator
        guard t >= -1e-9, t <= 1 + 1e-9, u >= -1e-9, u <= 1 + 1e-9 else { return (nil, nil) }
        return (min(1, max(0, t)), min(1, max(0, u)))
    }

    /// The edges of `polygons` split wherever an edge of `cutters` crosses them.
    static func fragments(of polygons: [[CGPoint]], cutBy cutters: [[CGPoint]]) -> [Fragment] {
        var result: [Fragment] = []
        for polygon in polygons {
            for i in 0..<polygon.count {
                let p0 = polygon[i], p1 = polygon[(i + 1) % polygon.count]
                var ts: [CGFloat] = [0, 1]
                for cutter in cutters {
                    for j in 0..<cutter.count {
                        if let t = intersection(p0, p1, cutter[j], cutter[(j + 1) % cutter.count]).0 { ts.append(t) }
                    }
                }
                ts.sort()
                for k in 0..<(ts.count - 1) where ts[k + 1] - ts[k] > 1e-9 {
                    result.append(Fragment(start: lerp(p0, p1, ts[k]), end: lerp(p0, p1, ts[k + 1])))
                }
            }
        }
        return result
    }

    /// Whether `point` lies inside `polygons` by the winding (or even-odd) rule.
    package static func contains(_ polygons: [[CGPoint]], _ point: CGPoint, evenOdd: Bool) -> Bool {
        var winding = 0
        var crossings = 0
        for polygon in polygons {
            for i in 0..<polygon.count {
                let a = polygon[i], b = polygon[(i + 1) % polygon.count]
                if a.y <= point.y {
                    if b.y > point.y, cross(a, b, point) > 0 { winding += 1; crossings += 1 }
                } else if b.y <= point.y, cross(a, b, point) < 0 {
                    winding -= 1; crossings += 1
                }
            }
        }
        return evenOdd ? crossings % 2 == 1 : winding != 0
    }

    /// Whether `point` lies on an edge of `polygons` (within a hair).
    static func onBoundary(_ polygons: [[CGPoint]], _ point: CGPoint) -> Bool {
        for polygon in polygons {
            for i in 0..<polygon.count {
                let a = polygon[i], b = polygon[(i + 1) % polygon.count]
                let length2 = (b.x - a.x) * (b.x - a.x) + (b.y - a.y) * (b.y - a.y)
                guard length2 > 0 else { continue }
                let t = max(0, min(1, ((point.x - a.x) * (b.x - a.x) + (point.y - a.y) * (b.y - a.y)) / length2))
                if lerp(a, b, t)._distance(to: point) < 1e-6 { return true }
            }
        }
        return false
    }

    static func cross(_ a: CGPoint, _ b: CGPoint, _ p: CGPoint) -> CGFloat {
        (b.x - a.x) * (p.y - a.y) - (p.x - a.x) * (b.y - a.y)
    }

    /// Chains fragments end to start into loops and orients holes against their containers.
    static func path(chaining fragments: [Fragment]) -> Path {
        func key(_ p: CGPoint) -> String { "\(Int((p.x * 1e4).rounded())),\(Int((p.y * 1e4).rounded()))" }
        var byStart: [String: [Int]] = [:]
        for (index, fragment) in fragments.enumerated() { byStart[key(fragment.start), default: []].append(index) }
        var used = Array(repeating: false, count: fragments.count)
        var loops: [[CGPoint]] = []
        for index in fragments.indices where !used[index] {
            var loop: [CGPoint] = [fragments[index].start]
            var current = index
            used[current] = true
            var guardCount = 0
            while guardCount < fragments.count + 1 {
                guardCount += 1
                let end = fragments[current].end
                loop.append(end)
                guard let candidates = byStart[key(end)], let next = candidates.first(where: { !used[$0] }) else { break }
                used[next] = true
                current = next
                if key(fragments[current].end) == key(loop[0]) {
                    used[current] = true
                    break
                }
            }
            if loop.count >= 3 {
                if let first = loop.first, let last = loop.last, first._distance(to: last) < 1e-6 { loop.removeLast() }
                if loop.count >= 3 { loops.append(loop) }
            }
        }
        // Outer loops turn one way, loops inside an odd number of others the other way.
        var path = Path()
        for (i, loop) in loops.enumerated() {
            let depth = loops.enumerated().filter { $0.offset != i && contains([$0.element], loop[0], evenOdd: true) }.count
            let area = signedArea(loop)
            let wantsPositive = depth % 2 == 0
            let oriented = (area >= 0) == wantsPositive ? loop : loop.reversed()
            path.move(to: oriented[0])
            for point in oriented.dropFirst() { path.addLine(to: point) }
            path.closeSubpath()
        }
        return path
    }

    package static func signedArea(_ polygon: [CGPoint]) -> CGFloat {
        var area: CGFloat = 0
        for i in 0..<polygon.count {
            let a = polygon[i], b = polygon[(i + 1) % polygon.count]
            area += a.x * b.y - b.x * a.y
        }
        return area / 2
    }
}

// MARK: - Shape operations

/// A shape made from two shapes by a boolean operation.
public struct _BooleanShape<A: Shape, B: Shape> {
    public var a: A
    public var b: B
    package var operation: PathBooleanOperation
    package var eoFill: Bool
    package var otherEOFill: Bool

    package init(a: A, b: B, operation: PathBooleanOperation, eoFill: Bool, otherEOFill: Bool) {
        self.a = a
        self.b = b
        self.operation = operation
        self.eoFill = eoFill
        self.otherEOFill = otherEOFill
    }
}

extension _BooleanShape: Shape {
    nonisolated public func path(in rect: CGRect) -> Path {
        a.path(in: rect).combined(operation, with: b.path(in: rect), eoFill: eoFill, otherEOFill: otherEOFill)
    }

    nonisolated public func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize { a.sizeThatFits(proposal) }

    public typealias AnimatableData = AnimatablePair<A.AnimatableData, B.AnimatableData>
    public var animatableData: AnimatableData {
        get { .init(a.animatableData, b.animatableData) }
        set { a.animatableData = newValue.first; b.animatableData = newValue.second }
    }
}

/// The parts of a shape's outline inside or outside another shape.
public struct _LineClippedShape<A: Shape, B: Shape> {
    public var a: A
    public var b: B
    package var keepInside: Bool
    package var otherEOFill: Bool

    package init(a: A, b: B, keepInside: Bool, otherEOFill: Bool) {
        self.a = a
        self.b = b
        self.keepInside = keepInside
        self.otherEOFill = otherEOFill
    }
}

extension _LineClippedShape: Shape {
    nonisolated public func path(in rect: CGRect) -> Path {
        a.path(in: rect).lineClipped(by: b.path(in: rect), keepInside: keepInside, otherEOFill: otherEOFill)
    }

    nonisolated public func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize { a.sizeThatFits(proposal) }
    public static var role: ShapeRole { .stroke }

    public typealias AnimatableData = AnimatablePair<A.AnimatableData, B.AnimatableData>
    public var animatableData: AnimatableData {
        get { .init(a.animatableData, b.animatableData) }
        set { a.animatableData = newValue.first; b.animatableData = newValue.second }
    }
}

extension Shape {
    /// The area covered by this shape or `other`.
    nonisolated public func union<T: Shape>(_ other: T, eoFill: Bool = false) -> some Shape {
        _BooleanShape(a: self, b: other, operation: .union, eoFill: eoFill, otherEOFill: eoFill)
    }

    /// The area covered by both this shape and `other`.
    nonisolated public func intersection<T: Shape>(_ other: T, eoFill: Bool = false) -> some Shape {
        _BooleanShape(a: self, b: other, operation: .intersection, eoFill: eoFill, otherEOFill: eoFill)
    }

    /// This shape's area with `other`'s removed.
    nonisolated public func subtracting<T: Shape>(_ other: T, eoFill: Bool = false) -> some Shape {
        _BooleanShape(a: self, b: other, operation: .subtraction, eoFill: eoFill, otherEOFill: eoFill)
    }

    /// The area covered by exactly one of this shape and `other`.
    nonisolated public func symmetricDifference<T: Shape>(_ other: T, eoFill: Bool = false) -> some Shape {
        _BooleanShape(a: self, b: other, operation: .symmetricDifference, eoFill: eoFill, otherEOFill: eoFill)
    }

    /// The parts of this shape's outline inside `other`.
    nonisolated public func lineIntersection<T: Shape>(_ other: T, eoFill: Bool = false) -> some Shape {
        _LineClippedShape(a: self, b: other, keepInside: true, otherEOFill: eoFill)
    }

    /// The parts of this shape's outline outside `other`.
    nonisolated public func lineSubtraction<T: Shape>(_ other: T, eoFill: Bool = false) -> some Shape {
        _LineClippedShape(a: self, b: other, keepInside: false, otherEOFill: eoFill)
    }
}

extension CGPoint {
    package func _distance(to other: CGPoint) -> CGFloat {
        ((x - other.x) * (x - other.x) + (y - other.y) * (y - other.y)).squareRoot()
    }
}
