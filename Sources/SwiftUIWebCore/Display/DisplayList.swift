/// A resolved colour in sRGB with straight alpha, components 0…1.
public struct RGBA: Hashable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    /// 8-bit components, as in a PNG or a CSS `rgb()`.
    public init(r: Int, g: Int, b: Int, a: Double = 1) {
        self.init(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, alpha: a)
    }

    public static let clear = RGBA(red: 0, green: 0, blue: 0, alpha: 0)
    public static let black = RGBA(red: 0, green: 0, blue: 0)
    public static let white = RGBA(red: 1, green: 1, blue: 1)

    public func multiplyingAlpha(by factor: Double) -> RGBA {
        var copy = self
        copy.alpha *= factor
        return copy
    }
}

/// Font description a painter needs (no environment left to resolve).
public struct DisplayFont: Hashable, Sendable {
    public var family: String
    public var size: CGFloat
    public var weight: Int
    public var italic: Bool

    public init(_ font: ResolvedFont) {
        family = font.family
        size = font.size
        weight = font.weight.value
        italic = font.italic
    }
}

/// One image draw: a catalog file scaled (or tiled, or nine-part stretched) into `rect`.
public struct ImageDraw: Equatable, Sendable {
    /// Path of the variant, relative to the manifest base.
    public var file: String
    /// Pixels per point of the file, and its pixel size.
    public var scale: CGFloat
    public var pixelSize: CGSize
    public var rect: CGRect
    /// Rigid border of a nine-part draw, in points; zero draws the whole image at once.
    public var capInsets = EdgeInsets()
    /// Tile the stretched parts (edges and centre of a nine-part draw, or the whole image).
    public var tiles = false
    /// Resample smoothly (`false` is nearest neighbour).
    public var smoothing = true
    /// Fill the image's alpha with this colour (template rendering).
    public var tint: RGBA?

    public init(file: String, scale: CGFloat, pixelSize: CGSize, rect: CGRect) {
        self.file = file
        self.scale = scale
        self.pixelSize = pixelSize
        self.rect = rect
    }
}

/// One drawing command. Coordinates are absolute points in the window, already rounded to the
/// pixel grid where SwiftUI rounds (frame edges).
public enum DisplayCommand: Equatable, Sendable {
    case save
    case restore
    case clipRect(CGRect)
    case clipRRect(CGRect, cornerRadius: CGFloat)
    case clipPath(Path, eoFill: Bool = false)
    case beginGroup(opacity: Double)
    case endGroup
    /// Multiplies the current transform (inside save/restore) for Canvas drawing and effects.
    case concat(CGAffineTransform)
    case fillRect(CGRect, RGBA)
    case fillRRect(CGRect, cornerRadius: CGFloat, RGBA)
    case fillPath(Path, RGBA, eoFill: Bool = false)
    case strokePath(Path, style: StrokeStyle, RGBA)
    /// Fills and strokes with a gradient (absolute coordinates).
    case fillGradient(Path, DisplayGradient, eoFill: Bool = false)
    case strokeGradient(Path, style: StrokeStyle, DisplayGradient)
    /// Draws one line of text with its baseline at `origin.y`.
    case drawText(String, DisplayFont, origin: CGPoint, RGBA)
    /// Draws one line of text filled with a gradient (absolute coordinates).
    case drawTextGradient(String, DisplayFont, origin: CGPoint, DisplayGradient)
    case drawImage(ImageDraw)
}

/// The flat command list a painter consumes for one frame (decision 0002).
public struct DisplayList: Equatable, Sendable {
    public var commands: [DisplayCommand] = []

    public init() {}

    public mutating func append(_ command: DisplayCommand) {
        commands.append(command)
    }

    /// Runs `body` between `save` and `restore`.
    public mutating func withSavedState(_ body: (inout DisplayList) -> Void) {
        commands.append(.save)
        body(&self)
        commands.append(.restore)
    }

    public var isEmpty: Bool { commands.isEmpty }
}

extension DisplayCommand: CustomStringConvertible {
    public var description: String {
        func f(_ v: CGFloat) -> String { v == v.rounded() ? "\(Int(v))" : "\(v)" }
        func r(_ rect: CGRect) -> String { "(\(f(rect.minX)), \(f(rect.minY)), \(f(rect.width)), \(f(rect.height)))" }
        func c(_ color: RGBA) -> String {
            let hex = String(Int((color.red * 255).rounded()), radix: 16, uppercase: true).leftPadded(2)
                + String(Int((color.green * 255).rounded()), radix: 16, uppercase: true).leftPadded(2)
                + String(Int((color.blue * 255).rounded()), radix: 16, uppercase: true).leftPadded(2)
            return color.alpha == 1 ? "#\(hex)" : "#\(hex)@\(color.alpha)"
        }
        switch self {
        case .save: return "save"
        case .restore: return "restore"
        case .clipRect(let rect): return "clipRect\(r(rect))"
        case .clipRRect(let rect, let radius): return "clipRRect\(r(rect)) r=\(f(radius))"
        case .clipPath(let path, let eo): return "clipPath(\(path.elements.count) elements)\(eo ? " eo" : "")"
        case .beginGroup(let opacity): return "beginGroup(opacity: \(opacity))"
        case .endGroup: return "endGroup"
        case .concat(let t): return "concat(\(f(t.a)), \(f(t.b)), \(f(t.c)), \(f(t.d)), \(f(t.tx)), \(f(t.ty)))"
        case .fillRect(let rect, let color): return "fillRect\(r(rect)) \(c(color))"
        case .fillRRect(let rect, let radius, let color): return "fillRRect\(r(rect)) r=\(f(radius)) \(c(color))"
        case .fillPath(let path, let color, let eo): return "fillPath(\(path.elements.count) elements)\(eo ? " eo" : "") \(c(color))"
        case .fillGradient(let path, let gradient, let eo): return "fillGradient(\(path.elements.count) elements)\(eo ? " eo" : "") \(gradient.summary)"
        case .strokeGradient(let path, let style, let gradient): return "strokeGradient(\(path.elements.count) elements) w=\(f(style.lineWidth)) \(gradient.summary)"
        case .strokePath(let path, let style, let color):
            var text = "strokePath(\(path.elements.count) elements) w=\(f(style.lineWidth))"
            if style.lineCap != .butt { text += " cap=\(style.lineCap == .round ? "round" : "square")" }
            if style.lineJoin != .miter { text += " join=\(style.lineJoin == .round ? "round" : "bevel")" }
            if style.miterLimit != 10 { text += " miter=\(f(style.miterLimit))" }
            if !style.dash.isEmpty { text += " dash=[\(style.dash.map(f).joined(separator: ","))]" + (style.dashPhase != 0 ? " phase=\(f(style.dashPhase))" : "") }
            return text + " \(c(color))"
        case .drawText(let text, let font, let origin, let color):
            return "drawText(\"\(text)\" \(font.family) \(f(font.size)) w\(font.weight) at \(f(origin.x)),\(f(origin.y)) \(c(color)))"
        case .drawTextGradient(let text, let font, let origin, let gradient):
            return "drawText(\"\(text)\" \(font.family) \(f(font.size)) w\(font.weight) at \(f(origin.x)),\(f(origin.y)) \(gradient.summary))"
        case .drawImage(let draw):
            var text = "drawImage(\(draw.file) @\(f(draw.scale))x \(r(draw.rect))"
            if draw.capInsets != EdgeInsets() { text += " insets=\(f(draw.capInsets.top)),\(f(draw.capInsets.leading)),\(f(draw.capInsets.bottom)),\(f(draw.capInsets.trailing))" }
            if draw.tiles { text += " tile" }
            if !draw.smoothing { text += " nearest" }
            if let tint = draw.tint { text += " tint=\(c(tint))" }
            return text + ")"
        }
    }
}

extension String {
    fileprivate func leftPadded(_ width: Int) -> String {
        count >= width ? self : String(repeating: "0", count: width - count) + self
    }
}

extension DisplayGradient {
    /// A short description for logs and tests.
    package var summary: String {
        func p(_ point: CGPoint) -> String { "\(point.x),\(point.y)" }
        let kindText: String
        switch kind {
        case .linear(let start, let end): kindText = "linear \(p(start))→\(p(end))"
        case .radial(let center, let r0, let r1): kindText = "radial \(p(center)) r\(r0)→\(r1)"
        case .angular(let center, let angle): kindText = "angular \(p(center)) a\(angle)"
        }
        let stopsText = stops.map { "\($0.location):\(String(format: "%02X%02X%02X", Int(($0.color.red * 255).rounded()), Int(($0.color.green * 255).rounded()), Int(($0.color.blue * 255).rounded())))" }.joined(separator: " ")
        return "\(kindText) [\(stopsText)]"
    }
}
