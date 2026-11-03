// CoreGraphics's image types where there is no CoreGraphics (wasm and Linux; Apple platforms
// keep Apple's), Docs/elements/UIKit/Drawing.md, "CGImage". A `CGImage` is what a painter can
// draw: an image file (PNG, JPEG, GIF or WebP bytes, which the browser decodes), a bitmap
// (RGBA pixels from a data provider), or a recording (what a graphics context drew, replayed
// scaled). It knows its pixel size and can be cropped and drawn into a rectangle as display
// list commands; it never holds decoded pixels it was not given.

#if !canImport(CoreGraphics) || os(WASI)
#if os(WASI)
import WebFoundation   // never full Foundation on wasm: it links ICU (decisions 0006, 0017)
#else
import Foundation
#endif

/// A colour space stand-in: every colour is sRGB (decision 0006).
public final class CGColorSpace: @unchecked Sendable {
    public static let sRGB = "kCGColorSpaceSRGB"
    public static let displayP3 = "kCGColorSpaceDisplayP3"
    public static let genericRGBLinear = "kCGColorSpaceGenericRGBLinear"
    public static let genericGrayGamma2_2 = "kCGColorSpaceGenericGrayGamma2_2"
    public static let linearGray = "kCGColorSpaceLinearGray"
    /// Colour components before alpha: 3 for RGB, 1 for grey.
    public let numberOfComponents: Int
    /// The space's name (sRGB unless it was made by a grey name).
    public let name: String?
    public init(_numberOfComponents components: Int, name: String? = nil) {
        numberOfComponents = components
        self.name = name ?? (components == 1 ? Self.genericGrayGamma2_2 : Self.sRGB)
    }
    public convenience init?(name: String) {
        // A grey space by its name ("…Gray…"); not `contains`, whose String overload links the
        // Regex engine into the wasm bundle (decision 0006).
        let gray = Array("Gray".utf8), bytes = Array(name.utf8)
        let isGray = bytes.count >= gray.count && (0...(bytes.count - gray.count)).contains { Array(bytes[$0..<($0 + gray.count)]) == gray }
        self.init(_numberOfComponents: isGray ? 1 : 3, name: name)
    }
    public var model: CGColorSpaceModel { numberOfComponents == 1 ? .monochrome : .rgb }
}
public func CGColorSpaceCreateDeviceRGB() -> CGColorSpace { CGColorSpace(_numberOfComponents: 3) }
public func CGColorSpaceCreateDeviceGray() -> CGColorSpace { CGColorSpace(_numberOfComponents: 1) }

/// The kind of a colour space's components.
public enum CGColorSpaceModel: Int32, Sendable {
    case unknown = -1, monochrome, rgb, cmyk, lab, deviceN, indexed, pattern, XYZ
}

/// Where alpha is in a pixel, and whether the colours are multiplied by it.
public enum CGImageAlphaInfo: UInt32, Sendable {
    case none = 0, premultipliedLast, premultipliedFirst, last, first, noneSkipLast, noneSkipFirst, alphaOnly
}

/// The byte order of a pixel's components.
public enum CGImageByteOrderInfo: UInt32, Sendable {
    case orderMask = 0x7000, orderDefault = 0, order16Little = 0x1000, order32Little = 0x2000, order16Big = 0x3000, order32Big = 0x4000
}

/// A bitmap's layout: its alpha info, float components and byte order.
public struct CGBitmapInfo: OptionSet, Sendable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }
    public init(alphaInfo: CGImageAlphaInfo) { rawValue = alphaInfo.rawValue }
    public static let alphaInfoMask = CGBitmapInfo(rawValue: 0x1F)
    public static let floatInfoMask = CGBitmapInfo(rawValue: 0xF00)
    public static let floatComponents = CGBitmapInfo(rawValue: 1 << 8)
    public static let byteOrderMask = CGBitmapInfo(rawValue: 0x7000)
    public static let byteOrderDefault = CGBitmapInfo([])
    public static let byteOrder16Little = CGBitmapInfo(rawValue: 0x1000)
    public static let byteOrder32Little = CGBitmapInfo(rawValue: 0x2000)
    public static let byteOrder16Big = CGBitmapInfo(rawValue: 0x3000)
    public static let byteOrder32Big = CGBitmapInfo(rawValue: 0x4000)
    public static let byteOrder16Host = byteOrder16Little
    public static let byteOrder32Host = byteOrder32Little
}

/// How colours are mapped into a destination's gamut (sRGB only here, so all alike).
public enum CGColorRenderingIntent: Int32, Sendable {
    case defaultIntent = 0, absoluteColorimetric, relativeColorimetric, perceptual, saturation
}

/// How smoothly a scaled image is resampled.
public enum CGInterpolationQuality: Int32, Sendable {
    case `default` = 0, none, low, high, medium
}

/// Bytes an image is made from.
public final class CGDataProvider: @unchecked Sendable {
    public let data: Data?
    public init?(data: Data) { self.data = data }
    /// A provider of the file at `url` (a file URL the app can read).
    public convenience init?(url: URL) {
        guard let data = try? Data(contentsOf: url) else { return nil }
        self.init(data: data)
    }
}

/// A bitmap image or image mask. An image read from a file is upright (browsers decode a JPEG
/// with its EXIF orientation applied), so its size is the size it shows.
public final class CGImage: Hashable, @unchecked Sendable {
    /// What an image draws.
    public enum _Content: @unchecked Sendable {
        /// An image file's bytes and header, and which of its frames this image is.
        case file(Data, _ImageFileInfo, frame: Int)
        /// Premultiplied RGBA pixels.
        case bitmap(DisplayBitmap)
        /// Commands in a `size`-point space, made at `scale` pixels per point.
        case recording([DisplayCommand], size: CGSize, scale: CGFloat)
    }

    public let _content: _Content
    /// The part of the content shown, in the content's pixels (all of it unless cropped).
    public let _crop: CGRect
    public let width: Int
    public let height: Int
    public let bitsPerComponent = 8
    public let bitsPerPixel = 32
    public var bytesPerRow: Int { width * 4 }
    public let colorSpace: CGColorSpace? = CGColorSpaceCreateDeviceRGB()
    public let bitmapInfo = CGBitmapInfo(alphaInfo: .premultipliedLast)
    public var alphaInfo: CGImageAlphaInfo { .premultipliedLast }
    public var byteOrderInfo: CGImageByteOrderInfo { .orderDefault }
    public let decode: UnsafePointer<CGFloat>? = nil
    public let shouldInterpolate: Bool
    public let renderingIntent: CGColorRenderingIntent
    public let isMask = false

    public init(_content content: _Content, crop: CGRect? = nil, shouldInterpolate: Bool = true,
                intent: CGColorRenderingIntent = .defaultIntent) {
        let full: CGSize
        switch content {
        case .file(_, let info, _): full = CGSize(width: info.uprightPixelSize.width, height: info.uprightPixelSize.height)
        case .bitmap(let bitmap): full = CGSize(width: bitmap.width, height: bitmap.height)
        case .recording(_, let size, let scale): full = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        }
        let crop = (crop ?? CGRect(origin: .zero, size: full)).intersection(CGRect(origin: .zero, size: full)).integral
        _content = content
        _crop = crop.isNull ? .zero : crop
        width = Int(_crop.width)
        height = Int(_crop.height)
        self.shouldInterpolate = shouldInterpolate
        renderingIntent = intent
    }

    /// An image from raw pixels: 8-bit components, 32 bits a pixel, alpha first or last (or
    /// skipped), in either byte order. Other layouts give nil.
    public convenience init?(width: Int, height: Int, bitsPerComponent: Int, bitsPerPixel: Int, bytesPerRow: Int,
                             space: CGColorSpace, bitmapInfo: CGBitmapInfo, provider: CGDataProvider,
                             decode: UnsafePointer<CGFloat>?, shouldInterpolate: Bool, intent: CGColorRenderingIntent) {
        guard width > 0, height > 0, bitsPerComponent == 8, bitsPerPixel == 32, bytesPerRow >= width * 4,
              let data = provider.data, data.count >= bytesPerRow * (height - 1) + width * 4,
              let alpha = CGImageAlphaInfo(rawValue: bitmapInfo.rawValue & CGBitmapInfo.alphaInfoMask.rawValue) else { return nil }
        let bytes = [UInt8](data)
        let little = bitmapInfo.rawValue & CGBitmapInfo.byteOrderMask.rawValue == CGBitmapInfo.byteOrder32Little.rawValue
        let alphaFirst = alpha == .premultipliedFirst || alpha == .first || alpha == .noneSkipFirst
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let s = y * bytesPerRow + x * 4
                var p = [bytes[s], bytes[s + 1], bytes[s + 2], bytes[s + 3]]
                if little { p.reverse() }
                var (r, g, b, a) = alphaFirst ? (p[1], p[2], p[3], p[0]) : (p[0], p[1], p[2], p[3])
                switch alpha {
                case .none, .noneSkipLast, .noneSkipFirst: a = 255
                case .last, .first:
                    r = UInt8((Int(r) * Int(a) + 127) / 255); g = UInt8((Int(g) * Int(a) + 127) / 255); b = UInt8((Int(b) * Int(a) + 127) / 255)
                case .alphaOnly: (r, g, b) = (0, 0, 0)
                case .premultipliedLast, .premultipliedFirst: break
                }
                let d = (y * width + x) * 4
                rgba[d] = r; rgba[d + 1] = g; rgba[d + 2] = b; rgba[d + 3] = a
            }
        }
        self.init(_content: .bitmap(DisplayBitmap(width: width, height: height, pixels: rgba)), shouldInterpolate: shouldInterpolate, intent: intent)
    }

    /// An image from a provider of PNG bytes.
    public convenience init?(pngDataProviderSource source: CGDataProvider, decode: UnsafePointer<CGFloat>?,
                             shouldInterpolate: Bool, intent: CGColorRenderingIntent) {
        guard let data = source.data, let info = _ImageFileInfo(data), info.kind == .png else { return nil }
        self.init(_content: .file(data, info, frame: 0), shouldInterpolate: shouldInterpolate, intent: intent)
    }

    /// An image from a provider of JPEG bytes.
    public convenience init?(jpegDataProviderSource source: CGDataProvider, decode: UnsafePointer<CGFloat>?,
                             shouldInterpolate: Bool, intent: CGColorRenderingIntent) {
        guard let data = source.data, let info = _ImageFileInfo(data), info.kind == .jpeg else { return nil }
        self.init(_content: .file(data, info, frame: 0), shouldInterpolate: shouldInterpolate, intent: intent)
    }

    /// The pixels of an image made from them; nil for one made from a file or a drawing, whose
    /// pixels only a painter makes.
    public var dataProvider: CGDataProvider? {
        guard case .bitmap(let bitmap) = _content else { return nil }
        if _crop == CGRect(x: 0, y: 0, width: bitmap.width, height: bitmap.height) { return CGDataProvider(data: Data(bitmap.pixels)) }
        var rows: [UInt8] = []
        for y in Int(_crop.minY)..<Int(_crop.maxY) {
            let start = (y * bitmap.width + Int(_crop.minX)) * 4
            rows += bitmap.pixels[start..<(start + width * 4)]
        }
        return CGDataProvider(data: Data(rows))
    }

    /// The uniform type identifier of the file the image was read from.
    public var utType: String? {
        guard case .file(_, let info, _) = _content else { return nil }
        return info.kind.typeIdentifier
    }

    /// The part of the image inside `rect` (in its pixels), or nil when they do not meet.
    public func cropping(to rect: CGRect) -> CGImage? {
        let local = rect.standardized.integral.intersection(CGRect(x: 0, y: 0, width: width, height: height))
        guard !local.isNull, local.width >= 1, local.height >= 1 else { return nil }
        return CGImage(_content: _content, crop: local.offsetBy(dx: _crop.minX, dy: _crop.minY),
                       shouldInterpolate: shouldInterpolate, intent: renderingIntent)
    }

    public func copy() -> CGImage? { self }
    public func copy(colorSpace space: CGColorSpace) -> CGImage? { self }

    /// The image file's bytes, when the image is a whole frame of a file.
    public var _fileData: Data? {
        guard case .file(let data, let info, _) = _content,
              _crop == CGRect(x: 0, y: 0, width: info.uprightPixelSize.width, height: info.uprightPixelSize.height) else { return nil }
        return data
    }

    /// The image as PNG bytes: a PNG file's own, or a bitmap's pixels encoded; nil for any other
    /// content, which only a painter can turn into pixels.
    public var _pngData: Data? {
        switch _content {
        case .file(_, let info, _) where info.kind == .png: return _fileData
        case .bitmap:
            guard let provider = dataProvider, let pixels = provider.data else { return nil }
            return Data(_PNGEncoder.encode(width: width, height: height, rgba: [UInt8](pixels)))
        default: return nil
        }
    }

    /// The commands that draw the image into `rect` (in the display list's points).
    public func _commands(in rect: CGRect) -> [DisplayCommand] {
        guard width > 0, height > 0, rect.width > 0, rect.height > 0 else { return [] }
        // The whole content, placed so the cropped part lands on `rect`.
        let sx = rect.width / _crop.width, sy = rect.height / _crop.height
        let fullRect: CGRect
        let draw: [DisplayCommand]
        switch _content {
        case .file(let data, let info, _):
            let upright = CGSize(width: info.uprightPixelSize.width, height: info.uprightPixelSize.height)
            fullRect = CGRect(x: rect.minX - _crop.minX * sx, y: rect.minY - _crop.minY * sy,
                              width: upright.width * sx, height: upright.height * sy)
            var image = ImageDraw(file: _dataURL(data, info), scale: 1, pixelSize: upright, rect: fullRect)
            image.smoothing = shouldInterpolate
            draw = [.drawImage(image)]
        case .bitmap(let bitmap):
            fullRect = CGRect(x: rect.minX - _crop.minX * sx, y: rect.minY - _crop.minY * sy,
                              width: CGFloat(bitmap.width) * sx, height: CGFloat(bitmap.height) * sy)
            draw = [.drawBitmap(bitmap, rect: fullRect)]
        case .recording(let commands, let size, let scale):
            fullRect = CGRect(x: rect.minX - _crop.minX * sx, y: rect.minY - _crop.minY * sy,
                              width: size.width * scale * sx, height: size.height * scale * sy)
            guard size.width > 0, size.height > 0 else { return [] }
            let transform = CGAffineTransform(a: fullRect.width / size.width, b: 0, c: 0, d: fullRect.height / size.height,
                                              tx: fullRect.minX, ty: fullRect.minY)
            draw = [.concat(transform)] + commands
        }
        let cropped = fullRect.integral != rect.integral
        return [.save] + (cropped ? [.clipRect(rect)] : []) + draw + [.restore]
    }

    private var dataURL: String?
    private func _dataURL(_ data: Data, _ info: _ImageFileInfo) -> String {
        if let dataURL { return dataURL }
        let url = "data:\(info.kind.mimeType);base64," + data.base64EncodedString()
        dataURL = url
        return url
    }

    public static func == (lhs: CGImage, rhs: CGImage) -> Bool { lhs === rhs }
    public func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(self)) }
}
#endif
