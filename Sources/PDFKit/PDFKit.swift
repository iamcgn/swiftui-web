// PDFKit (Docs/elements/UIKit/Drawing.md, "PDF renderers and PDFKit"): `PDFDocument` and `PDFPage` over a PDF's data, as
// Basic-Car-Maintenance opens the report it wrote with `UIGraphicsPDFRenderer` and shares it
// with a page thumbnail. A file this process wrote draws its pages as they were recorded (the
// renderer keeps the recordings under a marker in the file); another PDF is read for its page
// count, page sizes, version and information, and its pages draw blank, as the web has no PDF
// rasteriser to call from here. Encrypted files open unlocked.
#if os(WASI)
import WebFoundation
#else
import Foundation
#endif
import UIKit

/// The boxes a page's bounds are measured in; every box is the media box here.
public enum PDFDisplayBox: Int, Sendable {
    case mediaBox = 0
    case cropBox = 1
    case bleedBox = 2
    case trimBox = 3
    case artBox = 4
}

/// The keys of a document's information.
public struct PDFDocumentAttribute: RawRepresentable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let titleAttribute = PDFDocumentAttribute(rawValue: "Title")
    public static let authorAttribute = PDFDocumentAttribute(rawValue: "Author")
    public static let subjectAttribute = PDFDocumentAttribute(rawValue: "Subject")
    public static let creatorAttribute = PDFDocumentAttribute(rawValue: "Creator")
    public static let producerAttribute = PDFDocumentAttribute(rawValue: "Producer")
    public static let keywordsAttribute = PDFDocumentAttribute(rawValue: "Keywords")
}

/// A PDF's pages and information.
open class PDFDocument: @unchecked Sendable {
    /// The file the document was opened from.
    open private(set) var documentURL: URL?
    open private(set) var majorVersion = 1
    open private(set) var minorVersion = 4
    /// The information, by `PDFDocumentAttribute` raw value.
    open var documentAttributes: [AnyHashable: Any]?
    open var isEncrypted: Bool { false }
    open var isLocked: Bool { false }
    open var allowsPrinting: Bool { true }
    open var allowsCopying: Bool { true }

    private var pages: [PDFPage] = []
    /// The data the document was opened on, while no page has changed.
    private var original: Data?

    /// An empty document.
    public init() {}

    /// The document in the file at `url`, or nil when it is not a PDF.
    public convenience init?(url: URL) {
        guard let data = try? Data(contentsOf: url) else { return nil }
        self.init(data: data)
        documentURL = url
    }

    /// The document `data` holds, or nil when it is not a PDF.
    public init?(data: Data) {
        let bytes = [UInt8](data)
        guard let version = PDFScan.version(bytes) else { return nil }
        (majorVersion, minorVersion) = version
        original = data
        var attributes: [AnyHashable: Any] = [:]
        for key in ["Title", "Author", "Subject", "Creator", "Producer", "Keywords"] {
            if let value = PDFScan.literal(after: key, in: bytes) { attributes[key] = value }
        }
        documentAttributes = attributes
        if let marker = PDFScan.literal(after: _PDFDrawings.markerKey, in: bytes), let recorded = _PDFDrawings.pages(forMarker: marker) {
            pages = recorded.map { PDFPage(size: $0.size, commands: $0.commands) }
        } else {
            pages = PDFScan.pageSizes(bytes).map { PDFPage(size: $0, commands: []) }
        }
        for page in pages { page.document = self }
    }

    open var pageCount: Int { pages.count }

    open func page(at index: Int) -> PDFPage? { pages.indices.contains(index) ? pages[index] : nil }

    /// The page's index, or `NSNotFound` when it is not in the document.
    open func index(for page: PDFPage) -> Int { pages.firstIndex { $0 === page } ?? NSNotFound }

    open func insert(_ page: PDFPage, at index: Int) {
        pages.insert(page, at: max(0, min(index, pages.count)))
        page.document = self
        original = nil
    }

    open func removePage(at index: Int) {
        guard pages.indices.contains(index) else { return }
        pages.remove(at: index).document = nil
        original = nil
    }

    open func exchangePage(at indexA: Int, withPageAt indexB: Int) {
        guard pages.indices.contains(indexA), pages.indices.contains(indexB) else { return }
        pages.swapAt(indexA, indexB)
        original = nil
    }

    /// Unlocks an encrypted document; every document opens unlocked here.
    open func unlock(withPassword password: String) -> Bool { true }

    /// The text on every page, a page to a paragraph.
    open var string: String? { pages.compactMap { $0.string }.joined(separator: "\n") }

    /// The document as PDF data: the data it was opened on while unchanged, else the pages
    /// written afresh.
    open func dataRepresentation() -> Data? {
        if let original { return original }
        var info: [String: String] = [:]
        for (key, value) in documentAttributes ?? [:] {
            if let key = key as? String, let value = value as? String { info[key] = value }
        }
        return Data(_PDFDrawings.write(pages: pages.map { _PDFPage(size: $0.mediaBox.size, commands: $0.commands) }, info: info))
    }

    /// Writes the document to `url`; false when it cannot be written.
    @discardableResult
    open func write(to url: URL) -> Bool {
        guard let data = dataRepresentation() else { return false }
        do { try data.write(to: url) } catch { return false }
        return true
    }
}

/// A page of a PDF.
open class PDFPage: @unchecked Sendable {
    open internal(set) weak var document: PDFDocument?
    open var rotation = 0
    var mediaBox: CGRect
    let commands: [DisplayCommand]

    /// An empty US Letter page.
    public init() {
        mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        commands = []
    }

    /// A page the image's size showing the image (a drawn image keeps its drawing).
    public init?(image: UIImage) {
        guard image.size.width > 0, image.size.height > 0 else { return nil }
        mediaBox = CGRect(origin: .zero, size: image.size)
        commands = image.drawing?.commands ?? []
    }

    init(size: CGSize, commands: [DisplayCommand]) {
        mediaBox = CGRect(origin: .zero, size: size)
        self.commands = commands
    }

    open func bounds(for box: PDFDisplayBox) -> CGRect { mediaBox }
    open func setBounds(_ bounds: CGRect, for box: PDFDisplayBox) { if box == .mediaBox { mediaBox = bounds } }

    /// The page's number in its document, from 1.
    open var label: String? { document.map { String($0.index(for: self) + 1) } }

    /// The page's text, a drawn line to a line; nil when none was drawn.
    open var string: String? {
        var lines: [String] = []
        for command in commands {
            switch command {
            case .drawText(let text, _, _, _), .drawTextGradient(let text, _, _, _): lines.append(text)
            default: break
            }
        }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    open var numberOfCharacters: Int { string?.count ?? 0 }

    /// The page on white, scaled to fit inside `size` with its proportions kept.
    open func thumbnail(of size: CGSize, for box: PDFDisplayBox) -> UIImage {
        let page = bounds(for: box)
        guard page.width > 0, page.height > 0, size.width > 0, size.height > 0 else {
            return UIImage(drawing: UIImageDrawing(commands: [], size: .zero, scale: 2))
        }
        let factor = min(size.width / page.width, size.height / page.height)
        let fitted = CGSize(width: (page.width * factor).rounded(), height: (page.height * factor).rounded())
        let transform = CGAffineTransform(a: fitted.width / page.width, b: 0, c: 0, d: fitted.height / page.height,
                                          tx: -page.minX * fitted.width / page.width, ty: -page.minY * fitted.height / page.height)
        let white = RGBA(red: 1, green: 1, blue: 1, alpha: 1)
        let drawing: [DisplayCommand] = [.save, .concat(transform), .fillRect(page, white), .clipRect(page)] + commands + [.restore]
        return UIImage(drawing: UIImageDrawing(commands: drawing, size: fitted, scale: 2))
    }
}

// MARK: - Reading another PDF

/// Reads what PDFKit reports of a PDF from its bytes, without decoding its streams.
enum PDFScan {
    /// The version in the `%PDF-1.x` header, or nil when the data is not a PDF.
    static func version(_ bytes: [UInt8]) -> (Int, Int)? {
        guard let start = find(Array("%PDF-".utf8), in: bytes, from: 0), start < 1024 else { return nil }
        var index = start + 5
        var major = 0, minor = 0
        while index < bytes.count, isDigit(bytes[index]) { major = major * 10 + Int(bytes[index] - 48); index += 1 }
        if index < bytes.count, bytes[index] == UInt8(ascii: ".") { index += 1 }
        while index < bytes.count, isDigit(bytes[index]) { minor = minor * 10 + Int(bytes[index] - 48); index += 1 }
        return (max(major, 1), minor)
    }

    /// The size of each page object in file order: its media box, else the first one in the
    /// file (a page tree's, which pages inherit), else US Letter.
    static func pageSizes(_ bytes: [UInt8]) -> [CGSize] {
        let fallback = mediaBox(in: bytes, range: 0..<bytes.count) ?? CGSize(width: 612, height: 792)
        var sizes: [CGSize] = []
        var cursor = 0
        let typeKey = Array("/Type".utf8), pageName = Array("/Page".utf8), endobj = Array("endobj".utf8)
        while let at = find(typeKey, in: bytes, from: cursor) {
            var index = at + typeKey.count
            while index < bytes.count, isSpace(bytes[index]) { index += 1 }
            cursor = index
            guard starts(pageName, in: bytes, at: index) else { continue }
            let after = index + pageName.count
            if after < bytes.count, isNameByte(bytes[after]) { continue }   // `/Pages`
            let objectStart = findBackward(Array("obj".utf8), in: bytes, before: at) ?? 0
            let objectEnd = find(endobj, in: bytes, from: after) ?? bytes.count
            sizes.append(mediaBox(in: bytes, range: objectStart..<objectEnd) ?? fallback)
            cursor = after
        }
        return sizes
    }

    /// The literal string after `/key`, unescaped, or nil.
    static func literal(after key: String, in bytes: [UInt8]) -> String? {
        let name = Array("/\(key)".utf8)
        var cursor = 0
        while let at = find(name, in: bytes, from: cursor) {
            var index = at + name.count
            cursor = index
            if index < bytes.count, isNameByte(bytes[index]) { continue }
            while index < bytes.count, isSpace(bytes[index]) { index += 1 }
            guard index < bytes.count, bytes[index] == UInt8(ascii: "(") else { continue }
            return unescape(bytes, from: index + 1)
        }
        return nil
    }

    private static func mediaBox(in bytes: [UInt8], range: Range<Int>) -> CGSize? {
        let key = Array("/MediaBox".utf8)
        guard let at = find(key, in: bytes, from: range.lowerBound), at < range.upperBound else { return nil }
        var index = at + key.count
        while index < bytes.count, isSpace(bytes[index]) { index += 1 }
        guard index < bytes.count, bytes[index] == UInt8(ascii: "[") else { return nil }
        index += 1
        var numbers: [Double] = []
        while numbers.count < 4, let found = number(bytes, from: index) { numbers.append(found.0); index = found.1 }
        guard numbers.count == 4 else { return nil }
        let width = abs(numbers[2] - numbers[0]), height = abs(numbers[3] - numbers[1])
        return width > 0 && height > 0 ? CGSize(width: width, height: height) : nil
    }

    /// The number at `index` (after any spaces) and the index after it.
    private static func number(_ bytes: [UInt8], from index: Int) -> (Double, Int)? {
        var index = index
        while index < bytes.count, isSpace(bytes[index]) { index += 1 }
        var negative = false
        if index < bytes.count, bytes[index] == UInt8(ascii: "-") || bytes[index] == UInt8(ascii: "+") {
            negative = bytes[index] == UInt8(ascii: "-"); index += 1
        }
        var value = 0.0, digits = 0, scale = 0.0
        while index < bytes.count {
            let byte = bytes[index]
            if isDigit(byte) {
                if scale > 0 { value += Double(byte - 48) * scale; scale /= 10 } else { value = value * 10 + Double(byte - 48) }
                digits += 1
            } else if byte == UInt8(ascii: "."), scale == 0 {
                scale = 0.1
            } else { break }
            index += 1
        }
        return digits > 0 ? (negative ? -value : value, index) : nil
    }

    private static func unescape(_ bytes: [UInt8], from start: Int) -> String {
        var out: [UInt8] = []
        var depth = 0
        var index = start
        while index < bytes.count {
            let byte = bytes[index]
            if byte == UInt8(ascii: "\\"), index + 1 < bytes.count {
                index += 1
                let next = bytes[index]
                switch next {
                case UInt8(ascii: "n"): out.append(10)
                case UInt8(ascii: "r"): out.append(13)
                case UInt8(ascii: "t"): out.append(9)
                case 48...55:
                    var code = 0, count = 0
                    while count < 3, index < bytes.count, (48...55).contains(bytes[index]) { code = code * 8 + Int(bytes[index] - 48); index += 1; count += 1 }
                    out.append(UInt8(code & 0xFF)); continue
                default: out.append(next)
                }
            } else if byte == UInt8(ascii: "(") {
                depth += 1; out.append(byte)
            } else if byte == UInt8(ascii: ")") {
                if depth == 0 { break }
                depth -= 1; out.append(byte)
            } else {
                out.append(byte)
            }
            index += 1
        }
        // A UTF-16 string starts with its byte order mark; anything else reads as WinAnsi.
        if out.count >= 2, out[0] == 0xFE, out[1] == 0xFF {
            var units: [UInt16] = []
            var i = 2
            while i + 1 < out.count { units.append(UInt16(out[i]) << 8 | UInt16(out[i + 1])); i += 2 }
            return String(decoding: units, as: UTF16.self)
        }
        return String(String.UnicodeScalarView(out.map { Unicode.Scalar(winAnsi($0)) ?? "?" }))
    }

    private static func winAnsi(_ byte: UInt8) -> UInt32 {
        switch byte {
        case 0x80: 0x20AC
        case 0x85: 0x2026
        case 0x91: 0x2018
        case 0x92: 0x2019
        case 0x93: 0x201C
        case 0x94: 0x201D
        case 0x95: 0x2022
        case 0x96: 0x2013
        case 0x97: 0x2014
        default: UInt32(byte)
        }
    }

    private static func isDigit(_ byte: UInt8) -> Bool { byte >= 48 && byte <= 57 }
    private static func isSpace(_ byte: UInt8) -> Bool { byte == 32 || byte == 10 || byte == 13 || byte == 9 || byte == 12 || byte == 0 }
    private static func isNameByte(_ byte: UInt8) -> Bool {
        (byte >= 65 && byte <= 90) || (byte >= 97 && byte <= 122) || isDigit(byte)
    }

    private static func starts(_ needle: [UInt8], in bytes: [UInt8], at index: Int) -> Bool {
        guard index + needle.count <= bytes.count else { return false }
        for offset in 0..<needle.count where bytes[index + offset] != needle[offset] { return false }
        return true
    }

    static func find(_ needle: [UInt8], in bytes: [UInt8], from start: Int) -> Int? {
        guard !needle.isEmpty, bytes.count >= needle.count, start <= bytes.count - needle.count else { return nil }
        for index in max(start, 0)...(bytes.count - needle.count) where bytes[index] == needle[0] && starts(needle, in: bytes, at: index) {
            return index
        }
        return nil
    }

    private static func findBackward(_ needle: [UInt8], in bytes: [UInt8], before end: Int) -> Int? {
        var index = min(end, bytes.count) - needle.count
        while index >= 0 {
            if starts(needle, in: bytes, at: index) { return index }
            index -= 1
        }
        return nil
    }
}
