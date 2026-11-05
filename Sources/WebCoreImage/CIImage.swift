// Core Image on the web, Docs/elements/CoreImage.md. An image is a recipe, as Apple's is: a
// source (a CGImage, a solid colour) and the filters, composites, transforms and crops over it,
// in Core Image's space (pixels, origin at the bottom left). Nothing is computed until a
// context makes a CGImage of it, and then nothing is computed either: the context writes the
// recipe as display-list commands (colour matrices, blurs, blends, clips), so the CGImage is a
// recording that the painters draw, filters and all, wherever the app shows it.
// Where CGImage is CoreGraphics's (Apple platforms) the module is empty.

#if !canImport(CoreGraphics) || os(WASI)
// Apple's frameworks re-export Foundation. WebGraphics stays out of a client's scope; the
// CoreImage shadow re-exports CoreGraphics's names from it.
@_exported import WebFoundation
import WebGraphics
#if os(WASI)
import WebImageIO
#endif

/// An image to be filtered: a recipe that a `CIContext` renders.
public final class CIImage: Sendable, CustomStringConvertible {
    indirect enum Recipe: Sendable {
        case empty
        case bitmap(CGImage)
        case color(RGBA)
        case matrix(ColorMatrix, Recipe)
        case blur(CGFloat, Recipe)
        case over(Recipe, Recipe)
        case blend(BlendMode, Recipe, Recipe)
        case transform(CGAffineTransform, Recipe)
        case crop(CGRect, Recipe)
    }

    let recipe: Recipe
    /// The part of the plane the image covers: a CGImage's pixels, everything for a colour.
    public let extent: CGRect
    /// The image's metadata; none here.
    public var properties: [String: Any] { [:] }

    init(_ recipe: Recipe) {
        self.recipe = recipe
        extent = recipe.extent
    }

    public convenience init(cgImage: CGImage) { self.init(.bitmap(cgImage)) }
    public convenience init(cgImage: CGImage, options: [CIImageOption: Any]?) { self.init(.bitmap(cgImage)) }

    /// An image of a PNG, JPEG, GIF or WebP file's bytes; nil for anything else.
    public convenience init?(data: Data, options: [CIImageOption: Any]? = nil) {
        guard let info = _ImageFileInfo(data) else { return nil }
        self.init(.bitmap(CGImage(_content: .file(data, info, frame: 0))))
    }

    public convenience init?(contentsOf url: URL, options: [CIImageOption: Any]? = nil) {
        guard let data = try? Data(contentsOf: url) else { return nil }
        self.init(data: data, options: options)
    }

    /// An endless plane of one colour.
    public convenience init(color: CIColor) { self.init(.color(color.rgba)) }

    public static func empty() -> CIImage { CIImage(.empty) }
    public static let black = CIImage(color: .black)
    public static let white = CIImage(color: .white)
    public static let clear = CIImage(color: .clear)
    public static let gray = CIImage(color: .gray)
    public static let red = CIImage(color: .red)
    public static let green = CIImage(color: .green)
    public static let blue = CIImage(color: .blue)

    /// The CGImage the image was made from, when it is one unchanged.
    public var cgImage: CGImage? {
        if case .bitmap(let image) = recipe { return image }
        return nil
    }

    public func transformed(by matrix: CGAffineTransform) -> CIImage {
        matrix.isIdentity ? self : CIImage(.transform(matrix, recipe))
    }

    public func transformed(by matrix: CGAffineTransform, highQualityDownsample: Bool) -> CIImage { transformed(by: matrix) }

    public func cropped(to rect: CGRect) -> CIImage { CIImage(.crop(rect.standardized, recipe)) }

    /// The image drawn over `dest`.
    public func composited(over dest: CIImage) -> CIImage { CIImage(.over(recipe, dest.recipe)) }

    public func applyingGaussianBlur(sigma: Double) -> CIImage {
        sigma > 0 ? CIImage(.blur(CGFloat(sigma), recipe)) : self
    }

    /// The image turned or mirrored as an EXIF orientation says, kept at the origin.
    public func oriented(forExifOrientation orientation: Int32) -> CIImage {
        oriented(CGImagePropertyOrientation(rawValue: UInt32(orientation)) ?? .up)
    }

    public func oriented(_ orientation: CGImagePropertyOrientation) -> CIImage {
        let w = extent.width, h = extent.height
        let t: CGAffineTransform
        switch orientation {
        case .up: return self
        case .upMirrored: t = CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: w, ty: 0)
        case .down: t = CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: w, ty: h)
        case .downMirrored: t = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: h)
        case .leftMirrored: t = CGAffineTransform(a: 0, b: 1, c: 1, d: 0, tx: 0, ty: 0)
        case .right: t = CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: w)
        case .rightMirrored: t = CGAffineTransform(a: 0, b: -1, c: -1, d: 0, tx: h, ty: w)
        case .left: t = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: h, ty: 0)
        }
        let moved = CGAffineTransform(translationX: -extent.minX, y: -extent.minY).concatenating(t)
        return transformed(by: moved)
    }

    /// The image with a filter applied, `self` as its input image; the empty image for a
    /// filter this module does not know.
    public func applyingFilter(_ filterName: String, parameters params: [String: Any]) -> CIImage {
        guard let filter = CIFilter(name: filterName) else { return .empty() }
        filter.setValue(self, forKey: kCIInputImageKey)
        for (key, value) in params { filter.setValue(value, forKey: key) }
        return filter.outputImage ?? .empty()
    }

    public func applyingFilter(_ filterName: String) -> CIImage { applyingFilter(filterName, parameters: [:]) }

    public var description: String { "<CIImage extent \(extent)>" }
}

#if !os(WASI)
/// The EXIF orientations, as ImageIO numbers them (WebImageIO's on wasm).
public enum CGImagePropertyOrientation: UInt32, Sendable {
    case up = 1, upMirrored, down, downMirrored, leftMirrored, right, rightMirrored, left
}
#endif

extension CIImage.Recipe {
    var extent: CGRect {
        switch self {
        case .empty: return .null
        case .bitmap(let image): return CGRect(x: 0, y: 0, width: image.width, height: image.height)
        case .color: return .infinite
        case .matrix(_, let input): return input.extent
        case .blur(let sigma, let input):
            let e = input.extent
            return e.isInfinite || e.isNull ? e : e.insetBy(dx: -sigma * 3, dy: -sigma * 3)
        case .over(let top, let bottom), .blend(_, let top, let bottom): return top.extent.union(bottom.extent)
        case .transform(let t, let input):
            let e = input.extent
            return e.isInfinite || e.isNull ? e : e.applying(t)
        case .crop(let rect, let input): return rect.intersection(input.extent)
        }
    }

    /// The commands that draw the recipe where the current space is Core Image's, inside
    /// `area` (the part being rendered, in that space).
    func commands(in area: CGRect) -> [DisplayCommand] {
        let area = area.intersection(extent)
        guard !area.isNull, area.width > 0, area.height > 0 else { return [] }
        switch self {
        case .empty: return []
        case .bitmap(let image):
            // A CGImage's first row is its top: drawn upright in a y-up space by flipping it.
            let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
            let flip = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: rect.height)
            return [.save, .concat(flip)] + image._commands(in: rect) + [.restore]
        case .color(let color): return [.fillRect(area, color)]
        case .matrix(let m, let input): return [.beginFilter(.colorMatrix(m), bounds: area)] + input.commands(in: area) + [.endGroup]
        case .blur(let sigma, let input):
            return [.beginFilter(.blur(radius: sigma, opaque: false), bounds: area)]
                + input.commands(in: area.insetBy(dx: -sigma * 3, dy: -sigma * 3)) + [.endGroup]
        case .over(let top, let bottom): return bottom.commands(in: area) + top.commands(in: area)
        case .blend(let mode, let top, let bottom):
            return bottom.commands(in: area) + [.beginBlend(mode, bounds: area)] + top.commands(in: area) + [.endGroup]
        case .transform(let t, let input):
            return [.save, .concat(t)] + input.commands(in: area.applying(t.inverted())) + [.restore]
        case .crop(let rect, let input): return [.save, .clipRect(area)] + input.commands(in: area.intersection(rect)) + [.restore]
        }
    }
}

/// Options for making an image (accepted; orientation is applied with `oriented`).
public struct CIImageOption: RawRepresentable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let colorSpace = CIImageOption(rawValue: "kCIImageColorSpace")
    public static let properties = CIImageOption(rawValue: "kCIImageProperties")
    public static let applyOrientationProperty = CIImageOption(rawValue: "kCIImageApplyOrientationProperty")
    public static let nearestSampling = CIImageOption(rawValue: "kCIImageNearestSampling")
}

/// A colour with straight-alpha sRGB components.
public final class CIColor: Sendable, CustomStringConvertible {
    let rgba: RGBA

    public init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat = 1) {
        rgba = RGBA(red: Double(red), green: Double(green), blue: Double(blue), alpha: Double(alpha))
    }

    public convenience init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat, colorSpace: CGColorSpace) {
        self.init(red: red, green: green, blue: blue, alpha: alpha)
    }

    public convenience init(cgColor: CGColor) {
        let c = RGBA(cgColor: cgColor) ?? .black
        self.init(red: c.red, green: c.green, blue: c.blue, alpha: c.alpha)
    }

    /// A colour from its string form, "r g b a" (alpha optional).
    public convenience init(string representation: String) {
        let parts = representation.split(whereSeparator: { $0 == " " || $0 == "[" || $0 == "]" }).compactMap { Double($0) }
        let v = parts + [0, 0, 0, 1].dropFirst(min(parts.count, 4))
        self.init(red: v[0], green: v[1], blue: v[2], alpha: v[3])
    }

    public var red: CGFloat { rgba.red }
    public var green: CGFloat { rgba.green }
    public var blue: CGFloat { rgba.blue }
    public var alpha: CGFloat { rgba.alpha }
    public var numberOfComponents: Int { 4 }
    public var stringRepresentation: String { "\(red) \(green) \(blue) \(alpha)" }
    public var description: String { stringRepresentation }

    public static let black = CIColor(red: 0, green: 0, blue: 0)
    public static let white = CIColor(red: 1, green: 1, blue: 1)
    public static let gray = CIColor(red: 0.5, green: 0.5, blue: 0.5)
    public static let red = CIColor(red: 1, green: 0, blue: 0)
    public static let green = CIColor(red: 0, green: 1, blue: 0)
    public static let blue = CIColor(red: 0, green: 0, blue: 1)
    public static let cyan = CIColor(red: 0, green: 1, blue: 1)
    public static let magenta = CIColor(red: 1, green: 0, blue: 1)
    public static let yellow = CIColor(red: 1, green: 1, blue: 0)
    public static let clear = CIColor(red: 0, green: 0, blue: 0, alpha: 0)
}

/// Up to four numbers: a point, a rectangle (x, y, width, height) or a colour matrix row.
public final class CIVector: Sendable, CustomStringConvertible {
    let values: [CGFloat]

    public init(values: [CGFloat]) { self.values = values }
    public convenience init(x: CGFloat) { self.init(values: [x]) }
    public convenience init(x: CGFloat, y: CGFloat) { self.init(values: [x, y]) }
    public convenience init(x: CGFloat, y: CGFloat, z: CGFloat) { self.init(values: [x, y, z]) }
    public convenience init(x: CGFloat, y: CGFloat, z: CGFloat, w: CGFloat) { self.init(values: [x, y, z, w]) }
    public convenience init(cgPoint p: CGPoint) { self.init(values: [p.x, p.y]) }
    public convenience init(cgRect r: CGRect) { self.init(values: [r.minX, r.minY, r.width, r.height]) }
    public convenience init(cgAffineTransform t: CGAffineTransform) { self.init(values: [t.a, t.b, t.c, t.d, t.tx, t.ty]) }

    public var count: Int { values.count }
    public func value(at index: Int) -> CGFloat { index < values.count ? values[index] : 0 }
    public var x: CGFloat { value(at: 0) }
    public var y: CGFloat { value(at: 1) }
    public var z: CGFloat { value(at: 2) }
    public var w: CGFloat { value(at: 3) }
    public var cgPointValue: CGPoint { CGPoint(x: x, y: y) }
    public var cgRectValue: CGRect { CGRect(x: x, y: y, width: z, height: w) }
    public var cgAffineTransformValue: CGAffineTransform {
        CGAffineTransform(a: value(at: 0), b: value(at: 1), c: value(at: 2), d: value(at: 3), tx: value(at: 4), ty: value(at: 5))
    }
    public var stringRepresentation: String { "[" + values.map { "\($0)" }.joined(separator: " ") + "]" }
    public var description: String { stringRepresentation }
}
#endif
