// A uniform type identifier, shared by SwiftUIWeb's transfer representations and UIKitWeb's
// document picker (uk-system-sheets); the SwiftUI package adds the MIME lookups and conformance.

#if os(WASI)
import WebFoundation   // its URL; never full Foundation on wasm: it links ICU (decisions 0006, 0017)
#endif

/// A uniform type identifier.
public struct UTType: Hashable, Sendable, CustomStringConvertible {
    public let identifier: String
    /// The type with the identifier; nil for an empty one. Apple's initializer is failable
    /// (nil for a type the system doesn't declare), and apps chain on it (Gifu's
    /// `UTType(type)?.conforms(to: .gif)`); here every non-empty identifier counts as declared.
    public init?(_ identifier: String) {
        guard !identifier.isEmpty else { return nil }
        self.identifier = identifier
    }
    /// The type with an identifier the SDK declares itself (its constants, MIME and drag lookups).
    public init(_declared identifier: String) { self.identifier = identifier }
    /// A type the app declares (its Info.plist's exported types on iOS; here the identifier).
    public init(exportedAs identifier: String, conformingTo parentType: UTType? = nil) { self.identifier = identifier }
    /// A type another app declares, which this one uses.
    public init(importedAs identifier: String, conformingTo parentType: UTType? = nil) { self.identifier = identifier }

    public static let item = UTType(_declared: "public.item")
    public static let data = UTType(_declared: "public.data")
    public static let content = UTType(_declared: "public.content")
    public static let text = UTType(_declared: "public.text")
    public static let plainText = UTType(_declared: "public.plain-text")
    public static let utf8PlainText = UTType(_declared: "public.utf8-plain-text")
    public static let url = UTType(_declared: "public.url")
    public static let fileURL = UTType(_declared: "public.file-url")
    public static let json = UTType(_declared: "public.json")
    public static let image = UTType(_declared: "public.image")
    public static let png = UTType(_declared: "public.png")
    public static let jpeg = UTType(_declared: "public.jpeg")
    public static let pdf = UTType(_declared: "com.adobe.pdf")
    public static let html = UTType(_declared: "public.html")
    public static let rtf = UTType(_declared: "public.rtf")
    public static let commaSeparatedText = UTType(_declared: "public.comma-separated-values-text")
    public static let folder = UTType(_declared: "public.folder")
    public static let directory = UTType(_declared: "public.directory")
    public static let compositeContent = UTType(_declared: "public.composite-content")
    public static let utf16PlainText = UTType(_declared: "public.utf16-plain-text")
    public static let delimitedText = UTType(_declared: "public.delimited-values-text")
    public static let tabSeparatedText = UTType(_declared: "public.tab-separated-values-text")
    public static let sourceCode = UTType(_declared: "public.source-code")
    public static let swiftSource = UTType(_declared: "public.swift-source")
    public static let javaScript = UTType(_declared: "com.netscape.javascript-source")
    public static let propertyList = UTType(_declared: "com.apple.property-list")
    public static let yaml = UTType(_declared: "public.yaml")
    public static let log = UTType(_declared: "public.log")
    public static let gif = UTType(_declared: "com.compuserve.gif")
    public static let heic = UTType(_declared: "public.heic")
    public static let tiff = UTType(_declared: "public.tiff")
    public static let bmp = UTType(_declared: "com.microsoft.bmp")
    public static let svg = UTType(_declared: "public.svg-image")
    public static let webP = UTType(_declared: "org.webmproject.webp")
    public static let audiovisualContent = UTType(_declared: "public.audiovisual-content")
    public static let movie = UTType(_declared: "public.movie")
    public static let video = UTType(_declared: "public.video")
    public static let mpeg4Movie = UTType(_declared: "public.mpeg-4")
    public static let quickTimeMovie = UTType(_declared: "com.apple.quicktime-movie")
    public static let audio = UTType(_declared: "public.audio")
    public static let mp3 = UTType(_declared: "public.mp3")
    public static let mpeg4Audio = UTType(_declared: "public.mpeg-4-audio")
    public static let wav = UTType(_declared: "com.microsoft.waveform-audio")
    public static let archive = UTType(_declared: "public.archive")
    public static let zip = UTType(_declared: "public.zip-archive")
    public static let gzip = UTType(_declared: "org.gnu.gnu-zip-archive")
    public static let vCard = UTType(_declared: "public.vcard")
    public static let emailMessage = UTType(_declared: "public.email-message")
    public static let spreadsheet = UTType(_declared: "public.spreadsheet")
    public static let presentation = UTType(_declared: "public.presentation")
    public static let epub = UTType(_declared: "org.idpf.epub-container")
    public static let font = UTType(_declared: "public.font")

    /// The identifier, as Apple's description gives it.
    public var description: String { identifier }
    /// Whether the system declares the type: the `public.` and `com.apple.` ones.
    public var isPublic: Bool { identifier.hasPrefix("public.") }
    public var isDeclared: Bool { true }
    public var isDynamic: Bool { identifier.hasPrefix("dyn.") }

    /// The type for a filename extension, where one is known here.
    public init?(filenameExtension: String) {
        let lower = filenameExtension.lowercased()
        let aliases: [String: String] = ["txt": "public.plain-text", "jpeg": "public.jpeg", "jpe": "public.jpeg", "htm": "public.html", "text": "public.plain-text",
                                         "tif": "public.tiff", "yml": "public.yaml", "m4v": "public.mpeg-4", "qt": "com.apple.quicktime-movie",
                                         "wave": "com.microsoft.waveform-audio"]
        guard let identifier = aliases[lower] ?? Self._preferredExtensions.first(where: { $0.value == lower })?.key else { return nil }
        self.identifier = identifier
    }

    /// The file extension for the common types (a download's name, the open panel's filter,
    /// `URL.appendingPathComponent(_:conformingTo:)`): each declared type's preferred tag in
    /// Apple's system type table, nil for the abstract ones (data, image, movie, archive…).
    public var preferredFilenameExtension: String? {
        if let known = Self._preferredExtensions[identifier] { return known }
        // An exported type's identifier ends with its extension by convention ("com.example.notes").
        guard !identifier.hasPrefix("public."), !identifier.hasPrefix("com.apple."), !identifier.hasPrefix("dyn.") else { return nil }
        return identifier.split(separator: ".").last.map(String.init)
    }

    /// Each declared type's preferred filename extension (the system type table's first tag).
    private static let _preferredExtensions: [String: String] = [
        "public.plain-text": "txt", "public.utf8-plain-text": "txt", "public.utf16-plain-text": "txt", "public.text": "txt",
        "public.json": "json", "public.png": "png", "public.jpeg": "jpg", "com.adobe.pdf": "pdf", "public.rtf": "rtf",
        "public.html": "html", "public.xml": "xml", "public.comma-separated-values-text": "csv",
        "public.tab-separated-values-text": "tsv", "public.swift-source": "swift", "com.netscape.javascript-source": "js",
        "com.apple.property-list": "plist", "public.yaml": "yaml", "public.log": "log", "com.compuserve.gif": "gif",
        "public.heic": "heic", "public.tiff": "tiff", "com.microsoft.bmp": "bmp", "public.svg-image": "svg",
        "org.webmproject.webp": "webp", "public.mpeg-4": "mp4", "com.apple.quicktime-movie": "mov", "public.mp3": "mp3",
        "public.mpeg-4-audio": "m4a", "com.microsoft.waveform-audio": "wav", "public.zip-archive": "zip",
        "org.gnu.gnu-zip-archive": "gz", "public.vcard": "vcf", "public.email-message": "eml", "org.idpf.epub-container": "epub",
    ]

    /// Whether a URL of the type names a directory: folders, packages, bundles and volumes.
    fileprivate var _isDirectoryType: Bool {
        switch identifier {
        case "public.directory", "public.folder", "public.volume", "com.apple.package", "com.apple.bundle", "com.apple.application-bundle": return true
        default: return false
        }
    }
}

#if os(WASI)
/// The URL methods UniformTypeIdentifiers adds (Mlem names its settings files with them).
extension URL {
    /// The URL with a path component added, given the type's filename extension unless the name
    /// already has one of that type; a directory type adds it as a directory.
    public func appendingPathComponent(_ partialName: String, conformingTo contentType: UTType) -> URL {
        if contentType._isDirectoryType { return appendingPathComponent(partialName, isDirectory: true) }
        return appendingPathComponent(partialName).appendingPathExtension(for: contentType)
    }

    public mutating func appendPathComponent(_ partialName: String, conformingTo contentType: UTType) {
        self = appendingPathComponent(partialName, conformingTo: contentType)
    }

    /// The URL with the type's filename extension added, unless it already has one of that type.
    public func appendingPathExtension(for contentType: UTType) -> URL {
        guard let wanted = contentType.preferredFilenameExtension else { return self }
        let current = pathExtension.lowercased()
        if !current.isEmpty, current == wanted || UTType(filenameExtension: current) == contentType { return self }
        return appendingPathExtension(wanted)
    }

    public mutating func appendPathExtension(for contentType: UTType) {
        self = appendingPathExtension(for: contentType)
    }
}
#endif
