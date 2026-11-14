// Attributed strings read from documents (Docs/elements/UIKit/Drawing.md, "Documents"):
// `NSAttributedString(data:options:documentAttributes:)` for plain text and HTML, as UIKit's
// importer reads them. HTML becomes text with fonts, colours, backgrounds, decorations and
// links: each element's style comes from its tag (bold for `b`, `strong` and headings,
// monospace for `pre` and `code`), the document's `<style>` rules (tag, class and id selectors,
// compound and descendant, applied by specificity) and its own `style` attribute. Sizes are
// CSS pixels at three quarters of a point (the default 16px is Times 12, as UIKit's importer
// gives); blocks end their line, `br` breaks one, list items get a bullet or their number, and
// white space collapses except in `pre`. Highlightr and HighlightSwift turn highlight.js's
// `<span class="hljs-…">` markup into coloured code this way. Not done: RTF and RTFD (they
// throw), tables laid out as tables, images, and writing documents back out.
#if os(WASI)
import WebFoundation
#else
import Foundation
#endif

extension NSAttributedString {
    /// A document format an attributed string is read from.
    public struct DocumentType: Hashable, RawRepresentable, Sendable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public init(_ rawValue: String) { self.rawValue = rawValue }
        public static let plain = DocumentType("NSPlainText")
        public static let rtf = DocumentType("NSRTF")
        public static let rtfd = DocumentType("NSRTFD")
        public static let html = DocumentType("NSHTML")
    }

    /// An option for reading a document.
    public struct DocumentReadingOptionKey: Hashable, RawRepresentable, Sendable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public init(_ rawValue: String) { self.rawValue = rawValue }
        /// The document's format (a `DocumentType`); without it the format is guessed.
        public static let documentType = DocumentReadingOptionKey("DocumentType")
        /// The text encoding (a `String.Encoding` or its raw value); UTF-8 when not given.
        public static let characterEncoding = DocumentReadingOptionKey("CharacterEncoding")
        /// The attributes plain text takes, and the base HTML's styles start from.
        public static let defaultAttributes = DocumentReadingOptionKey("DefaultAttributes")
        public static let sourceTextScaling = DocumentReadingOptionKey("SourceTextScaling")
        public static let targetTextScaling = DocumentReadingOptionKey("TargetTextScaling")
    }

    /// A property of a read document.
    public struct DocumentAttributeKey: Hashable, RawRepresentable, Sendable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public init(_ rawValue: String) { self.rawValue = rawValue }
        public static let documentType = DocumentAttributeKey("DocumentType")
        public static let characterEncoding = DocumentAttributeKey("CharacterEncoding")
        public static let defaultAttributes = DocumentAttributeKey("DefaultAttributes")
        public static let title = DocumentAttributeKey("NSTitleDocumentAttribute")
        public static let paperSize = DocumentAttributeKey("PaperSize")
        public static let viewSize = DocumentAttributeKey("ViewSize")
        public static let readOnly = DocumentAttributeKey("ReadOnly")
    }

    #if canImport(Darwin)
    public typealias _DocumentAttributesOut = AutoreleasingUnsafeMutablePointer<NSDictionary?>?
    #else
    public typealias _DocumentAttributesOut = UnsafeMutablePointer<[NSAttributedString.DocumentAttributeKey: Any]?>?
    #endif

    /// The text of a plain-text or HTML document with its styles; `documentAttributes`, when
    /// given, receives the format and encoding read (and an HTML document's title).
    public convenience init(data: Data, options: [DocumentReadingOptionKey: Any] = [:],
                            documentAttributes dict: _DocumentAttributesOut) throws {
        let encoding = Self.encoding(options[.characterEncoding]) ?? HTMLImport.declaredEncoding(data) ?? .utf8
        guard let text = String(data: data, encoding: encoding) ?? String(data: data, encoding: .isoLatin1) else {
            throw NSError(domain: NSCocoaErrorDomain, code: 259, userInfo: nil)
        }
        let type = (options[.documentType] as? DocumentType) ?? HTMLImport.guessType(text)
        let defaults = options[.defaultAttributes] as? [NSAttributedString.Key: Any] ?? [:]
        var properties: [DocumentAttributeKey: Any] = [.documentType: type, .characterEncoding: encoding.rawValue]
        let built: NSAttributedString
        switch type {
        case .plain:
            var attributes = defaults
            if attributes[.font] == nil { attributes[.font] = HTMLImport.plainFont }
            built = NSAttributedString(string: text, attributes: attributes)
        case .html:
            var importer = HTMLImport(defaults: defaults)
            built = importer.read(text)
            if let title = importer.title { properties[.title] = title }
        default:
            throw NSError(domain: NSCocoaErrorDomain, code: 259, userInfo: nil)
        }
        if let dict {
            #if canImport(Darwin)
            dict.pointee = Dictionary(uniqueKeysWithValues: properties.map { ($0.key.rawValue, $0.value) }) as NSDictionary
            #else
            dict.pointee = properties
            #endif
        }
        self.init(attributedString: built)
    }

    /// The text of the document at `url` (a file the app reads, as `init(data:)` reads data).
    public convenience init(url: URL, options: [DocumentReadingOptionKey: Any] = [:],
                            documentAttributes dict: _DocumentAttributesOut) throws {
        let data = try Data(contentsOf: url)
        try self.init(data: data, options: options, documentAttributes: dict)
    }

    private static func encoding(_ option: Any?) -> String.Encoding? {
        switch option {
        case let encoding as String.Encoding: return encoding
        case let raw as UInt: return String.Encoding(rawValue: raw)
        case let raw as Int: return String.Encoding(rawValue: UInt(max(0, raw)))
        case let number as NSNumber: return String.Encoding(rawValue: number.uintValue)
        default: return nil
        }
    }
}

// MARK: - The HTML reader

struct HTMLImport {
    /// The style text takes inside an element.
    struct Style {
        var family = "Times New Roman"
        var monospace = false
        var size: CGFloat = 12
        var weight = 400
        var italic = false
        var color: UIColor? = .black
        var background: UIColor?
        var underline = false
        var strikethrough = false
        var link: URL?
        var preformatted = false
        var hidden = false
    }

    /// One CSS rule: a selector (compound selectors, right to left) and its declarations.
    struct Rule {
        var selector: [Compound]
        var declarations: [(String, String)]
        var specificity: Int
        var order: Int
    }

    struct Compound {
        var tag: String?
        var id: String?
        var classes: [String] = []
    }

    /// An open element, for selector matching and closing.
    struct Element {
        var tag: String
        var id: String?
        var classes: [String]
        var style: Style
        var isBlock: Bool
        var listCounter: Int?
    }

    static let plainFont = UIFont(resolved: ResolvedFont(family: "Helvetica", size: 12, weight: .regular, italic: false, textStyle: nil, profile: "iOS"), weight: .regular)

    let defaults: [NSAttributedString.Key: Any]
    private(set) var title: String?
    private var rules: [Rule] = []
    private var stack: [Element] = []
    private let output = NSMutableAttributedString(string: "")
    /// The text written so far, for the line and white-space rules.
    private var written = ""
    /// Whether nothing has been written since a `<pre>` opened (its first newline is dropped).
    private var preStart = false
    /// A space between words waiting for the text after it, with the style it was written in.
    private var pendingSpace: Style?

    init(defaults: [NSAttributedString.Key: Any]) {
        self.defaults = defaults
    }

    static let blocks: Set<String> = ["p", "div", "pre", "h1", "h2", "h3", "h4", "h5", "h6", "ul", "ol", "li", "blockquote", "section",
                                      "article", "header", "footer", "nav", "aside", "main", "figure", "figcaption", "table", "tr",
                                      "dl", "dt", "dd", "hr", "address", "body", "html", "form", "fieldset", "details", "summary"]
    static let voids: Set<String> = ["br", "hr", "img", "meta", "link", "input", "area", "base", "col", "embed", "source", "track", "wbr", "param"]

    mutating func read(_ html: String) -> NSAttributedString {
        let characters = Array(html.unicodeScalars)
        var root = Style()
        if let font = defaults[.font] as? UIFont { root.size = font.pointSize; root.family = font.familyName }
        if let color = defaults[.foregroundColor] as? UIColor { root.color = color }
        stack = [Element(tag: "#root", id: nil, classes: [], style: root, isBlock: true, listCounter: nil)]
        var index = 0
        var text = ""
        func flush(_ importer: inout HTMLImport) {
            if !text.isEmpty { importer.write(Self.decodeEntities(text)); text = "" }
        }
        while index < characters.count {
            let scalar = characters[index]
            guard scalar == "<" else { text.unicodeScalars.append(scalar); index += 1; continue }
            // A comment, a declaration, an end tag or a start tag; a lone "<" is text.
            if Self.starts(characters, index, "<!--") {
                flush(&self)
                index = Self.find(characters, index + 4, "-->").map { $0 + 3 } ?? characters.count
                continue
            }
            if Self.starts(characters, index, "<!") || Self.starts(characters, index, "<?") {
                flush(&self)
                index = Self.find(characters, index, ">").map { $0 + 1 } ?? characters.count
                continue
            }
            let next = index + 1 < characters.count ? characters[index + 1] : " "
            let closing = next == "/"
            let nameStart = closing ? index + 2 : index + 1
            guard nameStart < characters.count, characters[nameStart].properties.isAlphabetic else {
                text.unicodeScalars.append(scalar); index += 1; continue
            }
            flush(&self)
            let end = Self.tagEnd(characters, nameStart)
            let tag = String(String.UnicodeScalarView(characters[nameStart..<min(end, characters.count)]))
            index = min(end + 1, characters.count)
            let (name, attributes, selfClosing) = Self.parseTag(tag)
            if closing {
                close(name)
                continue
            }
            if name == "style" || name == "script" || name == "title" || name == "textarea" {
                let stop = Self.find(characters, index, "</\(name)", caseInsensitive: true) ?? characters.count
                let content = String(String.UnicodeScalarView(characters[index..<stop]))
                index = Self.find(characters, stop, ">").map { $0 + 1 } ?? characters.count
                if name == "style" { addStyleSheet(content) }
                if name == "title" { title = Self.decodeEntities(content).trimmingCharacters(in: .whitespacesAndNewlines) }
                continue
            }
            open(name, attributes)
            if selfClosing || Self.voids.contains(name) { close(name, void: true) }
        }
        flush(&self)
        return NSAttributedString(attributedString: output)
    }

    // MARK: Elements

    private mutating func open(_ tag: String, _ attributes: [String: String]) {
        // An element that closes an open sibling implicitly (`<p>`, `<li>`).
        if tag == "p" || tag == "li" || tag == "dt" || tag == "dd", let open = stack.lastIndex(where: { $0.tag == tag }),
           !stack[open...].contains(where: { ["ul", "ol", "div", "dl", "table"].contains($0.tag) && $0.tag != tag }) {
            close(tag)
        }
        let parent = stack[stack.count - 1]
        var style = parent.style
        let isBlock = Self.blocks.contains(tag)
        switch tag {
        case "b", "strong", "th": style.weight = 700
        case "i", "em", "cite", "var", "dfn", "address": style.italic = true
        case "u", "ins": style.underline = true
        case "s", "strike", "del": style.strikethrough = true
        case "code", "kbd", "samp", "tt":
            style.monospace = true
            style.size = 9.75
        case "pre":
            style.monospace = true
            style.size = 9.75
            style.preformatted = true
        case "h1", "h2", "h3", "h4", "h5", "h6":
            style.weight = 700
            let scale: [String: CGFloat] = ["h1": 2, "h2": 1.5, "h3": 1.17, "h4": 1, "h5": 0.83, "h6": 0.67]
            style.size = 12 * (scale[tag] ?? 1)
        case "small": style.size *= 0.83
        case "big": style.size *= 1.2
        case "a":
            if let href = attributes["href"], let url = URL(string: href) {
                style.link = url
                style.underline = true
                style.color = UIColor(red: 0, green: 0, blue: 0.933, alpha: 1)
            }
        case "font":
            if let color = attributes["color"].flatMap(Self.color) { style.color = color }
        case "head":
            style.hidden = true
        default: break
        }
        let id = attributes["id"]
        let classes = attributes["class"].map { $0.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" }).map(String.init) } ?? []
        var element = Element(tag: tag, id: id, classes: classes, style: style, isBlock: isBlock, listCounter: tag == "ol" ? 0 : nil)
        // The document's rules in specificity order, then the element's own style attribute.
        let matched = rules.filter { matches($0.selector, element) }.sorted { ($0.specificity, $0.order) < ($1.specificity, $1.order) }
        for rule in matched { apply(rule.declarations, to: &element.style, parent: parent.style) }
        if let inline = attributes["style"] { apply(Self.declarations(inline), to: &element.style, parent: parent.style) }

        if isBlock { breakLine() }
        stack.append(element)
        if tag == "pre" { preStart = true }
        switch tag {
        case "br":
            pendingSpace = nil
            writeRaw("\n")
        case "hr": break
        case "li":
            if let list = stack.dropLast().last(where: { $0.tag == "ol" || $0.tag == "ul" }),
               let listIndex = stack.lastIndex(where: { $0.tag == list.tag }) {
                if list.tag == "ol" {
                    stack[listIndex].listCounter = (stack[listIndex].listCounter ?? 0) + 1
                    writeRaw("\t\(stack[listIndex].listCounter!).\t")
                } else {
                    writeRaw("\t•\t")
                }
            }
        default: break
        }
    }

    private mutating func close(_ tag: String, void: Bool = false) {
        guard let index = stack.lastIndex(where: { $0.tag == tag }), index > 0 else { return }
        let closed = stack[index...]
        let wasBlock = closed.contains { $0.isBlock } && !(void && tag == "br")
        stack.removeSubrange(index...)
        if wasBlock { breakLine() }
    }

    /// Ends the current line, unless it is empty.
    private mutating func breakLine() {
        pendingSpace = nil
        if !written.isEmpty && !written.hasSuffix("\n") { writeRaw("\n") }
    }

    /// Whether the next text starts a line (a space there is dropped).
    private var atLineStart: Bool { written.isEmpty || written.hasSuffix("\n") || written.hasSuffix("\t") || written.hasSuffix(" ") }

    // MARK: Text

    /// Text as an element's content: white space collapses outside `pre`, and a space is only
    /// written once text follows it on the same line (none at a line's end).
    private mutating func write(_ text: String) {
        guard let style = stack.last?.style, !style.hidden else { return }
        if style.preformatted {
            var text = text
            // A newline straight after `<pre>` is not content.
            if preStart, text.hasPrefix("\n") { text.removeFirst() }
            flushSpace()
            writeRaw(text)
            return
        }
        func isSpace(_ character: Character) -> Bool {
            character == " " || character == "\n" || character == "\t" || character == "\r" || character == "\u{0C}"
        }
        let words = text.split(whereSeparator: isSpace)
        let leading = text.first.map(isSpace) ?? false
        let trailing = text.last.map(isSpace) ?? false
        if words.isEmpty {
            if leading && !atLineStart && pendingSpace == nil { pendingSpace = style }
            return
        }
        if leading && pendingSpace == nil && !atLineStart { pendingSpace = style }
        flushSpace()
        writeRaw(words.joined(separator: " "))
        if trailing { pendingSpace = style }
    }

    /// Writes a space held back from earlier text, in that text's style.
    private mutating func flushSpace() {
        guard let style = pendingSpace else { return }
        pendingSpace = nil
        guard !atLineStart else { return }
        written += " "
        output.append(NSAttributedString(string: " ", attributes: attributes(for: style)))
    }

    private mutating func writeRaw(_ text: String) {
        guard !text.isEmpty, let style = stack.last?.style, !style.hidden else { return }
        written += text
        preStart = false
        output.append(NSAttributedString(string: text, attributes: attributes(for: style)))
    }

    private func attributes(for style: Style) -> [NSAttributedString.Key: Any] {
        var attributes = defaults
        let family = style.monospace ? "Courier" : style.family
        let weight = UIFont.Weight(Self.weightValue(style.weight))
        attributes[.font] = UIFont(resolved: ResolvedFont(family: family, size: style.size, weight: FontWeight(style.weight), italic: style.italic,
                                                          textStyle: nil, profile: "iOS"), weight: weight)
        if let color = style.color { attributes[.foregroundColor] = color }
        if let background = style.background { attributes[.backgroundColor] = background }
        if style.underline { attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue }
        if style.strikethrough { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
        if let link = style.link { attributes[.link] = link }
        return attributes
    }

    private static func weightValue(_ css: Int) -> CGFloat {
        switch css {
        case ..<150: return UIFont.Weight.ultraLight.rawValue
        case ..<250: return UIFont.Weight.thin.rawValue
        case ..<350: return UIFont.Weight.light.rawValue
        case ..<450: return UIFont.Weight.regular.rawValue
        case ..<550: return UIFont.Weight.medium.rawValue
        case ..<650: return UIFont.Weight.semibold.rawValue
        case ..<750: return UIFont.Weight.bold.rawValue
        case ..<850: return UIFont.Weight.heavy.rawValue
        default: return UIFont.Weight.black.rawValue
        }
    }

    // MARK: Style sheets

    private mutating func addStyleSheet(_ css: String) {
        var source = css
        // Comments out, then at-rules with their blocks.
        while let start = source.range(of: "/*") {
            let end = source.range(of: "*/", range: start.upperBound..<source.endIndex)?.upperBound ?? source.endIndex
            source.removeSubrange(start.lowerBound..<end)
        }
        var index = source.startIndex
        while index < source.endIndex {
            guard let open = source[index...].firstIndex(of: "{") else { break }
            let prelude = source[index..<open].trimmingCharacters(in: .whitespacesAndNewlines)
            // The block's end, counting nested braces (an @media block holds rules).
            var depth = 0
            var close = open
            var cursor = open
            while cursor < source.endIndex {
                if source[cursor] == "{" { depth += 1 }
                if source[cursor] == "}" { depth -= 1; if depth == 0 { close = cursor; break } }
                cursor = source.index(after: cursor)
            }
            if cursor >= source.endIndex { close = source.endIndex }
            let body = String(source[source.index(after: open)..<close])
            index = close < source.endIndex ? source.index(after: close) : source.endIndex
            if prelude.hasPrefix("@") { continue }
            let declarations = Self.declarations(body)
            for selector in prelude.split(separator: ",") {
                guard let parsed = Self.parseSelector(selector.trimmingCharacters(in: .whitespacesAndNewlines)) else { continue }
                rules.append(Rule(selector: parsed.compounds, declarations: declarations, specificity: parsed.specificity, order: rules.count))
            }
        }
    }

    /// A selector as compound selectors, the subject last; nil for what is not supported
    /// (pseudo-classes, attribute selectors, sibling combinators).
    static func parseSelector(_ text: String) -> (compounds: [Compound], specificity: Int)? {
        guard !text.isEmpty, !text.contains(":"), !text.contains("["), !text.contains("+"), !text.contains("~") else { return nil }
        var compounds: [Compound] = []
        var specificity = 0
        for part in text.replacingOccurrences(of: ">", with: " ").split(separator: " ") where !part.isEmpty {
            var compound = Compound()
            var current = ""
            var kind: Character = "t"
            func finish() {
                guard !current.isEmpty else { return }
                switch kind {
                case ".": compound.classes.append(current); specificity += 10
                case "#": compound.id = current; specificity += 100
                default:
                    if current != "*" { compound.tag = current.lowercased(); specificity += 1 }
                }
                current = ""
            }
            for character in part {
                if character == "." || character == "#" {
                    finish()
                    kind = character
                } else {
                    current.append(character)
                }
            }
            finish()
            compounds.append(compound)
        }
        return compounds.isEmpty ? nil : (compounds, specificity)
    }

    private func matches(_ selector: [Compound], _ element: Element) -> Bool {
        guard let subject = selector.last, Self.matches(subject, element) else { return false }
        // Each ancestor compound matches some open element, in order outward.
        var level = stack.count - 1
        for compound in selector.dropLast().reversed() {
            while level > 0 && !Self.matches(compound, stack[level]) { level -= 1 }
            guard level > 0 else { return false }
            level -= 1
        }
        return true
    }

    private static func matches(_ compound: Compound, _ element: Element) -> Bool {
        if let tag = compound.tag, tag != element.tag { return false }
        if let id = compound.id, id != element.id { return false }
        return compound.classes.allSatisfy { element.classes.contains($0) }
    }

    static func declarations(_ text: String) -> [(String, String)] {
        text.split(separator: ";").compactMap { declaration in
            guard let colon = declaration.firstIndex(of: ":") else { return nil }
            let name = declaration[..<colon].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            var value = declaration[declaration.index(after: colon)...].trimmingCharacters(in: .whitespacesAndNewlines)
            if let important = value.range(of: "!important", options: .caseInsensitive) { value = value[..<important.lowerBound].trimmingCharacters(in: .whitespaces) }
            return name.isEmpty ? nil : (name, value)
        }
    }

    private func apply(_ declarations: [(String, String)], to style: inout Style, parent: Style) {
        for (name, value) in declarations {
            let lowered = value.lowercased()
            switch name {
            case "color":
                if lowered == "inherit" { style.color = parent.color } else if let color = Self.color(value) { style.color = color }
            case "background-color":
                if lowered == "transparent" { style.background = nil } else if let color = Self.color(value) { style.background = color }
            case "background":
                for token in Self.tokens(value) {
                    if token.lowercased() == "transparent" || token.lowercased() == "none" { style.background = nil; break }
                    if let color = Self.color(token) { style.background = color; break }
                }
            case "font-weight":
                switch lowered {
                case "bold", "bolder": style.weight = 700
                case "normal", "lighter": style.weight = 400
                default: if let number = Int(lowered) { style.weight = number }
                }
            case "font-style":
                style.italic = lowered == "italic" || lowered == "oblique"
            case "font-size":
                if let size = Self.size(lowered, parent: parent.size) { style.size = size }
            case "font-family":
                let families = value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\"'")) }
                if let first = families.first {
                    style.monospace = families.contains { $0.lowercased() == "monospace" } && first.lowercased() == "monospace"
                    if !style.monospace { style.family = first.lowercased() == "serif" ? "Times New Roman" : first.lowercased() == "sans-serif" ? "Helvetica" : first }
                }
            case "text-decoration", "text-decoration-line":
                if lowered.contains("none") { style.underline = false; style.strikethrough = false }
                if lowered.contains("underline") { style.underline = true }
                if lowered.contains("line-through") { style.strikethrough = true }
            case "display":
                if lowered == "none" { style.hidden = true }
            case "white-space":
                style.preformatted = lowered.hasPrefix("pre")
            default: break
            }
        }
    }

    private static func tokens(_ value: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var depth = 0
        for character in value {
            if character == "(" { depth += 1 }
            if character == ")" { depth -= 1 }
            if character == " " && depth == 0 {
                if !current.isEmpty { tokens.append(current) }
                current = ""
            } else {
                current.append(character)
            }
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }

    /// A CSS length in points (pixels at three quarters of a point).
    static func size(_ value: String, parent: CGFloat) -> CGFloat? {
        let keywords: [String: CGFloat] = ["xx-small": 9, "x-small": 10, "small": 13, "medium": 16, "large": 18, "x-large": 24, "xx-large": 32]
        if let pixels = keywords[value] { return pixels * 0.75 }
        if value == "smaller" { return parent / 1.2 }
        if value == "larger" { return parent * 1.2 }
        func number(_ suffix: String) -> CGFloat? {
            guard value.hasSuffix(suffix), let n = Double(value.dropLast(suffix.count).trimmingCharacters(in: .whitespaces)) else { return nil }
            return CGFloat(n)
        }
        if let pixels = number("px") { return pixels * 0.75 }
        if let points = number("pt") { return points }
        if let em = number("rem") { return em * 12 }
        if let em = number("em") { return em * parent }
        if let percent = number("%") { return percent / 100 * parent }
        if let plain = Double(value) { return CGFloat(plain) * 0.75 }
        return nil
    }

    /// A CSS colour: hex, `rgb()` and `rgba()`, or a name.
    static func color(_ value: String) -> UIColor? {
        let value = value.trimmingCharacters(in: .whitespaces).lowercased()
        if value.hasPrefix("#") {
            let hex = Array(value.dropFirst())
            func digit(_ c: Character) -> CGFloat? { c.hexDigitValue.map { CGFloat($0) } }
            var parts: [CGFloat] = []
            switch hex.count {
            case 3, 4:
                for c in hex { guard let d = digit(c) else { return nil }; parts.append((d * 17) / 255) }
            case 6, 8:
                var i = 0
                while i < hex.count {
                    guard let high = digit(hex[i]), let low = digit(hex[i + 1]) else { return nil }
                    parts.append((high * 16 + low) / 255)
                    i += 2
                }
            default: return nil
            }
            return UIColor(red: parts[0], green: parts[1], blue: parts[2], alpha: parts.count > 3 ? parts[3] : 1)
        }
        if value.hasPrefix("rgb"), let open = value.firstIndex(of: "("), let close = value.lastIndex(of: ")") {
            let inside = value[value.index(after: open)..<close].replacingOccurrences(of: "/", with: " ").replacingOccurrences(of: ",", with: " ")
            let numbers = inside.split(separator: " ").map(String.init)
            guard numbers.count >= 3 else { return nil }
            func channel(_ text: String) -> CGFloat? {
                if text.hasSuffix("%"), let n = Double(text.dropLast()) { return CGFloat(n / 100) }
                return Double(text).map { CGFloat($0 / 255) }
            }
            func alpha(_ text: String) -> CGFloat? {
                if text.hasSuffix("%"), let n = Double(text.dropLast()) { return CGFloat(n / 100) }
                return Double(text).map { CGFloat($0) }
            }
            guard let r = channel(numbers[0]), let g = channel(numbers[1]), let b = channel(numbers[2]) else { return nil }
            return UIColor(red: r, green: g, blue: b, alpha: numbers.count > 3 ? alpha(numbers[3]) ?? 1 : 1)
        }
        let named: [String: (CGFloat, CGFloat, CGFloat)] = [
            "black": (0, 0, 0), "white": (255, 255, 255), "red": (255, 0, 0), "green": (0, 128, 0), "blue": (0, 0, 255),
            "yellow": (255, 255, 0), "gray": (128, 128, 128), "grey": (128, 128, 128), "silver": (192, 192, 192),
            "maroon": (128, 0, 0), "purple": (128, 0, 128), "fuchsia": (255, 0, 255), "magenta": (255, 0, 255), "lime": (0, 255, 0),
            "olive": (128, 128, 0), "navy": (0, 0, 128), "teal": (0, 128, 128), "aqua": (0, 255, 255), "cyan": (0, 255, 255),
            "orange": (255, 165, 0), "brown": (165, 42, 42), "pink": (255, 192, 203), "darkgray": (169, 169, 169),
            "lightgray": (211, 211, 211), "darkgreen": (0, 100, 0), "darkblue": (0, 0, 139), "darkred": (139, 0, 0),
            "gold": (255, 215, 0), "indigo": (75, 0, 130), "violet": (238, 130, 238), "crimson": (220, 20, 60),
        ]
        if let (r, g, b) = named[value] { return UIColor(red: r / 255, green: g / 255, blue: b / 255, alpha: 1) }
        return nil
    }

    // MARK: Tags and entities

    static func parseTag(_ text: String) -> (name: String, attributes: [String: String], selfClosing: Bool) {
        var body = Substring(text)
        var selfClosing = false
        if body.hasSuffix("/") { selfClosing = true; body = body.dropLast() }
        let scalars = Array(body.unicodeScalars)
        var index = 0
        func isSpace(_ s: Unicode.Scalar) -> Bool { s == " " || s == "\n" || s == "\t" || s == "\r" || s == "/" }
        var name = ""
        while index < scalars.count, !isSpace(scalars[index]) { name.unicodeScalars.append(scalars[index]); index += 1 }
        var attributes: [String: String] = [:]
        while index < scalars.count {
            while index < scalars.count, isSpace(scalars[index]) { index += 1 }
            var key = ""
            while index < scalars.count, !isSpace(scalars[index]), scalars[index] != "=" { key.unicodeScalars.append(scalars[index]); index += 1 }
            while index < scalars.count, scalars[index] == " " { index += 1 }
            var value = ""
            if index < scalars.count, scalars[index] == "=" {
                index += 1
                while index < scalars.count, scalars[index] == " " { index += 1 }
                if index < scalars.count, scalars[index] == "\"" || scalars[index] == "'" {
                    let quote = scalars[index]
                    index += 1
                    while index < scalars.count, scalars[index] != quote { value.unicodeScalars.append(scalars[index]); index += 1 }
                    index += 1
                } else {
                    while index < scalars.count, !isSpace(scalars[index]) { value.unicodeScalars.append(scalars[index]); index += 1 }
                }
            }
            if !key.isEmpty { attributes[key.lowercased()] = decodeEntities(value) }
        }
        return (name.lowercased(), attributes, selfClosing)
    }

    /// Where the tag starting at `index` ends: its `>`, outside quoted attribute values.
    static func tagEnd(_ characters: [Unicode.Scalar], _ index: Int) -> Int {
        var quote: Unicode.Scalar?
        var i = index
        while i < characters.count {
            let c = characters[i]
            if let open = quote {
                if c == open { quote = nil }
            } else if c == "\"" || c == "'" {
                quote = c
            } else if c == ">" {
                return i
            }
            i += 1
        }
        return characters.count
    }

    static func starts(_ characters: [Unicode.Scalar], _ index: Int, _ prefix: String) -> Bool {
        let scalars = Array(prefix.unicodeScalars)
        guard index + scalars.count <= characters.count else { return false }
        return (0..<scalars.count).allSatisfy { characters[index + $0] == scalars[$0] }
    }

    static func find(_ characters: [Unicode.Scalar], _ from: Int, _ needle: String, caseInsensitive: Bool = false) -> Int? {
        let target = Array((caseInsensitive ? needle.lowercased() : needle).unicodeScalars)
        guard !target.isEmpty, from <= characters.count - target.count else { return nil }
        var i = from
        while i <= characters.count - target.count {
            var hit = true
            for j in 0..<target.count {
                var c = characters[i + j]
                if caseInsensitive, c.properties.isUppercase, let lower = c.properties.lowercaseMapping.unicodeScalars.first { c = lower }
                if c != target[j] { hit = false; break }
            }
            if hit { return i }
            i += 1
        }
        return nil
    }

    static let entities: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": "\u{00A0}", "copy": "©", "reg": "®", "trade": "™",
        "hellip": "…", "mdash": "—", "ndash": "–", "lsquo": "‘", "rsquo": "’", "ldquo": "“", "rdquo": "”", "bull": "•",
        "middot": "·", "euro": "€", "pound": "£", "yen": "¥", "cent": "¢", "laquo": "«", "raquo": "»", "times": "×",
        "divide": "÷", "deg": "°", "plusmn": "±", "sect": "§", "para": "¶", "iexcl": "¡", "iquest": "¿", "larr": "←",
        "rarr": "→", "uarr": "↑", "darr": "↓", "harr": "↔", "le": "≤", "ge": "≥", "ne": "≠", "shy": "\u{00AD}",
        "ensp": "\u{2002}", "emsp": "\u{2003}", "thinsp": "\u{2009}", "zwj": "\u{200D}", "zwnj": "\u{200C}",
    ]

    /// `text` with its character references replaced.
    static func decodeEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var result = ""
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            guard character == "&", let semicolon = text[index...].prefix(12).firstIndex(of: ";") else {
                result.append(character)
                index = text.index(after: index)
                continue
            }
            let name = String(text[text.index(after: index)..<semicolon])
            var replacement: String?
            if name.hasPrefix("#x") || name.hasPrefix("#X") {
                replacement = UInt32(name.dropFirst(2), radix: 16).flatMap(Unicode.Scalar.init).map { String(Character($0)) }
            } else if name.hasPrefix("#") {
                replacement = UInt32(name.dropFirst()).flatMap(Unicode.Scalar.init).map { String(Character($0)) }
            } else {
                replacement = entities[name]
            }
            if let replacement {
                result += replacement
                index = text.index(after: semicolon)
            } else {
                result.append(character)
                index = text.index(after: index)
            }
        }
        return result
    }

    // MARK: Guessing

    static func guessType(_ text: String) -> NSAttributedString.DocumentType {
        let start = text.prefix(512).lowercased()
        if start.hasPrefix("{\\rtf") { return .rtf }
        return start.contains("<html") || start.contains("<!doctype html") || start.contains("<body") || start.contains("<p")
            || start.contains("<div") || start.contains("<span") || start.contains("<pre") || start.contains("<style") ? .html : .plain
    }

    /// The encoding a document names in its `<meta charset>`.
    static func declaredEncoding(_ data: Data) -> String.Encoding? {
        let head = String(decoding: data.prefix(1024), as: UTF8.self).lowercased()
        guard let range = head.range(of: "charset=") else { return nil }
        let name = head[range.upperBound...].trimmingCharacters(in: CharacterSet(charactersIn: "\"' ")).prefix { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        switch name {
        case "utf-8", "utf8": return .utf8
        case "iso-8859-1", "latin1": return .isoLatin1
        case "windows-1252": return .windowsCP1252
        case "us-ascii", "ascii": return .ascii
        case "utf-16": return .utf16
        default: return nil
        }
    }
}
