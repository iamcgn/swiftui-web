// ImageIO's image sources where there is no ImageIO (wasm; the `ImageIO` shadow re-exports
// this module, Packages/Shadows), Docs/elements/UIKit/Drawing.md, "Image sources". A source
// reads an image file's header (WebGraphics's `_ImageFileInfo`): its type, pixel size, frames,
// GIF/APNG/WebP delays and EXIF orientation, as the properties dictionaries Apple's returns.
// Its images are `CGImage`s of the file (the browser decodes them), and a thumbnail is the
// file with a smaller pixel size, which painters scale it to. Numbers in the dictionaries are
// `NSNumber`s, as Apple's are (cast them `as? NSNumber`).
// There is no image destination: writing files needs an encoder this module does not ship.

#if os(WASI)
import WebFoundation
import WebGraphics

/// An opaque source of image data: a file in memory, read from its header.
public final class CGImageSource: @unchecked Sendable {
    var data: Data
    var info: _ImageFileInfo?
    var isFinal: Bool
    let typeHint: String?

    init(data: Data, isFinal: Bool = true, typeHint: String? = nil) {
        self.data = data
        self.isFinal = isFinal
        self.typeHint = typeHint
        info = _ImageFileInfo(data)
    }
}

/// How far a source has read its data.
public enum CGImageSourceStatus: Int32, Sendable {
    case statusUnexpectedEOF = -5, statusInvalidData = -4, statusUnknownType = -3, statusReadingHeader = -2, statusIncomplete = -1, statusComplete = 0
}

// MARK: Option keys

public let kCGImageSourceTypeIdentifierHint: CFString = "kCGImageSourceTypeIdentifierHint"
public let kCGImageSourceShouldCache: CFString = "kCGImageSourceShouldCache"
public let kCGImageSourceShouldCacheImmediately: CFString = "kCGImageSourceShouldCacheImmediately"
public let kCGImageSourceShouldAllowFloat: CFString = "kCGImageSourceShouldAllowFloat"
public let kCGImageSourceCreateThumbnailFromImageIfAbsent: CFString = "kCGImageSourceCreateThumbnailFromImageIfAbsent"
public let kCGImageSourceCreateThumbnailFromImageAlways: CFString = "kCGImageSourceCreateThumbnailFromImageAlways"
public let kCGImageSourceThumbnailMaxPixelSize: CFString = "kCGImageSourceThumbnailMaxPixelSize"
public let kCGImageSourceCreateThumbnailWithTransform: CFString = "kCGImageSourceCreateThumbnailWithTransform"
public let kCGImageSourceSubsampleFactor: CFString = "kCGImageSourceSubsampleFactor"

// MARK: Property keys

public let kCGImagePropertyPixelWidth: CFString = "PixelWidth"
public let kCGImagePropertyPixelHeight: CFString = "PixelHeight"
public let kCGImagePropertyOrientation: CFString = "Orientation"
public let kCGImagePropertyDepth: CFString = "Depth"
public let kCGImagePropertyHasAlpha: CFString = "HasAlpha"
public let kCGImagePropertyColorModel: CFString = "ColorModel"
public let kCGImagePropertyColorModelRGB: CFString = "RGB"
public let kCGImagePropertyFileSize: CFString = "FileSize"
public let kCGImagePropertyDPIWidth: CFString = "DPIWidth"
public let kCGImagePropertyDPIHeight: CFString = "DPIHeight"
public let kCGImagePropertyTIFFDictionary: CFString = "{TIFF}"
public let kCGImagePropertyTIFFOrientation: CFString = "Orientation"
public let kCGImagePropertyExifDictionary: CFString = "{Exif}"
public let kCGImagePropertyExifPixelXDimension: CFString = "PixelXDimension"
public let kCGImagePropertyExifPixelYDimension: CFString = "PixelYDimension"
public let kCGImagePropertyJFIFDictionary: CFString = "{JFIF}"
public let kCGImagePropertyGIFDictionary: CFString = "{GIF}"
public let kCGImagePropertyGIFDelayTime: CFString = "DelayTime"
public let kCGImagePropertyGIFUnclampedDelayTime: CFString = "UnclampedDelayTime"
public let kCGImagePropertyGIFLoopCount: CFString = "LoopCount"
public let kCGImagePropertyGIFHasGlobalColorMap: CFString = "HasGlobalColorMap"
public let kCGImagePropertyPNGDictionary: CFString = "{PNG}"
public let kCGImagePropertyAPNGDelayTime: CFString = "DelayTime"
public let kCGImagePropertyAPNGUnclampedDelayTime: CFString = "UnclampedDelayTime"
public let kCGImagePropertyAPNGLoopCount: CFString = "LoopCount"
public let kCGImagePropertyWebPDictionary: CFString = "{WebP}"
public let kCGImagePropertyWebPDelayTime: CFString = "DelayTime"
public let kCGImagePropertyWebPUnclampedDelayTime: CFString = "UnclampedDelayTime"
public let kCGImagePropertyWebPLoopCount: CFString = "LoopCount"

/// EXIF orientations, as `kCGImagePropertyOrientation` holds them.
public enum CGImagePropertyOrientation: UInt32, Sendable {
    case up = 1, upMirrored, down, downMirrored, leftMirrored, right, rightMirrored, left
}

// MARK: Creating sources

/// A source over image bytes; nil when the bytes are empty.
public func CGImageSourceCreateWithData(_ data: CFData, _ options: CFDictionary?) -> CGImageSource? {
    data.isEmpty ? nil : CGImageSource(data: data, typeHint: options?[kCGImageSourceTypeIdentifierHint] as? String)
}

/// A source over the file at `url`; nil when it cannot be read.
public func CGImageSourceCreateWithURL(_ url: CFURL, _ options: CFDictionary?) -> CGImageSource? {
    guard let data = try? Data(contentsOf: url) else { return nil }
    return CGImageSourceCreateWithData(data, options)
}

/// A source over a data provider's bytes.
public func CGImageSourceCreateWithDataProvider(_ provider: CGDataProvider, _ options: CFDictionary?) -> CGImageSource? {
    provider.data.flatMap { CGImageSourceCreateWithData($0, options) }
}

/// A source that is handed its bytes as they arrive (`CGImageSourceUpdateData`).
public func CGImageSourceCreateIncremental(_ options: CFDictionary?) -> CGImageSource {
    CGImageSource(data: Data(), isFinal: false, typeHint: options?[kCGImageSourceTypeIdentifierHint] as? String)
}

/// Replaces an incremental source's bytes with all of them so far.
public func CGImageSourceUpdateData(_ isrc: CGImageSource, _ data: CFData, _ final: Bool) {
    isrc.data = data
    isrc.isFinal = final
    isrc.info = _ImageFileInfo(data)
}

public func CGImageSourceUpdateDataProvider(_ isrc: CGImageSource, _ provider: CGDataProvider, _ final: Bool) {
    CGImageSourceUpdateData(isrc, provider.data ?? Data(), final)
}

// MARK: Reading sources

/// The source's uniform type identifier (`public.png`, `com.compuserve.gif`), or nil.
public func CGImageSourceGetType(_ isrc: CGImageSource) -> CFString? {
    (isrc.info?.kind ?? _ImageFileInfo.kind(of: isrc.data))?.typeIdentifier
}

/// The types a source can read.
public func CGImageSourceCopyTypeIdentifiers() -> CFArray {
    [_ImageFileInfo.Kind.png, .jpeg, .gif, .webp].map(\.typeIdentifier)
}

/// The number of images (frames) in the source; 0 before its header is read.
public func CGImageSourceGetCount(_ isrc: CGImageSource) -> Int { isrc.info?.frameCount ?? 0 }

public func CGImageSourceGetPrimaryImageIndex(_ isrc: CGImageSource) -> Int { 0 }

public func CGImageSourceGetStatus(_ isrc: CGImageSource) -> CGImageSourceStatus {
    if isrc.info != nil { return isrc.isFinal ? .statusComplete : .statusIncomplete }
    if isrc.data.isEmpty { return .statusReadingHeader }
    if _ImageFileInfo.kind(of: isrc.data) == nil { return isrc.data.count < 12 && !isrc.isFinal ? .statusReadingHeader : .statusUnknownType }
    return isrc.isFinal ? .statusInvalidData : .statusReadingHeader
}

public func CGImageSourceGetStatusAtIndex(_ isrc: CGImageSource, _ index: Int) -> CGImageSourceStatus {
    index < CGImageSourceGetCount(isrc) ? CGImageSourceGetStatus(isrc) : .statusUnknownType
}

/// The file's own properties: its size, and the format's dictionary with the loop count.
public func CGImageSourceCopyProperties(_ isrc: CGImageSource, _ options: CFDictionary?) -> CFDictionary? {
    guard let info = isrc.info else { return nil }
    var properties: [String: Any] = [kCGImagePropertyFileSize: NSNumber(value: isrc.data.count)]
    if let key = formatDictionaryKey(info.kind), let loops = info.loopCount {
        properties[key] = [kCGImagePropertyGIFLoopCount: NSNumber(value: loops)] as [String: Any]
    }
    return properties
}

/// One image's properties: pixel size, orientation, colour model and the frame's delay.
public func CGImageSourceCopyPropertiesAtIndex(_ isrc: CGImageSource, _ index: Int, _ options: CFDictionary?) -> CFDictionary? {
    guard let info = isrc.info, index >= 0, index < info.frameCount else { return nil }
    var properties: [String: Any] = [
        kCGImagePropertyPixelWidth: NSNumber(value: info.pixelWidth),
        kCGImagePropertyPixelHeight: NSNumber(value: info.pixelHeight),
        kCGImagePropertyDepth: NSNumber(value: 8),
        kCGImagePropertyColorModel: kCGImagePropertyColorModelRGB,
        kCGImagePropertyHasAlpha: NSNumber(value: info.kind != .jpeg),
    ]
    if info.kind == .jpeg {
        properties[kCGImagePropertyOrientation] = NSNumber(value: info.orientation)
        properties[kCGImagePropertyTIFFDictionary] = [kCGImagePropertyTIFFOrientation: NSNumber(value: info.orientation)] as [String: Any]
    }
    if let key = formatDictionaryKey(info.kind) {
        var format: [String: Any] = [:]
        if index < info.frameDelays.count {
            let delay = info.frameDelays[index]
            // ImageIO clamps short delays to a tenth of a second, as browsers do.
            format[kCGImagePropertyGIFUnclampedDelayTime] = NSNumber(value: delay)
            format[kCGImagePropertyGIFDelayTime] = NSNumber(value: delay < 0.011 ? 0.1 : delay)
        }
        if let loops = info.loopCount { format[kCGImagePropertyGIFLoopCount] = NSNumber(value: loops) }
        properties[key] = format
    }
    return properties
}

/// The image at `index`: the file's frame, drawn by the painters' decoder.
public func CGImageSourceCreateImageAtIndex(_ isrc: CGImageSource, _ index: Int, _ options: CFDictionary?) -> CGImage? {
    guard let info = isrc.info, index >= 0, index < info.frameCount else { return nil }
    return CGImage(_content: .file(isrc.data, info, frame: index))
}

/// A thumbnail of the image at `index`: the file at a pixel size no larger than the
/// `kCGImageSourceThumbnailMaxPixelSize` option (the painters scale it down when drawing).
public func CGImageSourceCreateThumbnailAtIndex(_ isrc: CGImageSource, _ index: Int, _ options: CFDictionary?) -> CGImage? {
    guard var info = isrc.info, index >= 0, index < info.frameCount else { return nil }
    if let limit = number(options?[kCGImageSourceThumbnailMaxPixelSize]), limit > 0 {
        let longest = Double(max(info.pixelWidth, info.pixelHeight))
        if longest > limit {
            let factor = limit / longest
            info.pixelWidth = max(1, Int((Double(info.pixelWidth) * factor).rounded()))
            info.pixelHeight = max(1, Int((Double(info.pixelHeight) * factor).rounded()))
        }
    }
    return CGImage(_content: .file(isrc.data, info, frame: index))
}

private func formatDictionaryKey(_ kind: _ImageFileInfo.Kind) -> String? {
    switch kind {
    case .gif: return kCGImagePropertyGIFDictionary
    case .png: return kCGImagePropertyPNGDictionary
    case .webp: return kCGImagePropertyWebPDictionary
    case .jpeg: return nil
    }
}

/// An option's number, whichever numeric type the app passed.
private func number(_ value: Any?) -> Double? {
    switch value {
    case let n as NSNumber: return n.doubleValue
    case let n as Double: return n
    case let n as Int: return Double(n)
    case let n as Float: return Double(n)
    case let n as UInt: return Double(n)
    default: return nil
    }
}
#endif
