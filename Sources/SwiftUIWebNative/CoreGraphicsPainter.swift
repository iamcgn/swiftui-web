#if canImport(AppKit)
import AppKit
import CoreText
import SwiftUIWebCore

/// Paints a `DisplayList` into a CoreGraphics context whose coordinate system is the display
/// list's: points, origin at the top left, y down (a flipped `NSView`, or a bitmap context the
/// caller flipped). Text is drawn with CoreText, images from the asset base directory.
@MainActor
public final class CoreGraphicsPainter {
    public let textEngine: CoreTextEngine
    /// The directory the asset manifest's files are relative to.
    public var assetBase: URL?
    private var images: [String: CGImage] = [:]
    private static let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

    public init(textEngine: CoreTextEngine, assetBase: URL? = nil) {
        self.textEngine = textEngine
        self.assetBase = assetBase
    }

    public func paint(_ list: DisplayList, into ctx: CGContext) {
        ctx.saveGState()
        ctx.setAllowsAntialiasing(true)
        ctx.setShouldAntialias(true)
        for command in list.commands {
            switch command {
            case .save: ctx.saveGState()
            case .restore: ctx.restoreGState()
            case .clipRect(let rect): ctx.clip(to: rect)
            case .clipRRect(let rect, let radius):
                ctx.addPath(Self.roundedPath(rect, radius: radius))
                ctx.clip()
            case .clipPath(let path, let eo):
                ctx.addPath(Self.cgPath(path))
                ctx.clip(using: eo ? .evenOdd : .winding)
            case .beginGroup(let opacity):
                ctx.saveGState()
                ctx.setAlpha(CGFloat(opacity))
                ctx.beginTransparencyLayer(auxiliaryInfo: nil)
            case .endGroup:
                ctx.endTransparencyLayer()
                ctx.restoreGState()
            case .concat(let transform): ctx.concatenate(transform)
            case .fillRect(let rect, let color):
                ctx.setFillColor(Self.cgColor(color))
                ctx.fill(rect)
            case .fillRRect(let rect, let radius, let color):
                ctx.setFillColor(Self.cgColor(color))
                ctx.addPath(Self.roundedPath(rect, radius: radius))
                ctx.fillPath()
            case .fillPath(let path, let color, let eo):
                ctx.setFillColor(Self.cgColor(color))
                ctx.addPath(Self.cgPath(path))
                ctx.fillPath(using: eo ? .evenOdd : .winding)
            case .strokePath(let path, let style, let color):
                ctx.setStrokeColor(Self.cgColor(color))
                Self.apply(style, to: ctx)
                ctx.addPath(Self.cgPath(path))
                ctx.strokePath()
            case .fillGradient(let path, let gradient, let eo):
                ctx.saveGState()
                ctx.addPath(Self.cgPath(path))
                ctx.clip(using: eo ? .evenOdd : .winding)
                Self.draw(gradient, in: ctx)
                ctx.restoreGState()
            case .strokeGradient(let path, let style, let gradient):
                ctx.saveGState()
                Self.apply(style, to: ctx)
                ctx.addPath(Self.cgPath(path))
                ctx.replacePathWithStrokedPath()
                ctx.clip()
                Self.draw(gradient, in: ctx)
                ctx.restoreGState()
            case .drawText(let text, let font, let origin, let color):
                drawText(text, font: font, at: origin, color: color, gradient: nil, in: ctx)
            case .drawTextGradient(let text, let font, let origin, let gradient):
                drawText(text, font: font, at: origin, color: .black, gradient: gradient, in: ctx)
            case .drawImage(let draw):
                drawImage(draw, in: ctx)
            }
        }
        ctx.restoreGState()
    }

    // MARK: Geometry and colour

    static func cgColor(_ color: RGBA) -> CGColor {
        CGColor(colorSpace: colorSpace, components: [CGFloat(color.red), CGFloat(color.green), CGFloat(color.blue), CGFloat(color.alpha)])!
    }

    static func cgPath(_ path: Path) -> CGPath {
        let result = CGMutablePath()
        for element in path.elements {
            switch element {
            case .move(let to): result.move(to: to)
            case .line(let to): result.addLine(to: to)
            case .quadCurve(let to, let control): result.addQuadCurve(to: to, control: control)
            case .curve(let to, let c1, let c2): result.addCurve(to: to, control1: c1, control2: c2)
            case .closeSubpath: result.closeSubpath()
            }
        }
        return result
    }

    static func roundedPath(_ rect: CGRect, radius: CGFloat) -> CGPath {
        let r = min(radius, rect.width / 2, rect.height / 2)
        return r > 0 ? CGPath(roundedRect: rect, cornerWidth: r, cornerHeight: r, transform: nil) : CGPath(rect: rect, transform: nil)
    }

    static func apply(_ style: StrokeStyle, to ctx: CGContext) {
        ctx.setLineWidth(style.lineWidth)
        ctx.setLineCap(style.lineCap)
        ctx.setLineJoin(style.lineJoin)
        ctx.setMiterLimit(style.miterLimit)
        ctx.setLineDash(phase: style.dashPhase, lengths: style.dash)
    }

    /// Draws a gradient over the current clip. Linear and radial map to CoreGraphics; an angular
    /// gradient is painted as 256 wedges of the interpolated stop colours.
    static func draw(_ gradient: DisplayGradient, in ctx: CGContext) {
        let stops = gradient.stops
        guard !stops.isEmpty else { return }
        let colors = stops.map { cgColor($0.color) } as CFArray
        let locations = stops.map { CGFloat($0.location) }
        guard let cgGradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: locations) else { return }
        let options: CGGradientDrawingOptions = [.drawsBeforeStartLocation, .drawsAfterEndLocation]
        switch gradient.kind {
        case .linear(let start, let end):
            ctx.drawLinearGradient(cgGradient, start: start, end: end, options: options)
        case .radial(let center, let r0, let r1):
            ctx.drawRadialGradient(cgGradient, startCenter: center, startRadius: r0, endCenter: center, endRadius: r1, options: options)
        case .angular(let center, let startAngle):
            let box = ctx.boundingBoxOfClipPath
            let corners = [box.origin, CGPoint(x: box.maxX, y: box.minY), CGPoint(x: box.minX, y: box.maxY), CGPoint(x: box.maxX, y: box.maxY)]
            let radius = corners.map { hypot($0.x - center.x, $0.y - center.y) }.max() ?? 0
            guard radius > 0 else { return }
            let wedges = 256
            func color(at t: Double) -> RGBA {
                guard let after = stops.firstIndex(where: { $0.location >= t }) else { return stops.last!.color }
                guard after > 0 else { return stops[0].color }
                let a = stops[after - 1], b = stops[after]
                let span = b.location - a.location
                let f = span > 0 ? (t - a.location) / span : 0
                return RGBA(red: a.color.red + (b.color.red - a.color.red) * f, green: a.color.green + (b.color.green - a.color.green) * f,
                            blue: a.color.blue + (b.color.blue - a.color.blue) * f, alpha: a.color.alpha + (b.color.alpha - a.color.alpha) * f)
            }
            for index in 0..<wedges {
                let a0 = startAngle + Double(index) / Double(wedges) * 2 * .pi
                let a1 = startAngle + Double(index + 1) / Double(wedges) * 2 * .pi + 0.004
                ctx.setFillColor(cgColor(color(at: (Double(index) + 0.5) / Double(wedges))))
                ctx.move(to: center)
                ctx.addLine(to: CGPoint(x: center.x + radius * CGFloat(cos(a0)), y: center.y + radius * CGFloat(sin(a0))))
                ctx.addLine(to: CGPoint(x: center.x + radius * CGFloat(cos(a1)), y: center.y + radius * CGFloat(sin(a1))))
                ctx.closePath()
                ctx.fillPath()
            }
        }
    }

    // MARK: Text

    private func drawText(_ text: String, font: DisplayFont, at origin: CGPoint, color: RGBA, gradient: DisplayGradient?, in ctx: CGContext) {
        let attributed = NSAttributedString(string: text, attributes: [
            .font: textEngine.nsFont(font),
            kCTForegroundColorAttributeName as NSAttributedString.Key: Self.cgColor(color),
        ])
        let line = CTLineCreateWithAttributedString(attributed)
        ctx.saveGState()
        // CoreText draws y-up: flip the glyphs about the baseline.
        ctx.textMatrix = .identity
        ctx.translateBy(x: origin.x, y: origin.y)
        ctx.scaleBy(x: 1, y: -1)
        if let gradient {
            ctx.setTextDrawingMode(.clip)
            CTLineDraw(line, ctx)
            ctx.scaleBy(x: 1, y: -1)
            ctx.translateBy(x: -origin.x, y: -origin.y)
            Self.draw(gradient, in: ctx)
        } else {
            ctx.setTextDrawingMode(.fill)
            CTLineDraw(line, ctx)
        }
        ctx.restoreGState()
    }

    // MARK: Images

    private func image(for file: String) -> CGImage? {
        if let cached = images[file] { return cached }
        guard let base = assetBase else { return nil }
        let url = base.appendingPathComponent(file)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        images[file] = image
        return image
    }

    /// Draws `image` (or its `part`) into `destination` in the y-down space; when tiling, the
    /// part repeats at `tile` size from the destination's top-left corner (the last column and
    /// row cut at its edge).
    private func draw(_ image: CGImage, part: CGRect? = nil, in destination: CGRect, tile: CGSize? = nil, ctx: CGContext) {
        guard destination.width > 0, destination.height > 0 else { return }
        let piece = part.flatMap { image.cropping(to: $0) } ?? image
        ctx.saveGState()
        ctx.clip(to: destination)
        // Flip about the destination so the image draws upright in this y-down space.
        ctx.translateBy(x: 0, y: destination.maxY)
        ctx.scaleBy(x: 1, y: -1)
        if let tile, tile.width > 0, tile.height > 0 {
            // In the flipped space the destination spans y 0…height; a tile whose top edge is at
            // the top of the destination anchors the pattern there.
            ctx.draw(piece, in: CGRect(x: destination.minX, y: destination.height - tile.height, width: tile.width, height: tile.height), byTiling: true)
        } else {
            ctx.draw(piece, in: CGRect(x: destination.minX, y: 0, width: destination.width, height: destination.height))
        }
        ctx.restoreGState()
    }

    private func drawImage(_ draw: ImageDraw, in ctx: CGContext) {
        guard let image = image(for: draw.file) else { return }
        ctx.saveGState()
        ctx.interpolationQuality = draw.smoothing ? .default : .none
        if draw.tint != nil {
            // Template images: the image masks a fill of the tint.
            ctx.clip(to: draw.rect)
            ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        }
        let insets = draw.capInsets
        let rect = draw.rect
        let scale = draw.scale
        let pointSize = CGSize(width: draw.pixelSize.width / scale, height: draw.pixelSize.height / scale)
        if insets == EdgeInsets() {
            self.draw(image, in: rect, tile: draw.tiles ? pointSize : nil, ctx: ctx)
        } else {
            // Nine parts: corners rigid, edges stretched or tiled one way, the centre both ways.
            let sx = [0, insets.leading * scale, draw.pixelSize.width - insets.trailing * scale, draw.pixelSize.width]
            let sy = [0, insets.top * scale, draw.pixelSize.height - insets.bottom * scale, draw.pixelSize.height]
            let dx = [rect.minX, rect.minX + insets.leading, rect.maxX - insets.trailing, rect.maxX]
            let dy = [rect.minY, rect.minY + insets.top, rect.maxY - insets.bottom, rect.maxY]
            for i in 0..<3 {
                for j in 0..<3 {
                    let source = CGRect(x: sx[i], y: sy[j], width: sx[i + 1] - sx[i], height: sy[j + 1] - sy[j])
                    let destination = CGRect(x: dx[i], y: dy[j], width: dx[i + 1] - dx[i], height: dy[j + 1] - dy[j])
                    guard source.width > 0, source.height > 0, destination.width > 0, destination.height > 0 else { continue }
                    let rigid = i != 1 && j != 1
                    let tile = draw.tiles && !rigid ? CGSize(width: source.width / scale, height: source.height / scale) : nil
                    self.draw(image, part: source, in: destination, tile: tile, ctx: ctx)
                }
            }
        }
        if let tint = draw.tint {
            ctx.setBlendMode(.sourceIn)
            ctx.setFillColor(Self.cgColor(tint))
            ctx.fill(draw.rect)
            ctx.endTransparencyLayer()
        }
        ctx.restoreGState()
    }
}
#endif
