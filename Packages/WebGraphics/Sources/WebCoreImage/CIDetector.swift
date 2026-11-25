// Core Image's detector and the features it finds (Docs/elements/CoreImage.md). A QR code
// detector reads the code in an image whose pixels are at hand here (a CGImage made from
// pixels, such as a camera frame or a generated code, cropped or transformed); an image of a
// file's bytes has its pixels only in the browser, so it finds nothing in one. It reports the
// first code it reads. Faces, rectangles and text need models this module does not have, so a
// detector of those types is nil.

#if !canImport(CoreGraphics) || os(WASI)
import WebFoundation
import WebGraphics

public let CIDetectorTypeQRCode = "CIDetectorTypeQRCode"
public let CIDetectorTypeFace = "CIDetectorTypeFace"
public let CIDetectorTypeRectangle = "CIDetectorTypeRectangle"
public let CIDetectorTypeText = "CIDetectorTypeText"

public let CIDetectorAccuracy = "CIDetectorAccuracy"
public let CIDetectorAccuracyLow = "CIDetectorAccuracyLow"
public let CIDetectorAccuracyHigh = "CIDetectorAccuracyHigh"
public let CIDetectorTracking = "CIDetectorTracking"
public let CIDetectorMinFeatureSize = "CIDetectorMinFeatureSize"
public let CIDetectorMaxFeatureCount = "CIDetectorMaxFeatureCount"
public let CIDetectorNumberOfAngles = "CIDetectorNumberOfAngles"
public let CIDetectorImageOrientation = "CIDetectorImageOrientation"
public let CIDetectorEyeBlink = "CIDetectorEyeBlink"
public let CIDetectorSmile = "CIDetectorSmile"
public let CIDetectorFocalLength = "CIDetectorFocalLength"
public let CIDetectorAspectRatio = "CIDetectorAspectRatio"
public let CIDetectorReturnSubFeatures = "CIDetectorReturnSubFeatures"

public let CIFeatureTypeQRCode = "QRCode"
public let CIFeatureTypeFace = "Face"
public let CIFeatureTypeRectangle = "Rectangle"
public let CIFeatureTypeText = "Text"

/// Something a detector found in an image.
open class CIFeature: @unchecked Sendable {
    /// The kind of feature (`CIFeatureTypeQRCode`).
    open var type: String { "" }
    /// Where it is, in the image's coordinates.
    public let bounds: CGRect

    init(bounds: CGRect) { self.bounds = bounds }
}

/// A QR code a detector read: where its corners are and what it says.
open class CIQRCodeFeature: CIFeature, @unchecked Sendable {
    open override var type: String { CIFeatureTypeQRCode }
    public let topLeft: CGPoint
    public let topRight: CGPoint
    public let bottomLeft: CGPoint
    public let bottomRight: CGPoint
    /// The message, as UTF-8 text (or Latin-1 when its bytes are not UTF-8).
    public let messageString: String?
    /// The code's data codewords and the parameters it was encoded with.
    public let symbolDescriptor: CIQRCodeDescriptor?

    init(topLeft: CGPoint, topRight: CGPoint, bottomLeft: CGPoint, bottomRight: CGPoint,
         messageString: String?, symbolDescriptor: CIQRCodeDescriptor?) {
        self.topLeft = topLeft
        self.topRight = topRight
        self.bottomLeft = bottomLeft
        self.bottomRight = bottomRight
        self.messageString = messageString
        self.symbolDescriptor = symbolDescriptor
        let xs = [topLeft.x, topRight.x, bottomLeft.x, bottomRight.x]
        let ys = [topLeft.y, topRight.y, bottomLeft.y, bottomRight.y]
        let (minX, maxX, minY, maxY) = (xs.min() ?? 0, xs.max() ?? 0, ys.min() ?? 0, ys.max() ?? 0)
        super.init(bounds: CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY))
    }
}

/// Finds features in images: QR codes.
open class CIDetector: @unchecked Sendable {
    private let type: String

    /// A detector of `type`; nil for a type this module cannot detect (faces, rectangles, text).
    public init?(ofType type: String, context: CIContext?, options: [String: Any]? = nil) {
        guard type == CIDetectorTypeQRCode else { return nil }
        self.type = type
    }

    open func features(in image: CIImage) -> [CIFeature] { features(in: image, options: nil) }

    open func features(in image: CIImage, options: [String: Any]?) -> [CIFeature] {
        guard type == CIDetectorTypeQRCode, let picture = image.recipe.greyLevels(extent: image.extent),
              let found = QRCode.find(luminance: picture.levels, width: picture.width, height: picture.height) else { return [] }
        // From the picture's pixels (top-left origin) to the image's coordinates (bottom-left).
        func point(_ p: (x: Double, y: Double)) -> CGPoint {
            CGPoint(x: picture.origin.x + CGFloat(p.x * picture.scale), y: picture.origin.y + CGFloat((Double(picture.height) - p.y) * picture.scale))
        }
        let d = found.decoded
        let level = CIQRCodeDescriptor.ErrorCorrectionLevel(rawValue: d.level.ascii) ?? .levelM
        let descriptor = CIQRCodeDescriptor(payload: Data(d.dataCodewords), symbolVersion: d.version,
                                            maskPattern: UInt8(d.mask), errorCorrectionLevel: level)
        return [CIQRCodeFeature(topLeft: point(found.topLeft), topRight: point(found.topRight),
                                bottomLeft: point(found.bottomLeft), bottomRight: point(found.bottomRight),
                                messageString: d.text, symbolDescriptor: descriptor)]
    }
}

extension CIImage.Recipe {
    /// The recipe's grey levels over white across `extent`, row by row from the top, at most
    /// 2048 pixels a side (sampled every `scale` units beyond that); nil when a step's pixels
    /// are not at hand here.
    func greyLevels(extent: CGRect) -> (levels: [UInt8], width: Int, height: Int, origin: CGPoint, scale: Double)? {
        guard !extent.isNull, !extent.isInfinite, extent.width >= 1, extent.height >= 1, canSample else { return nil }
        let area = extent.integral
        let scale = max(1, Double(max(area.width, area.height)) / 2048)
        let width = Int((Double(area.width) / scale).rounded(.down))
        let height = Int((Double(area.height) / scale).rounded(.down))
        guard width > 0, height > 0 else { return nil }
        var levels = [UInt8](repeating: 255, count: width * height)
        for row in 0..<height {
            // Core Image's y runs up, so the picture's top row is the extent's top.
            let y = Double(area.maxY) - (Double(row) + 0.5) * scale
            for col in 0..<width {
                let x = Double(area.minX) + (Double(col) + 0.5) * scale
                levels[row * width + col] = grey(at: CGPoint(x: x, y: y))
            }
        }
        return (levels, width, height, area.origin, scale)
    }

    /// Whether every step can be sampled pixel by pixel here.
    private var canSample: Bool {
        switch self {
        case .empty, .color: return true
        case .bitmap(let image):
            if case .bitmap = image._content { return true }
            return false
        case .crop(_, let input), .transform(_, let input): return input.canSample
        case .over(let top, let bottom): return top.canSample && bottom.canSample
        case .matrix, .blur, .blend: return false
        }
    }

    /// The colour at `p` in Core Image's space, as premultiplied red, green, blue and alpha 0 to 1.
    private func color(at p: CGPoint) -> (r: Double, g: Double, b: Double, a: Double) {
        switch self {
        case .empty: return (0, 0, 0, 0)
        case .color(let c): return (c.red * c.alpha, c.green * c.alpha, c.blue * c.alpha, c.alpha)
        case .bitmap(let image):
            guard case .bitmap(let bitmap) = image._content else { return (0, 0, 0, 0) }
            let (x, y) = (Int(Double(p.x).rounded(.down)), image.height - 1 - Int(Double(p.y).rounded(.down)))
            guard x >= 0, x < image.width, y >= 0, y < image.height else { return (0, 0, 0, 0) }
            let i = ((y + Int(image._crop.minY)) * bitmap.width + x + Int(image._crop.minX)) * 4
            guard i >= 0, i + 3 < bitmap.pixels.count else { return (0, 0, 0, 0) }
            let px = bitmap.pixels
            return (Double(px[i]) / 255, Double(px[i + 1]) / 255, Double(px[i + 2]) / 255, Double(px[i + 3]) / 255)
        case .crop(let rect, let input):
            return rect.contains(p) ? input.color(at: p) : (0, 0, 0, 0)
        case .transform(let t, let input):
            return input.color(at: p.applying(t.inverted()))
        case .over(let top, let bottom):
            let (a, b) = (top.color(at: p), bottom.color(at: p))
            return (a.r + b.r * (1 - a.a), a.g + b.g * (1 - a.a), a.b + b.b * (1 - a.a), a.a + b.a * (1 - a.a))
        case .matrix, .blur, .blend: return (0, 0, 0, 0)
        }
    }

    private func grey(at p: CGPoint) -> UInt8 {
        let c = color(at: p)
        // Over white, then Rec. 601 luma.
        let (r, g, b) = (c.r + 1 - c.a, c.g + 1 - c.a, c.b + 1 - c.a)
        return UInt8(max(0, min(255, (0.299 * r + 0.587 * g + 0.114 * b) * 255)).rounded())
    }
}
#endif
