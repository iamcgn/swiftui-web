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
    /// Starts a group (ended by `endGroup`) whose composite casts a shadow: `radius` is
    /// SwiftUI's blur radius (the Gaussian sigma in points), `offset` in points.
    case beginShadow(RGBA, radius: CGFloat, offset: CGSize)
    /// Starts a group (ended by `endGroup`) whose composite is filtered before it is drawn:
    /// `bounds` is the absolute frame of the filtered content, the area the painters process.
    case beginFilter(DisplayFilter, bounds: CGRect)
    /// Starts a group (ended by `endGroup`) composited with a blend mode; `bounds` as above.
    case beginBlend(BlendMode, bounds: CGRect)
    /// Starts a mask: the commands up to `beginMasked` draw the mask, those up to `endGroup`
    /// the content, which shows through the mask's alpha within `bounds`.
    case beginMask(bounds: CGRect)
    case beginMasked
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

/// Formats a number for display-list descriptions: integers without a fraction.
package func _displayFormat(_ v: CGFloat) -> String { v == v.rounded() ? "\(Int(v))" : "\(v)" }

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
        case .beginShadow(let color, let radius, let offset): return "beginShadow(\(c(color)) r=\(f(radius)) dx=\(f(offset.width)) dy=\(f(offset.height)))"
        case .beginFilter(let filter, let bounds): return "beginFilter(\(filter)\(r(bounds)))"
        case .beginBlend(let mode, let bounds): return "beginBlend(\(mode)\(r(bounds)))"
        case .beginMask(let bounds): return "beginMask\(r(bounds))"
        case .beginMasked: return "beginMasked"
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
        func hex(_ value: Double) -> String {
            let byte = Int((value * 255).rounded())
            let digits = String(byte, radix: 16, uppercase: true)
            return byte < 16 ? "0" + digits : digits
        }
        let stopsText = stops.map { "\($0.location):\(hex($0.color.red))\(hex($0.color.green))\(hex($0.color.blue))" }.joined(separator: " ")
        return "\(kindText) [\(stopsText)]"
    }
}

/// A filter a painter applies to a group's composite before drawing it.
public enum DisplayFilter: Equatable, Sendable {
    /// A 4 × 5 colour matrix over straight-alpha sRGB components in 0…1, row-major: each of
    /// the red, green, blue and alpha rows holds the red, green, blue and alpha factors and an
    /// offset (the SVG `feColorMatrix` convention). Results are clamped to 0…1.
    case colorMatrix(ColorMatrix)
    /// A Gaussian blur whose sigma is `radius` points. `opaque` keeps the content's own alpha
    /// (hard edges) and blurs only the colours inside it.
    case blur(radius: CGFloat, opaque: Bool)
}

extension DisplayFilter: CustomStringConvertible {
    public var description: String {
        switch self {
        case .colorMatrix(let matrix): return matrix.description
        case .blur(let radius, let opaque): return "blur(\(_displayFormat(radius))\(opaque ? " opaque" : ""))"
        }
    }
}

/// A colour matrix (see `DisplayFilter.colorMatrix`): 20 values, rows red, green, blue, alpha.
public struct ColorMatrix: Equatable, Sendable {
    public var values: [Double]

    public init(_ values: [Double]) {
        precondition(values.count == 20, "a colour matrix has 4 rows of 5")
        self.values = values
    }

    public static let identity = ColorMatrix([1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0])

    /// The luminance weights SwiftUI's filters share (Rec. 709 primaries).
    public static let luminance = (red: 0.2126, green: 0.7152, blue: 0.0722)

    /// Adds `amount` to every colour component (`brightness`).
    public static func brightness(_ amount: Double) -> ColorMatrix {
        ColorMatrix([1, 0, 0, 0, amount, 0, 1, 0, 0, amount, 0, 0, 1, 0, amount, 0, 0, 0, 1, 0])
    }

    /// Scales the colour components about mid grey (`contrast`).
    public static func contrast(_ amount: Double) -> ColorMatrix {
        let offset = 0.5 - 0.5 * amount
        return ColorMatrix([amount, 0, 0, 0, offset, 0, amount, 0, 0, offset, 0, 0, amount, 0, offset, 0, 0, 0, 1, 0])
    }

    /// Interpolates between luminance grey (0) and the colour itself (1), or beyond (`saturation`;
    /// `grayscale(x)` is `saturation(1 - x)`).
    public static func saturation(_ amount: Double) -> ColorMatrix {
        let (r, g, b) = luminance
        let s = amount
        return ColorMatrix([
            r + (1 - r) * s, g - g * s, b - b * s, 0, 0,
            r - r * s, g + (1 - g) * s, b - b * s, 0, 0,
            r - r * s, g - g * s, b + (1 - b) * s, 0, 0,
            0, 0, 0, 1, 0,
        ])
    }

    /// Rotates hues by `angle` (`hueRotation`), the SVG `hueRotate` matrix.
    public static func hueRotation(_ angle: Angle) -> ColorMatrix {
        let (r, g, b) = luminance
        let c = _cos(angle.radians), s = _sin(angle.radians)
        return ColorMatrix([
            r + c * (1 - r) - s * r, g - c * g - s * g, b - c * b + s * (1 - b), 0, 0,
            r - c * r + s * 0.143, g + c * (1 - g) + s * 0.140, b - c * b - s * 0.283, 0, 0,
            r - c * r - s * (1 - r), g - c * g + s * g, b + c * (1 - b) + s * b, 0, 0,
            0, 0, 0, 1, 0,
        ])
    }

    /// Complements every colour component (`colorInvert`).
    public static let invert = ColorMatrix([-1, 0, 0, 0, 1, 0, -1, 0, 0, 1, 0, 0, -1, 0, 1, 0, 0, 0, 1, 0])

    /// Multiplies the components by a colour's, alpha included (`colorMultiply`).
    public static func multiply(_ color: RGBA) -> ColorMatrix {
        ColorMatrix([color.red, 0, 0, 0, 0, 0, color.green, 0, 0, 0, 0, 0, color.blue, 0, 0, 0, 0, 0, color.alpha, 0])
    }

    /// Black whose alpha is the colour's luminance (`luminanceToAlpha`): the content's own
    /// alpha is replaced, as SwiftUI does.
    public static let luminanceToAlpha = ColorMatrix([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, luminance.red, luminance.green, luminance.blue, 0, 0])

    /// Applies the matrix to one straight-alpha colour, clamping to 0…1.
    public func apply(_ color: RGBA) -> RGBA {
        let input = [color.red, color.green, color.blue, color.alpha]
        var out = [0.0, 0.0, 0.0, 0.0]
        for row in 0..<4 {
            var value = values[row * 5 + 4]
            for column in 0..<4 { value += values[row * 5 + column] * input[column] }
            out[row] = min(1, max(0, value))
        }
        return RGBA(red: out[0], green: out[1], blue: out[2], alpha: out[3])
    }

    /// Applies the matrix in place to premultiplied 8-bit RGBA pixels: each pixel is
    /// un-premultiplied, transformed, clamped, rounded and premultiplied again.
    public func apply(toPremultiplied pixels: UnsafeMutableBufferPointer<UInt8>) {
        let m = values
        var i = 0
        while i + 3 < pixels.count {
            let a8 = pixels[i + 3]
            var r = 0.0, g = 0.0, b = 0.0, a = Double(a8) / 255
            if a8 != 0 {
                r = Double(pixels[i]) / 255 / a
                g = Double(pixels[i + 1]) / 255 / a
                b = Double(pixels[i + 2]) / 255 / a
            }
            let nr = min(1, max(0, m[0] * r + m[1] * g + m[2] * b + m[3] * a + m[4]))
            let ng = min(1, max(0, m[5] * r + m[6] * g + m[7] * b + m[8] * a + m[9]))
            let nb = min(1, max(0, m[10] * r + m[11] * g + m[12] * b + m[13] * a + m[14]))
            let na = min(1, max(0, m[15] * r + m[16] * g + m[17] * b + m[18] * a + m[19]))
            pixels[i] = UInt8((nr * na * 255).rounded())
            pixels[i + 1] = UInt8((ng * na * 255).rounded())
            pixels[i + 2] = UInt8((nb * na * 255).rounded())
            pixels[i + 3] = UInt8((na * 255).rounded())
            i += 4
        }
    }
}

extension ColorMatrix: CustomStringConvertible {
    public var description: String { "colorMatrix(" + values.map { _displayFormat($0) }.joined(separator: " ") + ")" }
}
