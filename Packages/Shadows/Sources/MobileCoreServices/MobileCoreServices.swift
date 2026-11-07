// Apple's `MobileCoreServices` module for wasm: the `kUTType` names of the common types (the
// identifiers `UTType` has, as Core Foundation strings), which image and document code still
// passes to ImageIO and the pickers, and the tag functions that map a filename extension or a
// MIME type to a type and back (Alamofire's multipart uploads name each part's MIME type with
// them). `UTType` itself is in `UniformTypeIdentifiers`.
#if os(WASI)
import WebFoundation   // `CFString`

public let kUTTypeItem: CFString = "public.item"
public let kUTTypeContent: CFString = "public.content"
public let kUTTypeData: CFString = "public.data"
public let kUTTypeText: CFString = "public.text"
public let kUTTypePlainText: CFString = "public.plain-text"
public let kUTTypeUTF8PlainText: CFString = "public.utf8-plain-text"
public let kUTTypeURL: CFString = "public.url"
public let kUTTypeFileURL: CFString = "public.file-url"
public let kUTTypeImage: CFString = "public.image"
public let kUTTypeJPEG: CFString = "public.jpeg"
public let kUTTypePNG: CFString = "public.png"
public let kUTTypeGIF: CFString = "com.compuserve.gif"
public let kUTTypeTIFF: CFString = "public.tiff"
public let kUTTypeBMP: CFString = "com.microsoft.bmp"
public let kUTTypeLivePhoto: CFString = "com.apple.live-photo"
public let kUTTypeMovie: CFString = "public.movie"
public let kUTTypeVideo: CFString = "public.video"
public let kUTTypeAudio: CFString = "public.audio"
public let kUTTypeMPEG4: CFString = "public.mpeg-4"
public let kUTTypeQuickTimeMovie: CFString = "com.apple.quicktime-movie"
public let kUTTypePDF: CFString = "com.adobe.pdf"
public let kUTTypeJSON: CFString = "public.json"
public let kUTTypeHTML: CFString = "public.html"
public let kUTTypeArchive: CFString = "public.archive"
public let kUTTypeZipArchive: CFString = "public.zip-archive"
public let kUTTypeVCard: CFString = "public.vcard"

// MARK: - Tags

public let kUTTagClassFilenameExtension: CFString = "public.filename-extension"
public let kUTTagClassMIMEType: CFString = "public.mime-type"

/// A string a Create or Copy function hands back. Apple's is an `Unmanaged<CFString>`; a
/// `CFString` is a Swift `String` here, so this carries it with the same two methods.
public struct _CFStringReturn: Sendable {
    let value: CFString
    public func takeRetainedValue() -> CFString { value }
    public func takeUnretainedValue() -> CFString { value }
}

/// The types the tag functions know: identifier, filename extensions, MIME types (the first of
/// each is the preferred one).
private let tagged: [(String, [String], [String])] = [
    ("public.plain-text", ["txt", "text"], ["text/plain"]),
    ("public.html", ["html", "htm"], ["text/html"]),
    ("public.comma-separated-values-text", ["csv"], ["text/csv"]),
    ("public.json", ["json"], ["application/json"]),
    ("public.xml", ["xml"], ["application/xml", "text/xml"]),
    ("public.rtf", ["rtf"], ["text/rtf"]),
    ("public.vcard", ["vcf", "vcard"], ["text/vcard"]),
    ("public.png", ["png"], ["image/png"]),
    ("public.jpeg", ["jpeg", "jpg", "jpe"], ["image/jpeg"]),
    ("com.compuserve.gif", ["gif"], ["image/gif"]),
    ("public.heic", ["heic"], ["image/heic"]),
    ("public.tiff", ["tiff", "tif"], ["image/tiff"]),
    ("com.microsoft.bmp", ["bmp"], ["image/bmp"]),
    ("org.webmproject.webp", ["webp"], ["image/webp"]),
    ("public.svg-image", ["svg"], ["image/svg+xml"]),
    ("com.adobe.pdf", ["pdf"], ["application/pdf"]),
    ("public.zip-archive", ["zip"], ["application/zip"]),
    ("org.gnu.gnu-zip-archive", ["gz", "gzip"], ["application/gzip"]),
    ("public.mpeg-4", ["mp4"], ["video/mp4"]),
    ("com.apple.quicktime-movie", ["mov", "qt"], ["video/quicktime"]),
    ("public.mp3", ["mp3"], ["audio/mpeg"]),
    ("public.mpeg-4-audio", ["m4a"], ["audio/mp4"]),
    ("com.microsoft.waveform-audio", ["wav"], ["audio/wav"]),
]

/// The type a tag names (`kUTTagClassFilenameExtension` or `kUTTagClassMIMEType`); a tag no
/// type here knows gets a dynamic identifier, as on Apple platforms.
public func UTTypeCreatePreferredIdentifierForTag(_ inTagClass: CFString, _ inTag: CFString, _ inConformingToUTI: CFString?) -> _CFStringReturn? {
    let tag = inTag.lowercased()
    let found: (String, [String], [String])?
    switch inTagClass {
    case kUTTagClassFilenameExtension: found = tagged.first { $0.1.contains(tag) }
    case kUTTagClassMIMEType: found = tagged.first { $0.2.contains(tag) }
    default: return nil
    }
    return _CFStringReturn(value: found?.0 ?? "dyn." + tag)
}

/// The type's preferred tag of the class; nil when none is known.
public func UTTypeCopyPreferredTagWithClass(_ inUTI: CFString, _ inTagClass: CFString) -> _CFStringReturn? {
    guard let entry = tagged.first(where: { $0.0 == inUTI }) else { return nil }
    switch inTagClass {
    case kUTTagClassFilenameExtension: return entry.1.first.map { _CFStringReturn(value: $0) }
    case kUTTagClassMIMEType: return entry.2.first.map { _CFStringReturn(value: $0) }
    default: return nil
    }
}

/// Whether two identifiers name the same type.
public func UTTypeEqual(_ inUTI1: CFString, _ inUTI2: CFString) -> Bool { inUTI1 == inUTI2 }
#endif
