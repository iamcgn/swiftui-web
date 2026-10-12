// A uniform type identifier, shared by SwiftUIWeb's transfer representations and UIKitWeb's
// document picker (uk-system-sheets); the SwiftUI package adds the MIME and extension lookups.

/// A uniform type identifier.
public struct UTType: Hashable, Sendable {
    public let identifier: String
    public init(_ identifier: String) { self.identifier = identifier }
    public init?(exportedAs identifier: String) { self.identifier = identifier }

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

    /// The type for a filename extension, where one is known here.
    public init?(filenameExtension: String) {
        let known: [String: String] = ["png": "public.png", "jpg": "public.jpeg", "jpeg": "public.jpeg", "txt": "public.plain-text", "json": "public.json",
                                       "pdf": "com.adobe.pdf", "html": "public.html", "htm": "public.html", "rtf": "public.rtf", "csv": "public.comma-separated-values-text"]
        guard let identifier = known[filenameExtension.lowercased()] else { return nil }
        self.identifier = identifier
    }
}
