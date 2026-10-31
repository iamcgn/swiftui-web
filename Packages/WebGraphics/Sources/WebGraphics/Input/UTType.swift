// A uniform type identifier, shared by SwiftUIWeb's transfer representations and UIKitWeb's
// document picker (uk-system-sheets); the SwiftUI package adds the MIME and extension lookups.

/// A uniform type identifier.
public struct UTType: Hashable, Sendable, CustomStringConvertible {
    public let identifier: String
    public init(_ identifier: String) { self.identifier = identifier }
    /// A type the app declares (its Info.plist's exported types on iOS; here the identifier).
    public init(exportedAs identifier: String, conformingTo parentType: UTType? = nil) { self.identifier = identifier }
    /// A type another app declares, which this one uses.
    public init(importedAs identifier: String, conformingTo parentType: UTType? = nil) { self.identifier = identifier }

    public static let item = UTType("public.item")
    public static let data = UTType("public.data")
    public static let content = UTType("public.content")
    public static let text = UTType("public.text")
    public static let plainText = UTType("public.plain-text")
    public static let utf8PlainText = UTType("public.utf8-plain-text")
    public static let url = UTType("public.url")
    public static let fileURL = UTType("public.file-url")
    public static let json = UTType("public.json")
    public static let image = UTType("public.image")
    public static let png = UTType("public.png")
    public static let jpeg = UTType("public.jpeg")
    public static let pdf = UTType("com.adobe.pdf")
    public static let html = UTType("public.html")
    public static let rtf = UTType("public.rtf")
    public static let commaSeparatedText = UTType("public.comma-separated-values-text")
    public static let folder = UTType("public.folder")
    public static let directory = UTType("public.directory")
    public static let compositeContent = UTType("public.composite-content")
    public static let utf16PlainText = UTType("public.utf16-plain-text")
    public static let delimitedText = UTType("public.delimited-values-text")
    public static let tabSeparatedText = UTType("public.tab-separated-values-text")
    public static let sourceCode = UTType("public.source-code")
    public static let swiftSource = UTType("public.swift-source")
    public static let javaScript = UTType("com.netscape.javascript-source")
    public static let propertyList = UTType("com.apple.property-list")
    public static let yaml = UTType("public.yaml")
    public static let log = UTType("public.log")
    public static let gif = UTType("com.compuserve.gif")
    public static let heic = UTType("public.heic")
    public static let tiff = UTType("public.tiff")
    public static let bmp = UTType("com.microsoft.bmp")
    public static let svg = UTType("public.svg-image")
    public static let webP = UTType("org.webmproject.webp")
    public static let audiovisualContent = UTType("public.audiovisual-content")
    public static let movie = UTType("public.movie")
    public static let video = UTType("public.video")
    public static let mpeg4Movie = UTType("public.mpeg-4")
    public static let quickTimeMovie = UTType("com.apple.quicktime-movie")
    public static let audio = UTType("public.audio")
    public static let mp3 = UTType("public.mp3")
    public static let mpeg4Audio = UTType("public.mpeg-4-audio")
    public static let wav = UTType("com.microsoft.waveform-audio")
    public static let archive = UTType("public.archive")
    public static let zip = UTType("public.zip-archive")
    public static let gzip = UTType("org.gnu.gnu-zip-archive")
    public static let vCard = UTType("public.vcard")
    public static let emailMessage = UTType("public.email-message")
    public static let spreadsheet = UTType("public.spreadsheet")
    public static let presentation = UTType("public.presentation")
    public static let epub = UTType("org.idpf.epub-container")
    public static let font = UTType("public.font")

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
