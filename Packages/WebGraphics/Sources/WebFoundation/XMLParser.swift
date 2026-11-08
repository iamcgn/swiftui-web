// Foundation's `XMLParser` on wasm (Docs/coverage.md: FeedKit, which OldOS and other feed
// readers build from source, reads RSS and Atom with it). A streaming parser written here, not
// libxml2: it reports the document, elements and their attributes, text, CDATA, comments and
// processing instructions to the delegate in order, decodes character and entity references
// (the five predefined ones and those an internal DOCTYPE subset declares), maps namespace
// prefixes when asked, and stops at the first well-formedness error with Foundation's codes.
//
// Differences from Foundation: no validation and no external entities or DTDs are read; text is
// delivered in runs between markup (Foundation may split a run at a reference); documents are
// read as UTF-8 or UTF-16 by their byte-order mark, or as Latin-1 when the declaration says so.
#if os(WASI)
import FoundationEssentials

/// The interface an XML parser uses to inform its delegate about the content of the document.
public protocol XMLParserDelegate: AnyObject {
    func parserDidStartDocument(_ parser: XMLParser)
    func parserDidEndDocument(_ parser: XMLParser)
    func parser(_ parser: XMLParser, foundNotationDeclarationWithName name: String, publicID: String?, systemID: String?)
    func parser(_ parser: XMLParser, foundUnparsedEntityDeclarationWithName name: String, publicID: String?, systemID: String?, notationName: String?)
    func parser(_ parser: XMLParser, foundAttributeDeclarationWithName attributeName: String, forElement elementName: String, type: String?, defaultValue: String?)
    func parser(_ parser: XMLParser, foundElementDeclarationWithName elementName: String, model: String)
    func parser(_ parser: XMLParser, foundInternalEntityDeclarationWithName name: String, value: String?)
    func parser(_ parser: XMLParser, foundExternalEntityDeclarationWithName name: String, publicID: String?, systemID: String?)
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String])
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?)
    func parser(_ parser: XMLParser, didStartMappingPrefix prefix: String, toURI namespaceURI: String)
    func parser(_ parser: XMLParser, didEndMappingPrefix prefix: String)
    func parser(_ parser: XMLParser, foundCharacters string: String)
    func parser(_ parser: XMLParser, foundIgnorableWhitespace whitespaceString: String)
    func parser(_ parser: XMLParser, foundProcessingInstructionWithTarget target: String, data: String?)
    func parser(_ parser: XMLParser, foundComment comment: String)
    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data)
    func parser(_ parser: XMLParser, resolveExternalEntityName name: String, systemID: String?) -> Data?
    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error)
    func parser(_ parser: XMLParser, validationErrorOccurred validationError: Error)
}

extension XMLParserDelegate {
    public func parserDidStartDocument(_ parser: XMLParser) {}
    public func parserDidEndDocument(_ parser: XMLParser) {}
    public func parser(_ parser: XMLParser, foundNotationDeclarationWithName name: String, publicID: String?, systemID: String?) {}
    public func parser(_ parser: XMLParser, foundUnparsedEntityDeclarationWithName name: String, publicID: String?, systemID: String?, notationName: String?) {}
    public func parser(_ parser: XMLParser, foundAttributeDeclarationWithName attributeName: String, forElement elementName: String, type: String?, defaultValue: String?) {}
    public func parser(_ parser: XMLParser, foundElementDeclarationWithName elementName: String, model: String) {}
    public func parser(_ parser: XMLParser, foundInternalEntityDeclarationWithName name: String, value: String?) {}
    public func parser(_ parser: XMLParser, foundExternalEntityDeclarationWithName name: String, publicID: String?, systemID: String?) {}
    public func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?,
                       attributes attributeDict: [String: String]) {}
    public func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {}
    public func parser(_ parser: XMLParser, didStartMappingPrefix prefix: String, toURI namespaceURI: String) {}
    public func parser(_ parser: XMLParser, didEndMappingPrefix prefix: String) {}
    public func parser(_ parser: XMLParser, foundCharacters string: String) {}
    public func parser(_ parser: XMLParser, foundIgnorableWhitespace whitespaceString: String) {}
    public func parser(_ parser: XMLParser, foundProcessingInstructionWithTarget target: String, data: String?) {}
    public func parser(_ parser: XMLParser, foundComment comment: String) {}
    public func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {}
    public func parser(_ parser: XMLParser, resolveExternalEntityName name: String, systemID: String?) -> Data? { nil }
    public func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {}
    public func parser(_ parser: XMLParser, validationErrorOccurred validationError: Error) {}
}

/// An event-driven parser of XML documents. (Not an `NSObject` here, as WebFoundation's other
/// parsers aren't, so an app that never names it doesn't link it.)
open class XMLParser: @unchecked Sendable {
    /// The error domain of `parserError`.
    public static let errorDomain = "NSXMLParserErrorDomain"

    /// Why parsing stopped (Foundation's values, which are libxml2's).
    public enum ErrorCode: Int, Sendable {
        case internalError = 1, outOfMemoryError, documentStartError, emptyDocumentError, prematureDocumentEndError,
             invalidHexCharacterRefError, invalidDecimalCharacterRefError, invalidCharacterRefError, invalidCharacterError,
             characterRefAtEOFError, characterRefInPrologError, characterRefInEpilogError, characterRefInDTDError,
             entityRefAtEOFError, entityRefInPrologError, entityRefInEpilogError, entityRefInDTDError,
             parsedEntityRefAtEOFError, parsedEntityRefInPrologError, parsedEntityRefInEpilogError,
             parsedEntityRefInInternalSubsetError, entityReferenceWithoutNameError, entityReferenceMissingSemiError,
             parsedEntityRefNoNameError, parsedEntityRefMissingSemiError, undeclaredEntityError
        case unparsedEntityError = 28, entityIsExternalError, entityIsParameterError, unknownEncodingError,
             encodingNotSupportedError, stringNotStartedError, stringNotClosedError, namespaceDeclarationError,
             entityNotStartedError, entityNotFinishedError, lessThanSymbolInAttributeError, attributeNotStartedError,
             attributeNotFinishedError, attributeHasNoValueError, attributeRedefinedError, literalNotStartedError,
             literalNotFinishedError, commentNotFinishedError, processingInstructionNotStartedError,
             processingInstructionNotFinishedError, notationNotStartedError, notationNotFinishedError,
             attributeListNotStartedError, attributeListNotFinishedError, mixedContentDeclNotStartedError,
             mixedContentDeclNotFinishedError, elementContentDeclNotStartedError, elementContentDeclNotFinishedError,
             xmlDeclNotStartedError, xmlDeclNotFinishedError, conditionalSectionNotStartedError,
             conditionalSectionNotFinishedError, externalSubsetNotFinishedError, doctypeDeclNotFinishedError,
             misplacedCDATAEndStringError, cdataNotFinishedError, misplacedXMLDeclarationError, spaceRequiredError,
             separatorRequiredError, nmtokenRequiredError, nameRequiredError, pcdataRequiredError, uriRequiredError,
             publicIdentifierRequiredError, ltRequiredError, gtRequiredError, ltSlashRequiredError, equalExpectedError,
             tagNameMismatchError, unfinishedTagError, standaloneValueError, invalidEncodingNameError,
             commentContainsDoubleHyphenError, invalidEncodingError, externalStandaloneEntityError,
             invalidConditionalSectionError, entityValueRequiredError, notWellBalancedError, extraContentError,
             invalidCharacterInEntityError, parsedEntityRefInInternalError, entityRefLoopError, entityBoundaryError,
             invalidURIError, uriFragmentError
        case noDTDError = 94
        case delegateAbortedParseError = 512
    }

    /// How the parser treats external entities (none are loaded here).
    public enum ExternalEntityResolvingPolicy: UInt, Sendable {
        case never, noNetwork, sameOriginOnly, always
    }

    private let data: Data
    open weak var delegate: (any XMLParserDelegate)?
    open var shouldProcessNamespaces = false
    open var shouldReportNamespacePrefixes = false
    open var shouldResolveExternalEntities = false
    open var externalEntityResolvingPolicy: ExternalEntityResolvingPolicy = .never
    open var allowedExternalEntityURLs: Set<URL>?
    open private(set) var parserError: (any Error)?
    open private(set) var publicID: String?
    open private(set) var systemID: String?
    open var lineNumber: Int { reader?.line ?? 0 }
    open var columnNumber: Int { reader?.column ?? 0 }

    private var reader: _XMLReader?
    private var aborted = false

    public init(data: Data) {
        self.data = data
    }

    public convenience init?(contentsOf url: URL) {
        guard let data = try? Data(contentsOf: url) else { return nil }
        self.init(data: data)
    }

    public convenience init(stream: InputStream) {
        var bytes = [UInt8]()
        stream.open()
        var chunk = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = chunk.withUnsafeMutableBufferPointer { stream.read($0.baseAddress!, maxLength: $0.count) }
            if count <= 0 { break }
            bytes.append(contentsOf: chunk[0..<count])
        }
        stream.close()
        self.init(data: Data(bytes))
    }

    /// Stops the parse: `parse()` returns false with `delegateAbortedParseError`.
    open func abortParsing() {
        aborted = true
        if parserError == nil { parserError = Self.error(.delegateAbortedParseError) }
    }

    /// Parses the document, reporting to the delegate; false when it is not well formed or
    /// the parse was aborted.
    open func parse() -> Bool {
        aborted = false
        parserError = nil
        let reader = _XMLReader(Self.scalars(of: data))
        self.reader = reader
        do {
            try run(reader)
            return !aborted
        } catch let failure as _XMLFailure {
            if aborted { return false }
            let error = Self.error(failure.code, line: reader.line, column: reader.column)
            parserError = error
            delegate?.parser(self, parseErrorOccurred: error)
            return false
        } catch {
            return false
        }
    }

    private static func error(_ code: ErrorCode, line: Int? = nil, column: Int? = nil) -> NSError {
        var info: [String: Any] = [:]
        if let line { info["NSXMLParserErrorLineNumber"] = line }
        if let column { info["NSXMLParserErrorColumn"] = column }
        return NSError(domain: errorDomain, code: code.rawValue, userInfo: info)
    }

    /// The document's characters: UTF-16 by its byte-order mark, Latin-1 when the declaration
    /// names it, UTF-8 otherwise.
    private static func scalars(of data: Data) -> [Unicode.Scalar] {
        let bytes = [UInt8](data)
        if bytes.count >= 2, (bytes[0] == 0xFE && bytes[1] == 0xFF) || (bytes[0] == 0xFF && bytes[1] == 0xFE) {
            let big = bytes[0] == 0xFE
            var units = [UInt16]()
            units.reserveCapacity(bytes.count / 2)
            var i = 2
            while i + 1 < bytes.count {
                units.append(big ? UInt16(bytes[i]) << 8 | UInt16(bytes[i + 1]) : UInt16(bytes[i + 1]) << 8 | UInt16(bytes[i]))
                i += 2
            }
            return Array(String(decoding: units, as: UTF16.self).unicodeScalars)
        }
        let start = bytes.starts(with: [0xEF, 0xBB, 0xBF]) ? 3 : 0
        if bytes[start...].starts(with: Array("<?xml".utf8)), let end = bytes[start...].firstIndex(of: UInt8(ascii: ">")) {
            let declaration = String(decoding: bytes[start..<end], as: UTF8.self).lowercased()
            if ["iso-8859-1", "latin1", "latin-1", "us-ascii", "windows-1252"].contains(where: { _xmlContains(declaration, "\"\($0)\"") || _xmlContains(declaration, "'\($0)'") }) {
                return bytes[start...].map { Unicode.Scalar($0) }
            }
        }
        return Array(String(decoding: bytes[start...], as: UTF8.self).unicodeScalars)
    }

    // MARK: The document

    private var entities: [String: String] = [:]
    private var namespaces: [[String: String]] = []

    private func run(_ r: _XMLReader) throws {
        entities = ["lt": "<", "gt": ">", "amp": "&", "quot": "\"", "apos": "'"]
        namespaces = [["xml": "http://www.w3.org/XML/1998/namespace"]]
        r.skipWhitespace()
        if r.atEnd { throw _XMLFailure(.emptyDocumentError) }
        delegate?.parserDidStartDocument(self)
        try check()
        if r.starts(with: "<?xml"), let after = r.peek(5), after == " " || after == "\t" || after == "\n" || after == "\r" || after == "?" {
            guard r.skip(past: "?>") else { throw _XMLFailure(.xmlDeclNotFinishedError) }
        }
        // The prolog: comments, processing instructions and the document type.
        while true {
            r.skipWhitespace()
            if r.atEnd { throw _XMLFailure(.emptyDocumentError) }
            if r.starts(with: "<!--") { try comment(r) }
            else if r.starts(with: "<?") { try instruction(r) }
            else if r.starts(with: "<!DOCTYPE") { try doctype(r) }
            else if r.peek() == "<" { break }
            else { throw _XMLFailure(.documentStartError) }
            try check()
        }
        try element(r)
        // The epilog.
        while true {
            r.skipWhitespace()
            if r.atEnd { break }
            if r.starts(with: "<!--") { try comment(r) }
            else if r.starts(with: "<?") { try instruction(r) }
            else { throw _XMLFailure(.extraContentError) }
            try check()
        }
        delegate?.parserDidEndDocument(self)
    }

    private func check() throws { if aborted { throw _XMLFailure(.delegateAbortedParseError) } }

    private func comment(_ r: _XMLReader) throws {
        r.advance(4)
        guard let text = r.take(until: "-->") else { throw _XMLFailure(.commentNotFinishedError) }
        delegate?.parser(self, foundComment: text)
    }

    private func instruction(_ r: _XMLReader) throws {
        r.advance(2)
        let target = r.name()
        guard !target.isEmpty else { throw _XMLFailure(.processingInstructionNotStartedError) }
        if target.lowercased() == "xml" { throw _XMLFailure(.misplacedXMLDeclarationError) }
        r.skipWhitespace()
        guard let body = r.take(until: "?>") else { throw _XMLFailure(.processingInstructionNotFinishedError) }
        delegate?.parser(self, foundProcessingInstructionWithTarget: target, data: body.isEmpty ? nil : body)
    }

    /// The document type: its identifiers, and the entities its internal subset declares.
    private func doctype(_ r: _XMLReader) throws {
        r.advance(9)
        r.skipWhitespace()
        guard !r.name().isEmpty else { throw _XMLFailure(.nameRequiredError) }
        r.skipWhitespace()
        if r.starts(with: "PUBLIC") {
            r.advance(6); r.skipWhitespace()
            publicID = try r.quoted()
            r.skipWhitespace()
            systemID = try r.quoted()
        } else if r.starts(with: "SYSTEM") {
            r.advance(6); r.skipWhitespace()
            systemID = try r.quoted()
        }
        r.skipWhitespace()
        if r.peek() == "[" {
            r.advance(1)
            while true {
                r.skipWhitespace()
                guard let next = r.peek() else { throw _XMLFailure(.doctypeDeclNotFinishedError) }
                if next == "]" { r.advance(1); break }
                if r.starts(with: "<!ENTITY") {
                    r.advance(8); r.skipWhitespace()
                    let parameter = r.peek() == "%"
                    if parameter { r.advance(1); r.skipWhitespace() }
                    let name = r.name()
                    r.skipWhitespace()
                    if r.peek() == "\"" || r.peek() == "'" {
                        let value = try r.quoted()
                        if !parameter {
                            entities[name] = value
                            delegate?.parser(self, foundInternalEntityDeclarationWithName: name, value: value)
                        }
                    }
                    guard r.skip(past: ">") else { throw _XMLFailure(.entityNotFinishedError) }
                } else if r.starts(with: "<!--") {
                    try comment(r)
                } else if r.starts(with: "<?") {
                    try instruction(r)
                } else if r.starts(with: "<!") {
                    // Element, attribute-list and notation declarations: skipped, quoted text included.
                    try r.skipDeclaration()
                } else {
                    r.advance(1)
                }
            }
            r.skipWhitespace()
        }
        guard r.peek() == ">" else { throw _XMLFailure(.doctypeDeclNotFinishedError) }
        r.advance(1)
    }

    /// One element, its content and its end tag; elements nest by a stack, not by recursion.
    private func element(_ r: _XMLReader) throws {
        var open: [(name: String, prefixes: [String], local: String, uri: String?)] = []
        repeat {
            if r.starts(with: "</") {
                r.advance(2)
                let name = r.name()
                r.skipWhitespace()
                guard r.peek() == ">" else { throw _XMLFailure(.gtRequiredError) }
                r.advance(1)
                guard let top = open.popLast(), top.name == name else { throw _XMLFailure(.tagNameMismatchError) }
                end(top)
                try check()
            } else if r.starts(with: "<!--") {
                try comment(r)
                try check()
            } else if r.starts(with: "<![CDATA[") {
                r.advance(9)
                guard let text = r.take(until: "]]>") else { throw _XMLFailure(.cdataNotFinishedError) }
                delegate?.parser(self, foundCDATA: Data(text.utf8))
                try check()
            } else if r.starts(with: "<?") {
                try instruction(r)
                try check()
            } else if r.peek() == "<" {
                r.advance(1)
                let name = r.name()
                guard !name.isEmpty else { throw _XMLFailure(.nameRequiredError) }
                var attributes: [(String, String)] = []
                while true {
                    let spaced = r.skipWhitespace()
                    guard let next = r.peek() else { throw _XMLFailure(.unfinishedTagError) }
                    if next == ">" || next == "/" { break }
                    guard spaced else { throw _XMLFailure(.spaceRequiredError) }
                    let attribute = r.name()
                    guard !attribute.isEmpty else { throw _XMLFailure(.attributeNotStartedError) }
                    r.skipWhitespace()
                    guard r.peek() == "=" else { throw _XMLFailure(.attributeHasNoValueError) }
                    r.advance(1)
                    r.skipWhitespace()
                    guard let quote = r.peek(), quote == "\"" || quote == "'" else { throw _XMLFailure(.attributeNotStartedError) }
                    r.advance(1)
                    guard let raw = r.take(until: String(quote)) else { throw _XMLFailure(.attributeNotFinishedError) }
                    if raw.unicodeScalars.contains("<") { throw _XMLFailure(.lessThanSymbolInAttributeError) }
                    if attributes.contains(where: { $0.0 == attribute }) { throw _XMLFailure(.attributeRedefinedError) }
                    let value = try decode(raw, attribute: true)
                    attributes.append((attribute, value))
                }
                let empty = r.peek() == "/"
                if empty {
                    r.advance(1)
                    guard r.peek() == ">" else { throw _XMLFailure(.gtRequiredError) }
                }
                r.advance(1)
                let opened = start(name, attributes)
                try check()
                if empty { end(opened); try check() } else { open.append(opened) }
            } else if r.atEnd {
                throw _XMLFailure(open.isEmpty ? .prematureDocumentEndError : .unfinishedTagError)
            } else {
                let raw = r.text()
                if _xmlContains(raw, "]]>") { throw _XMLFailure(.misplacedCDATAEndStringError) }
                let text = try decode(raw, attribute: false)
                if !text.isEmpty { delegate?.parser(self, foundCharacters: text) }
                try check()
            }
        } while !open.isEmpty
    }

    /// Reports an element's start, with its namespaces when they are processed.
    private func start(_ name: String, _ attributes: [(String, String)]) -> (name: String, prefixes: [String], local: String, uri: String?) {
        guard shouldProcessNamespaces || shouldReportNamespacePrefixes else {
            delegate?.parser(self, didStartElement: name, namespaceURI: nil, qualifiedName: nil, attributes: Dictionary(attributes, uniquingKeysWith: { a, _ in a }))
            return (name, [], name, nil)
        }
        var scope = namespaces.last ?? [:]
        var prefixes: [String] = []
        var plain: [(String, String)] = []
        for (key, value) in attributes {
            if key == "xmlns" { scope[""] = value; prefixes.append("") }
            else if key.hasPrefix("xmlns:") { let prefix = String(key.dropFirst(6)); scope[prefix] = value; prefixes.append(prefix) }
            else { plain.append((key, value)) }
        }
        namespaces.append(scope)
        if shouldReportNamespacePrefixes {
            for prefix in prefixes { delegate?.parser(self, didStartMappingPrefix: prefix, toURI: scope[prefix] ?? "") }
        }
        guard shouldProcessNamespaces else {
            delegate?.parser(self, didStartElement: name, namespaceURI: nil, qualifiedName: nil, attributes: Dictionary(attributes, uniquingKeysWith: { a, _ in a }))
            return (name, prefixes, name, nil)
        }
        let (prefix, local) = Self.split(name)
        let uri = scope[prefix ?? ""]
        delegate?.parser(self, didStartElement: local, namespaceURI: uri, qualifiedName: name, attributes: Dictionary(plain, uniquingKeysWith: { a, _ in a }))
        return (name, prefixes, local, uri)
    }

    private func end(_ element: (name: String, prefixes: [String], local: String, uri: String?)) {
        if shouldProcessNamespaces {
            delegate?.parser(self, didEndElement: element.local, namespaceURI: element.uri, qualifiedName: element.name)
        } else {
            delegate?.parser(self, didEndElement: element.name, namespaceURI: nil, qualifiedName: nil)
        }
        if shouldProcessNamespaces || shouldReportNamespacePrefixes {
            namespaces.removeLast()
            if shouldReportNamespacePrefixes {
                for prefix in element.prefixes { delegate?.parser(self, didEndMappingPrefix: prefix) }
            }
        }
    }

    private static func split(_ name: String) -> (prefix: String?, local: String) {
        guard let colon = name.firstIndex(of: ":") else { return (nil, name) }
        return (String(name[..<colon]), String(name[name.index(after: colon)...]))
    }

    /// Replaces character and entity references; an attribute's whitespace becomes spaces.
    private func decode(_ raw: String, attribute: Bool, depth: Int = 0) throws -> String {
        guard raw.unicodeScalars.contains(where: { $0 == "&" || (attribute && ($0 == "\n" || $0 == "\t" || $0 == "\r")) }) else { return raw }
        var out = String.UnicodeScalarView()
        let scalars = Array(raw.unicodeScalars)
        var i = 0
        while i < scalars.count {
            let c = scalars[i]
            if c == "&" {
                guard let semi = scalars[i...].firstIndex(of: ";") else { throw _XMLFailure(.entityReferenceMissingSemiError) }
                let name = String(String.UnicodeScalarView(scalars[(i + 1)..<semi]))
                if name.hasPrefix("#") {
                    let hex = name.hasPrefix("#x")
                    let digits = name.dropFirst(hex ? 2 : 1)
                    guard let value = UInt32(digits, radix: hex ? 16 : 10), let scalar = Unicode.Scalar(value), value != 0 else {
                        throw _XMLFailure(hex ? .invalidHexCharacterRefError : .invalidDecimalCharacterRefError)
                    }
                    out.append(scalar)
                } else if name.isEmpty {
                    throw _XMLFailure(.entityReferenceWithoutNameError)
                } else if let value = entities[name] {
                    if depth > 8 { throw _XMLFailure(.entityRefLoopError) }
                    let predefined = ["lt", "gt", "amp", "quot", "apos"].contains(name)
                    out.append(contentsOf: (predefined ? value : try decode(value, attribute: attribute, depth: depth + 1)).unicodeScalars)
                } else if let data = delegate?.parser(self, resolveExternalEntityName: name, systemID: nil) {
                    out.append(contentsOf: String(decoding: data, as: UTF8.self).unicodeScalars)
                } else {
                    throw _XMLFailure(.undeclaredEntityError)
                }
                i = semi + 1
                continue
            }
            if attribute, c == "\r" {
                out.append(" ")
                if i + 1 < scalars.count, scalars[i + 1] == "\n" { i += 1 }
            } else if attribute, c == "\n" || c == "\t" {
                out.append(" ")
            } else {
                out.append(c)
            }
            i += 1
        }
        return String(out)
    }
}

/// Whether the text holds the other (without `String.contains(_:)`, whose string search brings
/// the regex machinery into a wasm build).
private func _xmlContains(_ text: String, _ other: String) -> Bool {
    let a = Array(text.unicodeScalars), b = Array(other.unicodeScalars)
    guard !b.isEmpty, a.count >= b.count else { return b.isEmpty }
    for start in 0...(a.count - b.count) where a[start] == b[0] && Array(a[start..<(start + b.count)]) == b { return true }
    return false
}

/// A well-formedness error, with Foundation's code.
private struct _XMLFailure: Error {
    let code: XMLParser.ErrorCode
    init(_ code: XMLParser.ErrorCode) { self.code = code }
}

/// The parser's position in the document, with its line and column.
private final class _XMLReader {
    private let scalars: [Unicode.Scalar]
    private var index = 0
    private(set) var line = 1
    private(set) var column = 1

    init(_ scalars: [Unicode.Scalar]) { self.scalars = scalars }

    var atEnd: Bool { index >= scalars.count }
    func peek(_ offset: Int = 0) -> Unicode.Scalar? { index + offset < scalars.count ? scalars[index + offset] : nil }

    func advance(_ count: Int) {
        for _ in 0..<count where index < scalars.count {
            if scalars[index] == "\n" { line += 1; column = 1 } else { column += 1 }
            index += 1
        }
    }

    func starts(with text: String) -> Bool {
        var i = index
        for scalar in text.unicodeScalars {
            guard i < scalars.count, scalars[i] == scalar else { return false }
            i += 1
        }
        return true
    }

    @discardableResult func skipWhitespace() -> Bool {
        let before = index
        while let c = peek(), c == " " || c == "\t" || c == "\n" || c == "\r" { advance(1) }
        return index > before
    }

    /// The characters up to `terminator`, which is consumed; nil (at the end) when it never comes.
    func take(until terminator: String) -> String? {
        let start = index
        while !atEnd {
            if starts(with: terminator) {
                let text = String(String.UnicodeScalarView(scalars[start..<index]))
                advance(terminator.unicodeScalars.count)
                return text
            }
            advance(1)
        }
        return nil
    }

    func skip(past terminator: String) -> Bool { take(until: terminator) != nil }

    /// Text up to the next markup.
    func text() -> String {
        let start = index
        while let c = peek(), c != "<" { advance(1) }
        return String(String.UnicodeScalarView(scalars[start..<index]))
    }

    /// An XML name (letters, digits and `_ : . -`, and anything beyond ASCII).
    func name() -> String {
        let start = index
        while let c = peek(), c.properties.isAlphabetic || ("0"..."9").contains(c) || c == "_" || c == ":" || c == "." || c == "-" || c.value > 0x7F {
            advance(1)
        }
        return String(String.UnicodeScalarView(scalars[start..<index]))
    }

    func quoted() throws -> String {
        guard let quote = peek(), quote == "\"" || quote == "'" else { throw _XMLFailure(.literalNotStartedError) }
        advance(1)
        guard let text = take(until: String(quote)) else { throw _XMLFailure(.literalNotFinishedError) }
        return text
    }

    /// A markup declaration in the internal subset, to its closing `>` outside quotes.
    func skipDeclaration() throws {
        while let c = peek() {
            if c == "\"" || c == "'" { _ = try quoted(); continue }
            advance(1)
            if c == ">" { return }
        }
        throw _XMLFailure(.doctypeDeclNotFinishedError)
    }
}
#endif
