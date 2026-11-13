// A uniform type identifier, shared by SwiftUIWeb's transfer representations and UIKitWeb's
// document picker (uk-system-sheets); the SwiftUI package adds the MIME and extension lookups.

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
    init(_declared identifier: String) { self.identifier = identifier }
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
        let known: [String: String] = ["png": "public.png", "jpg": "public.jpeg", "jpeg": "public.jpeg", "txt": "public.plain-text", "json": "public.json",
                                       "pdf": "com.adobe.pdf", "html": "public.html", "htm": "public.html", "rtf": "public.rtf", "csv": "public.comma-separated-values-text"]
        guard let identifier = known[filenameExtension.lowercased()] else { return nil }
        self.identifier = identifier
    }
}
