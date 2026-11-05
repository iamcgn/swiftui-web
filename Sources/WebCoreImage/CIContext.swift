// Rendering, Docs/elements/CoreImage.md. A context turns an image's recipe into a CGImage that
// records it: display-list commands in a space the size of the rectangle asked for, flipped from
// Core Image's bottom-left origin to the top-left one a CGImage's rows run from. The painters
// draw the recording (and run its filters) when the app shows the image. Such a CGImage has no
// pixels to read back, as any recorded CGImage here.

#if !canImport(CoreGraphics) || os(WASI)
import WebFoundation
import WebGraphics
#if canImport(UIKit)
import UIKit
#endif

/// Options for a context (accepted; the painters choose how to draw).
public struct CIContextOption: RawRepresentable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let workingColorSpace = CIContextOption(rawValue: "working_color_space")
    public static let outputColorSpace = CIContextOption(rawValue: "output_color_space")
    public static let workingFormat = CIContextOption(rawValue: "working_format")
    public static let useSoftwareRenderer = CIContextOption(rawValue: "software_renderer")
    public static let cacheIntermediates = CIContextOption(rawValue: "kCIContextCacheIntermediates")
    public static let priorityRequestLow = CIContextOption(rawValue: "priority_request_low")
    public static let highQualityDownsample = CIContextOption(rawValue: "high_quality_downsample")
    public static let outputPremultiplied = CIContextOption(rawValue: "output_premultiplied")
    public static let name = CIContextOption(rawValue: "name")
}

/// A pixel format for rendering (accepted; a recording has none).
public struct CIFormat: RawRepresentable, Hashable, Sendable {
    public let rawValue: Int32
    public init(rawValue: Int32) { self.rawValue = rawValue }
    public static let ARGB8 = CIFormat(rawValue: 264)
    public static let BGRA8 = CIFormat(rawValue: 266)
    public static let RGBA8 = CIFormat(rawValue: 264 + 8)
    public static let RGBAh = CIFormat(rawValue: 2056)
    public static let RGBAf = CIFormat(rawValue: 2312)
    public static let A8 = CIFormat(rawValue: 265)
    public static let L8 = CIFormat(rawValue: 1797)
}

/// Renders images.
public final class CIContext: @unchecked Sendable {
    public init(options: [CIContextOption: Any]? = nil) {}
    public convenience init() { self.init(options: nil) }

    /// A CGImage of the part of `image` inside `fromRect` (Core Image's space, one pixel per
    /// unit); nil for an empty or endless rectangle.
    public func createCGImage(_ image: CIImage, from fromRect: CGRect) -> CGImage? {
        let rect = fromRect.standardized.integral
        guard !rect.isNull, !rect.isInfinite, rect.width >= 1, rect.height >= 1,
              rect.width <= 32768, rect.height <= 32768 else { return nil }
        // Core Image's (x, y) lands at (x − minX, maxY − y) in the recording.
        let flip = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: -rect.minX, ty: rect.maxY)
        let size = CGSize(width: rect.width, height: rect.height)
        let commands: [DisplayCommand] = [.save, .clipRect(CGRect(origin: .zero, size: size)), .concat(flip)]
            + image.recipe.commands(in: rect) + [.restore]
        return CGImage(_content: .recording(commands, size: size, scale: 1))
    }

    public func createCGImage(_ image: CIImage, from fromRect: CGRect, format: CIFormat, colorSpace: CGColorSpace?) -> CGImage? {
        createCGImage(image, from: fromRect)
    }

    public func createCGImage(_ image: CIImage, from fromRect: CGRect, format: CIFormat, colorSpace: CGColorSpace?,
                              deferred: Bool) -> CGImage? {
        createCGImage(image, from: fromRect)
    }

    /// Lets go of cached intermediates; there are none.
    public func clearCaches() {}
    public func reclaimResources() {}

    public var workingColorSpace: CGColorSpace? { CGColorSpaceCreateDeviceRGB() }
    public var workingFormat: CIFormat { .RGBAh }
}

#if canImport(UIKit)
extension CIColor {
    /// The UIKit colour's components.
    public convenience init(color: UIColor) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        _ = color.getRed(&r, green: &g, blue: &b, alpha: &a)
        self.init(red: r, green: g, blue: b, alpha: a)
    }
}

extension UIColor {
    public convenience init(ciColor: CIColor) {
        self.init(red: ciColor.red, green: ciColor.green, blue: ciColor.blue, alpha: ciColor.alpha)
    }
}

extension CIImage {
    /// The image of a UIImage's CGImage; nil for one with none (a symbol or a catalog image).
    public convenience init?(image: UIImage) {
        guard let cgImage = image.cgImage else { return nil }
        self.init(cgImage: cgImage)
    }

    public convenience init?(image: UIImage, options: [CIImageOption: Any]?) { self.init(image: image) }
}

extension UIImage {
    /// An image of a Core Image recipe, rendered over its extent; empty for an endless one.
    public convenience init(ciImage: CIImage, scale: CGFloat, orientation: UIImage.Orientation) {
        let made = CIContext().createCGImage(ciImage, from: ciImage.extent)
            ?? CIContext().createCGImage(CIImage.clear, from: CGRect(x: 0, y: 0, width: 1, height: 1))!
        self.init(cgImage: made, scale: scale, orientation: orientation)
    }

    public convenience init(ciImage: CIImage) { self.init(ciImage: ciImage, scale: 1, orientation: .up) }
}
#endif
#endif
