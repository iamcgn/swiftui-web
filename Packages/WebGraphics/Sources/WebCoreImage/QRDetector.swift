// Finding a QR code in a picture, for `CIDetector` (Docs/elements/CoreImage.md): the picture's
// grey levels become dark and light pixels (one threshold for the whole picture, then a local
// one), the three finder patterns are found by their 1:1:3:1:1 runs, the bottom-right
// alignment pattern near where they put it, and the modules are sampled through the
// perspective that maps the symbol's grid onto those four points.

#if !canImport(CoreGraphics) || os(WASI)
import WebFoundation

extension QRCode {
    /// A symbol found in a picture: its message and its corners in the picture's pixels
    /// (origin at the top left), in the symbol's own top-left, top-right, bottom-left and
    /// bottom-right order.
    struct Found {
        var decoded: Decoded
        var topLeft: (x: Double, y: Double)
        var topRight: (x: Double, y: Double)
        var bottomLeft: (x: Double, y: Double)
        var bottomRight: (x: Double, y: Double)
    }

    /// The first readable symbol in a picture of `width` by `height` grey levels, row by row
    /// from the top.
    static func find(luminance: [UInt8], width: Int, height: Int) -> Found? {
        guard width >= 21, height >= 21, luminance.count >= width * height else { return nil }
        for local in [false, true] {
            let picture = Picture(dark: local ? localThreshold(luminance, width, height) : globalThreshold(luminance), width: width, height: height)
            if let found = picture.read() { return found }
        }
        return nil
    }

    /// Dark where the grey level is at or below the level that best splits the histogram in two.
    private static func globalThreshold(_ luminance: [UInt8]) -> [Bool] {
        var histogram = [Int](repeating: 0, count: 256)
        for v in luminance { histogram[Int(v)] += 1 }
        let total = Double(luminance.count)
        let sum = (0..<256).reduce(0.0) { $0 + Double($1 * histogram[$1]) }
        var below = 0.0, belowSum = 0.0, bestSpread = 0.0, threshold = 128
        for t in 0..<256 {
            below += Double(histogram[t])
            guard below > 0 else { continue }
            let above = total - below
            guard above > 0 else { break }
            belowSum += Double(t * histogram[t])
            let difference = belowSum / below - (sum - belowSum) / above
            let spread = below * above * difference * difference
            if spread > bestSpread {
                bestSpread = spread
                threshold = t
            }
        }
        return luminance.map { Int($0) <= threshold }
    }

    /// Dark where the grey level is below 92% of its neighbourhood's mean.
    private static func localThreshold(_ luminance: [UInt8], _ width: Int, _ height: Int) -> [Bool] {
        let radius = max(8, min(width, height) / 16)
        var integral = [Int](repeating: 0, count: (width + 1) * (height + 1))
        for y in 0..<height {
            var row = 0
            for x in 0..<width {
                row += Int(luminance[y * width + x])
                integral[(y + 1) * (width + 1) + x + 1] = integral[y * (width + 1) + x + 1] + row
            }
        }
        var dark = [Bool](repeating: false, count: width * height)
        for y in 0..<height {
            let (y0, y1) = (max(0, y - radius), min(height, y + radius + 1))
            for x in 0..<width {
                let (x0, x1) = (max(0, x - radius), min(width, x + radius + 1))
                let sum = integral[y1 * (width + 1) + x1] - integral[y0 * (width + 1) + x1]
                    - integral[y1 * (width + 1) + x0] + integral[y0 * (width + 1) + x0]
                let area = (y1 - y0) * (x1 - x0)
                dark[y * width + x] = Double(luminance[y * width + x]) * Double(area) < Double(sum) * 0.92
            }
        }
        return dark
    }

    /// A row-vector projective transform: (u, v, 1) times the matrix.
    struct Perspective {
        var m: [Double]

        func apply(_ u: Double, _ v: Double) -> (x: Double, y: Double) {
            let w = m[2] * u + m[5] * v + m[8]
            return ((m[0] * u + m[3] * v + m[6]) / w, (m[1] * u + m[4] * v + m[7]) / w)
        }

        /// The unit square's corners (0, 0), (1, 0), (1, 1), (0, 1) onto `p`.
        static func fromSquare(_ p: [(x: Double, y: Double)]) -> Perspective {
            let dx3 = p[0].x - p[1].x + p[2].x - p[3].x
            let dy3 = p[0].y - p[1].y + p[2].y - p[3].y
            if abs(dx3) < 1e-9, abs(dy3) < 1e-9 {
                return Perspective(m: [p[1].x - p[0].x, p[1].y - p[0].y, 0, p[2].x - p[1].x, p[2].y - p[1].y, 0, p[0].x, p[0].y, 1])
            }
            let (dx1, dx2, dy1, dy2) = (p[1].x - p[2].x, p[3].x - p[2].x, p[1].y - p[2].y, p[3].y - p[2].y)
            let denominator = dx1 * dy2 - dx2 * dy1
            let a13 = (dx3 * dy2 - dx2 * dy3) / denominator
            let a23 = (dx1 * dy3 - dx3 * dy1) / denominator
            return Perspective(m: [
                p[1].x - p[0].x + a13 * p[1].x, p[1].y - p[0].y + a13 * p[1].y, a13,
                p[3].x - p[0].x + a23 * p[3].x, p[3].y - p[0].y + a23 * p[3].y, a23,
                p[0].x, p[0].y, 1,
            ])
        }

        /// The inverse up to scale.
        var adjoint: Perspective {
            let (a, b, c, d, e, f, g, h, i) = (m[0], m[1], m[2], m[3], m[4], m[5], m[6], m[7], m[8])
            return Perspective(m: [e * i - f * h, c * h - b * i, b * f - c * e,
                                   f * g - d * i, a * i - c * g, c * d - a * f,
                                   d * h - e * g, b * g - a * h, a * e - b * d])
        }

        /// This transform, then `next`.
        func then(_ next: Perspective) -> Perspective {
            var r = [Double](repeating: 0, count: 9)
            for row in 0..<3 {
                for col in 0..<3 {
                    r[row * 3 + col] = (0..<3).reduce(0.0) { $0 + m[row * 3 + $1] * next.m[$1 * 3 + col] }
                }
            }
            return Perspective(m: r)
        }

        /// The quadrilateral `from` onto the quadrilateral `to`, corner by corner.
        static func mapping(_ from: [(x: Double, y: Double)], to: [(x: Double, y: Double)]) -> Perspective {
            fromSquare(from).adjoint.then(fromSquare(to))
        }
    }

    /// A finder pattern's centre, module size and how many scans found it.
    fileprivate struct Finder {
        var x: Double
        var y: Double
        var module: Double
        var hits: Int
    }

    fileprivate struct Picture {
        let dark: [Bool]
        let width: Int
        let height: Int

        func at(_ x: Int, _ y: Int) -> Bool { x >= 0 && x < width && y >= 0 && y < height && dark[y * width + x] }
        func inside(_ x: Int, _ y: Int) -> Bool { x >= 0 && x < width && y >= 0 && y < height }
        func at(_ x: Double, _ y: Double) -> Bool {
            guard x.isFinite, y.isFinite, abs(x) < 1e7, abs(y) < 1e7 else { return false }
            return at(Int(x.rounded(.down)), Int(y.rounded(.down)))
        }

        static func ratioMatches(_ c: [Int]) -> Bool {
            let total = c.reduce(0, +)
            guard total >= 7 else { return false }
            let module = Double(total) / 7, tolerance = module / 2
            func near(_ count: Int, _ modules: Double) -> Bool { abs(Double(count) - module * modules) < tolerance * modules }
            return near(c[0], 1) && near(c[1], 1) && near(c[2], 3) && near(c[3], 1) && near(c[4], 1)
        }

        /// The runs through (x, y) along (dx, dy): the centre's offset from (x, y) along that
        /// line and the runs' total length, when they are in 1:1:3:1:1.
        func crossCheck(_ x: Int, _ y: Int, _ dx: Int, _ dy: Int, limit: Int) -> (offset: Double, total: Int)? {
            var c = [0, 0, 0, 0, 0]
            var (px, py) = (x, y)
            while inside(px, py), at(px, py) { c[2] += 1; px -= dx; py -= dy }
            while inside(px, py), !at(px, py), c[1] <= limit { c[1] += 1; px -= dx; py -= dy }
            while inside(px, py), at(px, py), c[0] <= limit { c[0] += 1; px -= dx; py -= dy }
            (px, py) = (x + dx, y + dy)
            while inside(px, py), at(px, py) { c[2] += 1; px += dx; py += dy }
            while inside(px, py), !at(px, py), c[3] <= limit { c[3] += 1; px += dx; py += dy }
            while inside(px, py), at(px, py), c[4] <= limit { c[4] += 1; px += dx; py += dy }
            guard Self.ratioMatches(c) else { return nil }
            let end = (px - x) * dx + (py - y) * dy
            return (Double(end - c[4] - c[3]) - Double(c[2]) / 2, c.reduce(0, +))
        }

        /// Scans every row for finder patterns, checking each down its column and back along its row.
        func finders() -> [Finder] {
            var found: [Finder] = []
            func check(_ c: [Int], end: Int, row: Int) {
                let total = c.reduce(0, +)
                let cx = Int((Double(end - c[4] - c[3]) - Double(c[2]) / 2).rounded(.down))
                guard let vertical = crossCheck(cx, row, 0, 1, limit: total) else { return }
                let cy = Double(row) + vertical.offset
                let iy = Int(cy.rounded(.down))
                guard let horizontal = crossCheck(cx, iy, 1, 0, limit: total) else { return }
                let fx = Double(cx) + horizontal.offset
                let module = Double(total + vertical.total + horizontal.total) / 21
                for i in found.indices {
                    let f = found[i]
                    if abs(f.x - fx) <= module, abs(f.y - cy) <= module, abs(f.module - module) <= max(1, module / 2) {
                        let n = Double(f.hits)
                        found[i] = Finder(x: (f.x * n + fx) / (n + 1), y: (f.y * n + cy) / (n + 1),
                                          module: (f.module * n + module) / (n + 1), hits: f.hits + 1)
                        return
                    }
                }
                found.append(Finder(x: fx, y: cy, module: module, hits: 1))
            }
            for y in 0..<height {
                var c = [0, 0, 0, 0, 0]
                var state = 0
                for x in 0..<width {
                    let d = dark[y * width + x]
                    if state % 2 == 0 {
                        if d {
                            c[state] += 1
                        } else if state == 4 {
                            if Self.ratioMatches(c) { check(c, end: x, row: y) }
                            c = [c[2], c[3], c[4], 1, 0]
                            state = 3
                        } else {
                            state += 1
                            c[state] += 1
                        }
                    } else if !d {
                        c[state] += 1
                    } else {
                        state += 1
                        c[state] += 1
                    }
                }
                if state == 4, Self.ratioMatches(c) { check(c, end: width, row: y) }
            }
            return found
        }

        /// Three finders that could be one symbol's, best first: top left, top right, bottom left.
        func triples(_ finders: [Finder]) -> [(Finder, Finder, Finder)] {
            let confirmed = finders.filter { $0.hits >= 2 }
            let pool = Array((confirmed.count >= 3 ? confirmed : finders).sorted { $0.hits > $1.hits }.prefix(12))
            var scored: [(Double, (Finder, Finder, Finder))] = []
            guard pool.count >= 3 else { return [] }
            for i in 0..<pool.count {
                for j in (i + 1)..<pool.count {
                    for k in (j + 1)..<pool.count {
                        let p = [pool[i], pool[j], pool[k]]
                        let modules = p.map(\.module)
                        guard let small = modules.min(), let large = modules.max(), large <= small * 1.4 else { continue }
                        // The corner opposite the longest side is the top left.
                        let sides = [(distance(p[1], p[2]), 0), (distance(p[0], p[2]), 1), (distance(p[0], p[1]), 2)].sorted { $0.0 < $1.0 }
                        let (a, b, hypotenuse) = (sides[0].0, sides[1].0, sides[2].0)
                        guard b > 0, hypotenuse > 0 else { continue }
                        let error = abs(a - b) / b + abs(hypotenuse - (a * a + b * b).squareRoot()) / hypotenuse
                        guard error <= 0.5 else { continue }
                        let corner = p[sides[2].1]
                        let others = p.indices.filter { $0 != sides[2].1 }.map { p[$0] }
                        let turn = (others[0].x - corner.x) * (others[1].y - corner.y) - (others[0].y - corner.y) * (others[1].x - corner.x)
                        let (topRight, bottomLeft) = turn > 0 ? (others[0], others[1]) : (others[1], others[0])
                        scored.append((error + (large - small) / small, (corner, topRight, bottomLeft)))
                    }
                }
            }
            return scored.sorted { $0.0 < $1.0 }.map { $0.1 }
        }

        func distance(_ a: Finder, _ b: Finder) -> Double {
            ((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y)).squareRoot()
        }

        /// The length of a finder's runs along the unit vector (ux, uy) through its centre: from
        /// the centre out to the far edge of the dark ring, both ways.
        func ringWidth(_ f: Finder, _ ux: Double, _ uy: Double) -> Int {
            var total = 0
            for sign in [1.0, -1.0] {
                var state = 0, steps = 0
                while steps < 4000 {
                    let (x, y) = (f.x + sign * ux * Double(steps), f.y + sign * uy * Double(steps))
                    let (ix, iy) = (Int(x.rounded(.down)), Int(y.rounded(.down)))
                    guard inside(ix, iy) else { break }
                    let d = at(ix, iy)
                    if state == 0, !d { state = 1 } else if state == 1, d { state = 2 } else if state == 2, !d { break }
                    steps += 1
                }
                total += steps
            }
            return total - 1
        }

        /// The module size along the line from `a` to `b`, from both finders' widths on it.
        func module(from a: Finder, to b: Finder) -> Double {
            let length = distance(a, b)
            guard length > 0 else { return 0 }
            let (ux, uy) = ((b.x - a.x) / length, (b.y - a.y) / length)
            return Double(ringWidth(a, ux, uy) + ringWidth(b, ux, uy)) / 14
        }

        /// Where the bottom-right alignment pattern is, searched for near where the finders put it.
        func alignment(_ tl: Finder, _ tr: Finder, _ bl: Finder, dimension: Int, module: Double) -> (x: Double, y: Double)? {
            let span = Double(dimension - 7)
            let (fx, fy) = ((tr.x - tl.x) / span, (tr.y - tl.y) / span)
            let (gx, gy) = ((bl.x - tl.x) / span, (bl.y - tl.y) / span)
            let u = Double(dimension) - 10
            let (ex, ey) = (tl.x + (fx + gx) * u, tl.y + (fy + gy) * u)
            let radius = Int(module * 6) + 2
            let step = max(1, Int(module / 3))
            var best: (score: Int, x: Int, y: Int, distance: Double)?
            for yy in stride(from: Int(ey) - radius, through: Int(ey) + radius, by: step) {
                for xx in stride(from: Int(ex) - radius, through: Int(ex) + radius, by: step) {
                    var score = 0
                    for j in -2...2 {
                        for i in -2...2 {
                            let want = max(abs(i), abs(j)) != 1
                            let (px, py) = (Double(xx) + fx * Double(i) + gx * Double(j), Double(yy) + fy * Double(i) + gy * Double(j))
                            if at(px, py) == want { score += 1 }
                        }
                    }
                    let d = ((Double(xx) - ex) * (Double(xx) - ex) + (Double(yy) - ey) * (Double(yy) - ey)).squareRoot()
                    if best == nil || score > best!.score || (score == best!.score && d < best!.distance) {
                        best = (score, xx, yy, d)
                    }
                }
            }
            guard let best, best.score >= 23 else { return nil }
            return (Double(best.x) + 0.5, Double(best.y) + 0.5)
        }

        func sample(_ transform: Perspective, dimension: Int) -> [[Bool]] {
            (0..<dimension).map { y in
                (0..<dimension).map { x in
                    let p = transform.apply(Double(x) + 0.5, Double(y) + 0.5)
                    return at(p.x, p.y)
                }
            }
        }

        func read() -> Found? {
            for (tl, tr, bl) in triples(finders()).prefix(6) {
                let (m1, m2) = (module(from: tl, to: tr), module(from: tl, to: bl))
                guard m1 > 0, m2 > 0 else { continue }
                let estimate = (distance(tl, tr) / m1 + distance(tl, bl) / m2) / 2 + 7
                let spread = max(4, estimate * 0.08)
                let dimensions = stride(from: 21, through: 177, by: 4).filter { abs(Double($0) - estimate) <= spread }
                    .sorted { abs(Double($0) - estimate) < abs(Double($1) - estimate) }
                for dimension in dimensions {
                    let d = Double(dimension)
                    let br = (x: tr.x + bl.x - tl.x, y: tr.y + bl.y - tl.y)
                    var transforms: [Perspective] = []
                    if dimension > 21, let a = alignment(tl, tr, bl, dimension: dimension, module: (m1 + m2) / 2) {
                        transforms.append(.mapping([(3.5, 3.5), (d - 3.5, 3.5), (d - 6.5, d - 6.5), (3.5, d - 3.5)],
                                                   to: [(tl.x, tl.y), (tr.x, tr.y), a, (bl.x, bl.y)]))
                    }
                    transforms.append(.mapping([(3.5, 3.5), (d - 3.5, 3.5), (d - 3.5, d - 3.5), (3.5, d - 3.5)],
                                               to: [(tl.x, tl.y), (tr.x, tr.y), br, (bl.x, bl.y)]))
                    for transform in transforms {
                        let modules = sample(transform, dimension: dimension)
                        // A mirrored symbol reads with its rows and columns swapped.
                        let mirrored = (0..<dimension).map { y in (0..<dimension).map { x in modules[x][y] } }
                        for (matrix, flipped) in [(modules, false), (mirrored, true)] {
                            guard let decoded = QRCode.decode(matrix) else { continue }
                            func corner(_ u: Double, _ v: Double) -> (x: Double, y: Double) {
                                flipped ? transform.apply(v, u) : transform.apply(u, v)
                            }
                            return Found(decoded: decoded, topLeft: corner(0, 0), topRight: corner(d, 0),
                                         bottomLeft: corner(0, d), bottomRight: corner(d, d))
                        }
                    }
                }
            }
            return nil
        }
    }
}
#endif
