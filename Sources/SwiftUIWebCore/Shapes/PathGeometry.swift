// Path algorithms: flattening, hit testing, trimming by arc length, dashing and stroking.
// Stroking produces overlapping polygons with one orientation (a nonzero fill unions them), not
// the true offset outline SwiftUI computes; painters stroke natively, this is for clipping and
// hit testing (`Docs/elements/Shape.md`).

/// A flattened subpath.
package struct _Polyline {
    package var points: [CGPoint]
    package var closed: Bool
}

extension CGPoint {
    @inline(__always) fileprivate static func + (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x + b.x, y: a.y + b.y) }
    @inline(__always) fileprivate static func - (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x - b.x, y: a.y - b.y) }
    @inline(__always) fileprivate static func * (a: CGPoint, s: CGFloat) -> CGPoint { CGPoint(x: a.x * s, y: a.y * s) }
    @inline(__always) fileprivate var length: CGFloat { _hypot(x, y) }
    @inline(__always) fileprivate func distance(to other: CGPoint) -> CGFloat { (self - other).length }
    @inline(__always) fileprivate static func lerp(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint { a + (b - a) * t }
}

/// A cubic Bézier segment.
struct _Cubic {
    var p0, c1, c2, p3: CGPoint

    init(_ p0: CGPoint, _ c1: CGPoint, _ c2: CGPoint, _ p3: CGPoint) {
        self.p0 = p0; self.c1 = c1; self.c2 = c2; self.p3 = p3
    }

    /// A quadratic curve raised to a cubic (what SwiftUI emits when it splits one).
    init(quadFrom p0: CGPoint, control: CGPoint, to p1: CGPoint) {
        self.init(p0, CGPoint.lerp(p0, control, 2.0 / 3.0), CGPoint.lerp(p1, control, 2.0 / 3.0), p1)
    }

    func point(at t: CGFloat) -> CGPoint {
        let u = 1 - t
        let a = u * u * u, b = 3 * u * u * t, c = 3 * u * t * t, d = t * t * t
        return CGPoint(x: a * p0.x + b * c1.x + c * c2.x + d * p3.x, y: a * p0.y + b * c1.y + c * c2.y + d * p3.y)
    }

    /// Number of chords that keep the flattening error well under a tenth of a point.
    var steps: Int {
        let polygon = p0.distance(to: c1) + c1.distance(to: c2) + c2.distance(to: p3)
        return max(8, min(96, Int((polygon * 0.75).rounded(.up))))
    }

    /// The chord points from `p0` to `p3`, inclusive.
    func flattened() -> [CGPoint] {
        let n = steps
        var points: [CGPoint] = [p0]
        points.reserveCapacity(n + 1)
        for i in 1..<n { points.append(point(at: CGFloat(i) / CGFloat(n))) }
        points.append(p3)
        return points
    }

    var length: CGFloat {
        let points = flattened()
        var total: CGFloat = 0
        for i in 1..<points.count { total += points[i - 1].distance(to: points[i]) }
        return total
    }

    /// The parameter at which `distance` of the curve's length has been covered.
    func parameter(atLength distance: CGFloat) -> CGFloat {
        let points = flattened()
        var covered: CGFloat = 0
        for i in 1..<points.count {
            let chord = points[i - 1].distance(to: points[i])
            if covered + chord >= distance {
                let local = chord > 0 ? (distance - covered) / chord : 0
                return (CGFloat(i - 1) + local) / CGFloat(points.count - 1)
            }
            covered += chord
        }
        return 1
    }

    /// De Casteljau split: the two halves at `t`.
    func split(at t: CGFloat) -> (_Cubic, _Cubic) {
        let p01 = CGPoint.lerp(p0, c1, t), p12 = CGPoint.lerp(c1, c2, t), p23 = CGPoint.lerp(c2, p3, t)
        let p012 = CGPoint.lerp(p01, p12, t), p123 = CGPoint.lerp(p12, p23, t)
        let mid = CGPoint.lerp(p012, p123, t)
        return (_Cubic(p0, p01, p012, mid), _Cubic(mid, p123, p23, p3))
    }

    /// The portion between parameters `t0` and `t1`.
    func portion(from t0: CGFloat, to t1: CGFloat) -> _Cubic {
        var piece = self
        if t1 < 1 { piece = piece.split(at: t1).0 }
        if t0 > 0 {
            let scaled = t1 > 0 ? t0 / t1 : 0
            piece = piece.split(at: scaled).1
        }
        return piece
    }
}

extension Path {
    /// The subpaths as polylines (curves flattened). Trailing moves are dropped.
    package func _flattened() -> [_Polyline] {
        var result: [_Polyline] = []
        var points: [CGPoint] = []
        var closed = false
        func flush() {
            if points.count > 1 || (points.count == 1 && closed) { result.append(_Polyline(points: points, closed: closed)) }
            points = []
            closed = false
        }
        var subpathStart = CGPoint.zero
        for element in elements {
            switch element {
            case .move(let p):
                flush()
                points = [p]
                subpathStart = p
            case .line(let p):
                if points.isEmpty { points = [subpathStart] }
                points.append(p)
            case .quadCurve(let p, let c):
                if points.isEmpty { points = [subpathStart] }
                points += _Cubic(quadFrom: points.last!, control: c, to: p).flattened().dropFirst()
            case .curve(let p, let c1, let c2):
                if points.isEmpty { points = [subpathStart] }
                points += _Cubic(points.last!, c1, c2, p).flattened().dropFirst()
            case .closeSubpath:
                closed = true
                flush()
                points = []   // a line after a close continues from the subpath start
            }
        }
        flush()
        return result
    }

    /// Whether `point` is inside the path (nonzero winding, or even-odd), treating every subpath
    /// as closed; points on an edge count as inside.
    public func contains(_ point: CGPoint, eoFill: Bool = false) -> Bool {
        var winding = 0
        var crossings = 0
        for polyline in _flattened() {
            let points = polyline.points
            guard points.count > 1 else { continue }
            for i in 0..<points.count {
                let a = points[i], b = points[(i + 1) % points.count]
                // On the segment?
                let ab = b - a, ap = point - a
                let cross = ab.x * ap.y - ab.y * ap.x
                let lengthSquared = ab.x * ab.x + ab.y * ab.y
                if lengthSquared < 1e-18 {
                    if ap.x * ap.x + ap.y * ap.y < 1e-18 { return true }
                    continue
                }
                if abs(cross) < 1e-9 * max(1, lengthSquared) {
                    let dot = ab.x * ap.x + ab.y * ap.y
                    if dot >= -1e-9 && dot <= lengthSquared + 1e-9 { return true }
                }
                // Ray towards +x.
                if (a.y <= point.y) != (b.y <= point.y) {
                    let x = a.x + (point.y - a.y) / (b.y - a.y) * (b.x - a.x)
                    if x > point.x {
                        crossings += 1
                        winding += b.y > a.y ? 1 : -1
                    }
                }
            }
        }
        return eoFill ? crossings % 2 == 1 : winding != 0
    }

    /// The part of the path between two fractions of its total length (segment lengths summed,
    /// closing segments included). `to` at or below `from` gives an empty path.
    public func trimmedPath(from: CGFloat, to: CGFloat) -> Path {
        let from = max(0, min(1, from)), to = max(0, min(1, to))
        guard to > from else { return Path() }

        enum Segment {
            case line(CGPoint, CGPoint)
            case cubic(_Cubic)
            case close(CGPoint, CGPoint)
            case move(CGPoint)

            var length: CGFloat {
                switch self {
                case .line(let a, let b), .close(let a, let b): return a.distance(to: b)
                case .cubic(let c): return c.length
                case .move: return 0
                }
            }
        }
        var segments: [Segment] = []
        var current = CGPoint.zero, start = CGPoint.zero
        for element in elements {
            switch element {
            case .move(let p): segments.append(.move(p)); current = p; start = p
            case .line(let p): segments.append(.line(current, p)); current = p
            case .quadCurve(let p, let c): segments.append(.cubic(_Cubic(quadFrom: current, control: c, to: p))); current = p
            case .curve(let p, let c1, let c2): segments.append(.cubic(_Cubic(current, c1, c2, p))); current = p
            case .closeSubpath: segments.append(.close(current, start)); current = start
            }
        }
        let lengths = segments.map(\.length)
        let total = lengths.reduce(0, +)
        guard total > 0 else { return from == 0 ? self : Path() }
        let startLength = from * total, endLength = to * total

        var result = Path()
        var covered: CGFloat = 0
        var needMove = true
        var subpathIntact = false
        for (segment, length) in zip(segments, lengths) {
            if case .move(let p) = segment {
                if covered >= startLength && covered < endLength {
                    result.move(to: p)
                    needMove = false
                    subpathIntact = true
                } else {
                    needMove = true
                    subpathIntact = false
                }
                continue
            }
            let s0 = covered, s1 = covered + length
            covered = s1
            if length == 0 {
                guard s0 >= startLength && s0 <= endLength else { continue }
            } else if s1 <= startLength || s0 >= endLength {
                if s1 <= startLength { needMove = true }
                continue
            }
            let clippedStart = s0 < startLength, clippedEnd = s1 > endLength
            let l0 = clippedStart ? startLength - s0 : 0
            let l1 = clippedEnd ? endLength - s0 : length
            if clippedStart { subpathIntact = false }
            switch segment {
            case .line(let a, let b), .close(let a, let b):
                let p0 = length > 0 ? CGPoint.lerp(a, b, l0 / length) : a
                let p1 = length > 0 ? CGPoint.lerp(a, b, l1 / length) : b
                if needMove || clippedStart { result.move(to: p0); needMove = false }
                if case .close = segment, subpathIntact, !clippedEnd {
                    result.closeSubpath()
                } else {
                    result.addLine(to: p1)
                }
            case .cubic(let cubic):
                let t0 = clippedStart ? cubic.parameter(atLength: l0) : 0
                let t1 = clippedEnd ? cubic.parameter(atLength: l1) : 1
                let piece = cubic.portion(from: t0, to: t1)
                if needMove || clippedStart { result.move(to: piece.p0); needMove = false }
                result.addCurve(to: piece.p3, control1: piece.c1, control2: piece.c2)
            case .move:
                break
            }
        }
        return result
    }

    /// The outline of the path stroked with `style`, as polygons that a nonzero fill unions.
    public func strokedPath(_ style: StrokeStyle) -> Path {
        var result = Path()
        let halfWidth = max(0, style.lineWidth / 2)
        guard halfWidth > 0 else { return result }
        for polyline in _dashed(style) {
            _stroke(polyline, halfWidth: halfWidth, style: style, into: &result)
        }
        return result
    }

    /// The flattened subpaths cut into dashes (open pieces) when the style has a dash pattern.
    private func _dashed(_ style: StrokeStyle) -> [_Polyline] {
        let polylines = _flattened()
        let pattern = style.dash.filter { $0 >= 0 }
        let period = pattern.reduce(0, +)
        guard !pattern.isEmpty, period > 0 else { return polylines }
        var pieces: [_Polyline] = []
        for polyline in polylines {
            var points = polyline.points
            if polyline.closed, let first = points.first { points.append(first) }
            // Where the pattern starts: index and remaining length of the current entry.
            var phase = style.dashPhase.truncatingRemainder(dividingBy: period)
            if phase < 0 { phase += period }
            var index = 0
            while phase >= pattern[index] {
                phase -= pattern[index]
                index = (index + 1) % pattern.count
                if pattern[index] == 0 && phase == 0 { break }
            }
            var remaining = pattern[index] - phase
            var on = index % 2 == 0
            var dash: [CGPoint] = on ? [points[0]] : []
            for i in 1..<points.count {
                var a = points[i - 1]
                let b = points[i]
                var segmentLeft = a.distance(to: b)
                while segmentLeft > 0 {
                    if remaining >= segmentLeft {
                        remaining -= segmentLeft
                        if on { dash.append(b) }
                        segmentLeft = 0
                    } else {
                        let cut = CGPoint.lerp(a, b, remaining / segmentLeft)
                        if on {
                            dash.append(cut)
                            pieces.append(_Polyline(points: dash, closed: false))
                            dash = []
                        } else {
                            dash = [cut]
                        }
                        on.toggle()
                        segmentLeft -= remaining
                        a = cut
                        index = (index + 1) % pattern.count
                        remaining = pattern[index]
                        if remaining == 0 { remaining = 1e-9 }
                    }
                }
            }
            if on, dash.count > 1 { pieces.append(_Polyline(points: dash, closed: false)) }
        }
        return pieces
    }

    private func _stroke(_ polyline: _Polyline, halfWidth: CGFloat, style: StrokeStyle, into result: inout Path) {
        // Drop repeated points.
        var points: [CGPoint] = []
        for p in polyline.points where points.last.map({ $0.distance(to: p) > 1e-9 }) ?? true { points.append(p) }
        if polyline.closed, points.count > 1, points.first!.distance(to: points.last!) <= 1e-9 { points.removeLast() }
        guard let first = points.first else { return }
        func polygon(_ vertices: [CGPoint]) {
            guard vertices.count >= 3 else { return }
            var area: CGFloat = 0
            for i in 0..<vertices.count {
                let a = vertices[i], b = vertices[(i + 1) % vertices.count]
                area += a.x * b.y - b.x * a.y
            }
            guard abs(area) > 1e-12 else { return }
            let ordered = area > 0 ? vertices : vertices.reversed()
            result.move(to: ordered[0])
            for v in ordered.dropFirst() { result.addLine(to: v) }
            result.closeSubpath()
        }
        func disc(_ center: CGPoint) {
            result.addEllipse(in: CGRect(x: center.x - halfWidth, y: center.y - halfWidth, width: 2 * halfWidth, height: 2 * halfWidth))
        }
        if points.count == 1 {
            switch style.lineCap {
            case .round: disc(first)
            case .square: result.addRect(CGRect(x: first.x - halfWidth, y: first.y - halfWidth, width: 2 * halfWidth, height: 2 * halfWidth))
            default: break
            }
            return
        }
        let closed = polyline.closed && points.count > 2
        let segmentCount = closed ? points.count : points.count - 1
        var directions: [CGPoint] = []
        for i in 0..<segmentCount {
            let a = points[i], b = points[(i + 1) % points.count]
            let d = b - a
            let u = d * (1 / d.length)
            directions.append(u)
            let n = CGPoint(x: -u.y, y: u.x) * halfWidth
            polygon([a + n, b + n, b - n, a - n])
        }
        // Joins.
        let joinRange = closed ? 0..<points.count : 1..<(points.count - 1)
        for i in joinRange {
            let vertex = points[i]
            let dIn = directions[(i - 1 + segmentCount) % segmentCount], dOut = directions[i % segmentCount]
            let cross = dIn.x * dOut.y - dIn.y * dOut.x
            let dot = dIn.x * dOut.x + dIn.y * dOut.y
            guard abs(cross) > 1e-9 || dot < 0 else { continue }
            if style.lineJoin == .round { disc(vertex); continue }
            // Outer side: opposite the turn direction.
            let sign: CGFloat = cross > 0 ? -1 : 1
            let nIn = CGPoint(x: -dIn.y, y: dIn.x) * (halfWidth * sign)
            let nOut = CGPoint(x: -dOut.y, y: dOut.x) * (halfWidth * sign)
            let a = vertex + nIn, b = vertex + nOut
            if style.lineJoin == .miter {
                // Miter length ratio 1 / sin(θ/2), θ the angle between the segments.
                let cosTheta = max(-1, min(1, -dot))
                let halfTheta = _acos(cosTheta) / 2
                let sinHalf = _sin(halfTheta)
                if sinHalf > 1e-9, 1 / sinHalf <= style.miterLimit {
                    let bisector = nIn + nOut
                    let bl = bisector.length
                    if bl > 1e-9 {
                        let tip = vertex + bisector * (halfWidth / sinHalf / bl)
                        polygon([vertex, a, tip, b])
                        continue
                    }
                }
            }
            polygon([vertex, a, b])
        }
        // Caps.
        guard !closed else { return }
        let last = points[points.count - 1]
        switch style.lineCap {
        case .round:
            disc(first)
            disc(last)
        case .square:
            let dStart = directions[0], dEnd = directions[segmentCount - 1]
            let nStart = CGPoint(x: -dStart.y, y: dStart.x) * halfWidth, nEnd = CGPoint(x: -dEnd.y, y: dEnd.x) * halfWidth
            let backStart = first - dStart * halfWidth, forwardEnd = last + dEnd * halfWidth
            polygon([first + nStart, backStart + nStart, backStart - nStart, first - nStart])
            polygon([last + nEnd, forwardEnd + nEnd, forwardEnd - nEnd, last - nEnd])
        default:
            break
        }
    }
}
