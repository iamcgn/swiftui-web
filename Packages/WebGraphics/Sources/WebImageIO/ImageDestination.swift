// ImageIO's image destinations on wasm, re-exported by the `ImageIO` shadow (Packages/Shadows) and by
// AVFoundation, which re-exports ImageIO on Apple's platforms (Kingfisher writes a video
// thumbnail's JPEG through it with only AVKit imported).
// Writing image files (IceCubes' compressor, Oscar's screenshots): a destination collects images
// and, when finalized, writes the first one's bytes into its data or file. This substrate ships no
// JPEG, GIF or WebP encoder, so an image keeps its own file's bytes when that file is already of
// the asked type (a JPEG re-saved as JPEG), and is otherwise written as PNG, which every reader of
// the bytes (the browser, `CGImageSource`, `UIImage(data:)`) sniffs from the bytes themselves.
// An image only a painter can turn into pixels (a recorded drawing) cannot be written here, so
// finalizing fails as Apple's does for an image it cannot encode.
#if os(WASI)
import WebFoundation
import WebFoundationFormats
import WebGraphics

/// Where image files are written: a mutable data object or a file.
public final class CGImageDestination: @unchecked Sendable {
    let data: NSMutableData?
    let url: URL?
    let type: String
    let capacity: Int
    var images: [CGImage] = []
    var finalized = false

    init(data: NSMutableData?, url: URL?, type: String, capacity: Int) {
        self.data = data
        self.url = url
        self.type = type
        self.capacity = capacity
    }

    /// The bytes the first image is written as: its own file's when that is of the asked type,
    /// otherwise PNG.
    var encoded: Data? {
        guard let image = images.first else { return nil }
        if let file = image._fileData, _ImageFileInfo(file)?.kind.typeIdentifier == type { return file }
        return image._pngData
    }
}

/// The file types a destination can write.
public func CGImageDestinationCopyTypeIdentifiers() -> CFArray {
    [_ImageFileInfo.Kind.png, .jpeg, .gif, .webp].map(\.typeIdentifier)
}

private func destinationType(_ type: CFString) -> Bool {
    [_ImageFileInfo.Kind.png, .jpeg, .gif, .webp].contains { $0.typeIdentifier == type } || type == "public.heic" || type == "public.tiff"
}

/// A destination that writes into `data`; nil for a type it cannot name.
public func CGImageDestinationCreateWithData(_ data: CFMutableData, _ type: CFString, _ count: Int, _ options: CFDictionary?) -> CGImageDestination? {
    destinationType(type) ? CGImageDestination(data: data, url: nil, type: type, capacity: count) : nil
}

/// A destination that writes the file at `url`; nil for a type it cannot name.
public func CGImageDestinationCreateWithURL(_ url: CFURL, _ type: CFString, _ count: Int, _ options: CFDictionary?) -> CGImageDestination? {
    destinationType(type) ? CGImageDestination(data: nil, url: url, type: type, capacity: count) : nil
}

/// Adds an image (its properties, such as the lossy compression quality, are not used here).
public func CGImageDestinationAddImage(_ idst: CGImageDestination, _ image: CGImage, _ properties: CFDictionary?) {
    guard !idst.finalized, idst.images.count < max(1, idst.capacity) else { return }
    idst.images.append(image)
}

/// Adds the image at `index` of a source.
public func CGImageDestinationAddImageFromSource(_ idst: CGImageDestination, _ isrc: CGImageSource, _ index: Int, _ properties: CFDictionary?) {
    guard let image = CGImageSourceCreateImageAtIndex(isrc, index, nil) else { return }
    CGImageDestinationAddImage(idst, image, properties)
}

/// Sets the file's own properties (not written here).
public func CGImageDestinationSetProperties(_ idst: CGImageDestination, _ properties: CFDictionary?) {}

/// Writes the images; false when there is none, or none this substrate can write.
public func CGImageDestinationFinalize(_ idst: CGImageDestination) -> Bool {
    guard !idst.finalized, let bytes = idst.encoded else { return false }
    idst.finalized = true
    if let data = idst.data { data.setData(bytes) }
    if let url = idst.url { return (try? bytes.write(to: url)) != nil }
    return true
}

public let kCGImageDestinationLossyCompressionQuality: CFString = "kCGImageDestinationLossyCompressionQuality"
public let kCGImageDestinationBackgroundColor: CFString = "kCGImageDestinationBackgroundColor"
public let kCGImageDestinationImageMaxPixelSize: CFString = "kCGImageDestinationImageMaxPixelSize"
public let kCGImageDestinationEmbedThumbnail: CFString = "kCGImageDestinationEmbedThumbnail"
public let kCGImageDestinationOptimizeColorForSharing: CFString = "kCGImageDestinationOptimizeColorForSharing"
#endif
