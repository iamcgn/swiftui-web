// A mesh gradient rasterised into a bitmap (SwiftUI's `MeshGradient`): a grid of positioned
// colours joined by bicubic patches whose tangents come from the neighbouring points, the
// colours interpolated bicubically (smooth) or bilinearly, in device sRGB or Oklab
// (`Docs/elements/Gradient.md`). Painters draw the result as a `drawBitmap`.

public struct MeshDescription: Equatable, Sendable {
    public var width: Int
    public var height: Int
    /// Row-major positions in unit space (0…1 across the painted bounds).
    public var points: [CGPoint]
    /// Row-major straight-alpha colours.
    public var colors: [RGBA]
    public var background: RGBA
    public var smoothsColors: Bool
    /// Interpolate colours in Oklab rather than sRGB components.
    public var perceptual: Bool

    public init(width: Int, height: Int, points: [CGPoint], colors: [RGBA], background: RGBA, smoothsColors: Bool, perceptual: Bool) {
        self.width = width
        self.height = height
        self.points = points
        self.colors = colors
        self.background = background
        self.smoothsColors = smoothsColors
        self.perceptual = perceptual
    }
}

public enum MeshRasterizer {
    /// The mesh over `size` points at `scale` pixels per point.
    public static func rasterize(_ mesh: MeshDescription, size: CGSize, scale: CGFloat) -> DisplayBitmap {
        let pixelWidth = max(1, Int((size.width * scale).rounded(.up)))
        let pixelHeight = max(1, Int((size.height * scale).rounded(.up)))
        var raster = Raster(width: pixelWidth, height: pixelHeight, background: mesh.background)
        guard mesh.width >= 2, mesh.height >= 2, mesh.points.count == mesh.width * mesh.height, mesh.colors.count == mesh.points.count else {
            return raster.bitmap
        }
        let grid = Grid(mesh, size: size, scale: scale)
        for row in 0..<(mesh.height - 1) {
            for column in 0..<(mesh.width - 1) {
                grid.rasterize(cell: (column, row), into: &raster)
            }
        }
        return raster.bitmap
    }

    /// A colour as four interpolable channels (sRGB components or Oklab plus alpha).
    struct Channels {
        var a, b, c, alpha: Double
        static func + (l: Channels, r: Channels) -> Channels { Channels(a: l.a + r.a, b: l.b + r.b, c: l.c + r.c, alpha: l.alpha + r.alpha) }
        static func - (l: Channels, r: Channels) -> Channels { Channels(a: l.a - r.a, b: l.b - r.b, c: l.c - r.c, alpha: l.alpha - r.alpha) }
        static func * (l: Channels, s: Double) -> Channels { Channels(a: l.a * s, b: l.b * s, c: l.c * s, alpha: l.alpha * s) }
    }

    /// The mesh in pixel space with its tangents.
    struct Grid {
        let width: Int, height: Int
        let points: [CGPoint]
        let channels: [Channels]
        let smooth: Bool
        let perceptual: Bool

        init(_ mesh: MeshDescription, size: CGSize, scale: CGFloat) {
            width = mesh.width
            height = mesh.height
            points = mesh.points.map { CGPoint(x: $0.x * size.width * scale, y: $0.y * size.height * scale) }
            perceptual = mesh.perceptual
            channels = mesh.colors.map { Grid.channels($0, perceptual: mesh.perceptual) }
            smooth = mesh.smoothsColors
        }

        static func channels(_ color: RGBA, perceptual: Bool) -> Channels {
            if perceptual {
                let lab = _Oklab(color)
                return Channels(a: lab.L, b: lab.a, c: lab.b, alpha: color.alpha)
            }
            return Channels(a: color.red, b: color.green, c: color.blue, alpha: color.alpha)
        }

        func color(_ channels: Channels) -> RGBA {
            if perceptual { return _Oklab(L: channels.a, a: channels.b, b: channels.c).rgba(alpha: min(max(channels.alpha, 0), 1)) }
            return RGBA(red: min(max(channels.a, 0), 1), green: min(max(channels.b, 0), 1), blue: min(max(channels.c, 0), 1), alpha: min(max(channels.alpha, 0), 1))
        }

        func point(_ column: Int, _ row: Int) -> CGPoint { points[row * width + column] }
        func channel(_ column: Int, _ row: Int) -> Channels { channels[row * width + column] }

        /// Catmull-Rom tangent along the columns at a vertex (one-sided at the edges), halved
        /// so a Hermite segment spans one cell.
        func tangentU(_ column: Int, _ row: Int) -> CGPoint {
            let previous = point(max(column - 1, 0), row), next = point(min(column + 1, width - 1), row)
            let span = CGFloat(min(column + 1, width - 1) - max(column - 1, 0))
            return CGPoint(x: (next.x - previous.x) / span, y: (next.y - previous.y) / span)
        }
        func tangentV(_ column: Int, _ row: Int) -> CGPoint {
            let previous = point(column, max(row - 1, 0)), next = point(column, min(row + 1, height - 1))
            let span = CGFloat(min(row + 1, height - 1) - max(row - 1, 0))
            return CGPoint(x: (next.x - previous.x) / span, y: (next.y - previous.y) / span)
        }
        func colorTangentU(_ column: Int, _ row: Int) -> Channels {
            let previous = channel(max(column - 1, 0), row), next = channel(min(column + 1, width - 1), row)
            return (next - previous) * (1 / Double(min(column + 1, width - 1) - max(column - 1, 0)))
        }
        func colorTangentV(_ column: Int, _ row: Int) -> Channels {
            let previous = channel(column, max(row - 1, 0)), next = channel(column, min(row + 1, height - 1))
            return (next - previous) * (1 / Double(min(row + 1, height - 1) - max(row - 1, 0)))
        }

        /// Hermite basis.
        @inline(__always) static func hermite(_ t: Double) -> (Double, Double, Double, Double) {
            let t2 = t * t, t3 = t2 * t
            return (2 * t3 - 3 * t2 + 1, -2 * t3 + 3 * t2, t3 - 2 * t2 + t, t3 - t2)
        }

        /// Rasterises one cell as a lattice of small quads with the surface and colours evaluated
        /// at the lattice points (a Ferguson patch: corner positions and tangents, zero twist).
        func rasterize(cell: (Int, Int), into raster: inout Raster) {
            let (column, row) = cell
            let corners = [(column, row), (column + 1, row), (column, row + 1), (column + 1, row + 1)]
            let p = corners.map { point($0.0, $0.1) }
            let tu = corners.map { tangentU($0.0, $0.1) }
            let tv = corners.map { tangentV($0.0, $0.1) }
            let c = corners.map { channel($0.0, $0.1) }
            let cu = corners.map { colorTangentU($0.0, $0.1) }
            let cv = corners.map { colorTangentV($0.0, $0.1) }
            // Subdivisions from the cell's extent in pixels, two pixels a step.
            let extent = max(abs(p[1].x - p[0].x), abs(p[3].x - p[2].x), abs(p[2].y - p[0].y), abs(p[3].y - p[1].y), abs(p[3].x - p[0].x), abs(p[3].y - p[0].y))
            let steps = max(4, min(64, Int((extent / 2).rounded(.up))))
            var positions = [CGPoint](repeating: .zero, count: (steps + 1) * (steps + 1))
            var colors = [Channels](repeating: Channels(a: 0, b: 0, c: 0, alpha: 0), count: positions.count)
            for j in 0...steps {
                let v = Double(j) / Double(steps)
                let (hv0, hv1, hv2, hv3) = Self.hermite(v)
                for i in 0...steps {
                    let u = Double(i) / Double(steps)
                    let (hu0, hu1, hu2, hu3) = Self.hermite(u)
                    // Position: a bicubic Hermite surface with zero twist vectors.
                    func surface(_ f: (Int) -> CGFloat, _ fu: (Int) -> CGFloat, _ fv: (Int) -> CGFloat) -> CGFloat {
                        let row0 = hu0 * f(0) + hu1 * f(1) + hu2 * fu(0) + hu3 * fu(1)
                        let row1 = hu0 * f(2) + hu1 * f(3) + hu2 * fu(2) + hu3 * fu(3)
                        let col0 = hu0 * fv(0) + hu1 * fv(1), col1 = hu0 * fv(2) + hu1 * fv(3)
                        return hv0 * row0 + hv1 * row1 + hv2 * col0 + hv3 * col1
                    }
                    let x = surface({ p[$0].x }, { tu[$0].x }, { tv[$0].x })
                    let y = surface({ p[$0].y }, { tu[$0].y }, { tv[$0].y })
                    positions[j * (steps + 1) + i] = CGPoint(x: x, y: y)
                    let color: Channels
                    if smooth {
                        let row0 = c[0] * hu0 + c[1] * hu1 + cu[0] * hu2 + cu[1] * hu3
                        let row1 = c[2] * hu0 + c[3] * hu1 + cu[2] * hu2 + cu[3] * hu3
                        let col0 = cv[0] * hu0 + cv[1] * hu1, col1 = cv[2] * hu0 + cv[3] * hu1
                        color = row0 * hv0 + row1 * hv1 + col0 * hv2 + col1 * hv3
                    } else {
                        color = (c[0] * (1 - u) + c[1] * u) * (1 - v) + (c[2] * (1 - u) + c[3] * u) * v
                    }
                    colors[j * (steps + 1) + i] = color
                }
            }
            for j in 0..<steps {
                for i in 0..<steps {
                    let a = j * (steps + 1) + i, b = a + 1, d = a + steps + 1, e = d + 1
                    raster.triangle(positions[a], positions[b], positions[d], colors[a], colors[b], colors[d], grid: self)
                    raster.triangle(positions[b], positions[e], positions[d], colors[b], colors[e], colors[d], grid: self)
                }
            }
        }
    }

    /// A straight-alpha RGBA raster with a Gouraud triangle fill.
    struct Raster {
        let width: Int, height: Int
        var pixels: [UInt8]

        init(width: Int, height: Int, background: RGBA) {
            self.width = width
            self.height = height
            pixels = [UInt8](repeating: 0, count: width * height * 4)
            if background.alpha > 0 {
                let bytes = Raster.bytes(background)
                for i in 0..<(width * height) { for k in 0..<4 { pixels[i * 4 + k] = bytes[k] } }
            }
        }

        static func bytes(_ color: RGBA) -> [UInt8] {
            [UInt8((min(max(color.red, 0), 1) * 255).rounded()), UInt8((min(max(color.green, 0), 1) * 255).rounded()),
             UInt8((min(max(color.blue, 0), 1) * 255).rounded()), UInt8((min(max(color.alpha, 0), 1) * 255).rounded())]
        }

        var bitmap: DisplayBitmap { DisplayBitmap(width: width, height: height, pixels: pixels) }

        /// Fills the triangle, pixel centres inside (edges inclusive), colours by barycentre.
        mutating func triangle(_ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint, _ c0: Channels, _ c1: Channels, _ c2: Channels, grid: Grid) {
            let minX = max(0, Int((min(p0.x, p1.x, p2.x)).rounded(.down))), maxX = min(width - 1, Int((max(p0.x, p1.x, p2.x)).rounded(.up)))
            let minY = max(0, Int((min(p0.y, p1.y, p2.y)).rounded(.down))), maxY = min(height - 1, Int((max(p0.y, p1.y, p2.y)).rounded(.up)))
            guard minX <= maxX, minY <= maxY else { return }
            let area = (p1.x - p0.x) * (p2.y - p0.y) - (p2.x - p0.x) * (p1.y - p0.y)
            guard abs(area) > 1e-12 else { return }
            let inverse = 1 / area
            for y in minY...maxY {
                let py = CGFloat(y) + 0.5
                for x in minX...maxX {
                    let px = CGFloat(x) + 0.5
                    var w0 = ((p1.x - px) * (p2.y - py) - (p2.x - px) * (p1.y - py)) * inverse
                    var w1 = ((p2.x - px) * (p0.y - py) - (p0.x - px) * (p2.y - py)) * inverse
                    var w2 = 1 - w0 - w1
                    // A hair of slack keeps shared edges seamless.
                    guard w0 >= -1e-3, w1 >= -1e-3, w2 >= -1e-3 else { continue }
                    w0 = max(0, w0); w1 = max(0, w1); w2 = max(0, min(1, w2))
                    let channels = c0 * Double(w0) + c1 * Double(w1) + c2 * Double(w2)
                    let bytes = Raster.bytes(grid.color(channels))
                    let index = (y * width + x) * 4
                    pixels[index] = bytes[0]; pixels[index + 1] = bytes[1]; pixels[index + 2] = bytes[2]; pixels[index + 3] = bytes[3]
                }
            }
        }
    }
}
