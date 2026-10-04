// The inline markdown SwiftUI reads in string literals (`Text("**bold** _italic_ [link](url)")`)
// and `AttributedString(markdown:)` on wasm: strong and emphasis (`**`, `__`, `*`, `_`), code
// spans, strikethrough (`~~`), links, and backslash escapes. Block structure (headings, lists)
// is not interpreted; newlines pass through.

/// One run of parsed inline markdown.
public struct _InlineMarkdownRun: Equatable, Sendable {
    public var text: String
    public var bold = false
    public var italic = false
    public var code = false
    public var strikethrough = false
    public var link: String?

    public init(text: String, bold: Bool = false, italic: Bool = false, code: Bool = false, strikethrough: Bool = false, link: String? = nil) {
        self.text = text
        self.bold = bold
        self.italic = italic
        self.code = code
        self.strikethrough = strikethrough
        self.link = link
    }

    public var isPlain: Bool { !bold && !italic && !code && !strikethrough && link == nil }
}

public enum _InlineMarkdown {
    /// Whether the string holds anything markdown would change.
    public static func hasMarkup(_ string: String) -> Bool {
        string.contains { $0 == "*" || $0 == "_" || $0 == "`" || $0 == "~" || $0 == "[" || $0 == "\\" }
    }

    /// The runs of `string`, adjacent runs with the same style merged; a plain string is one run.
    public static func parse(_ string: String) -> [_InlineMarkdownRun] {
        guard hasMarkup(string) else { return [_InlineMarkdownRun(text: string)] }
        var parser = Parser(Array(string))
        let runs = parser.parse(until: nil)
        return merged(runs)
    }

    private static func merged(_ runs: [_InlineMarkdownRun]) -> [_InlineMarkdownRun] {
        var result: [_InlineMarkdownRun] = []
        for run in runs where !run.text.isEmpty {
            if var last = result.last, last.bold == run.bold, last.italic == run.italic, last.code == run.code, last.strikethrough == run.strikethrough, last.link == run.link {
                last.text += run.text
                result[result.count - 1] = last
            } else {
                result.append(run)
            }
        }
        return result.isEmpty ? [_InlineMarkdownRun(text: "")] : result
    }

    private struct Style {
        var bold = false, italic = false, strikethrough = false
        var link: String?
    }

    private struct Parser {
        let chars: [Character]
        var index = 0
        var style = Style()

        init(_ chars: [Character]) { self.chars = chars }

        private func at(_ offset: Int) -> Character? { index + offset < chars.count ? chars[index + offset] : nil }

        /// Whether the delimiter run of `length` at `index` closes an opened span (a closing run
        /// must follow a non-space) or opens one (must precede a non-space).
        private func isLeftFlanking(_ length: Int) -> Bool {
            guard let next = at(length) else { return false }
            // An underscore inside a word (snake_case) is literal.
            if chars[index] == "_", index > 0, chars[index - 1].isLetter || chars[index - 1].isNumber { return false }
            return !next.isWhitespace
        }
        private func isRightFlanking(_ length: Int = 1) -> Bool {
            guard index > 0 else { return false }
            if chars[index] == "_", let next = at(length), next.isLetter || next.isNumber { return false }
            return !chars[index - 1].isWhitespace
        }

        /// Parses the whole string at the top level.
        mutating func parse(until closing: [Character]?) -> [_InlineMarkdownRun] {
            var runs: [_InlineMarkdownRun] = []
            var text = ""
            func flush() {
                if !text.isEmpty { runs.append(_InlineMarkdownRun(text: text, bold: style.bold, italic: style.italic, strikethrough: style.strikethrough, link: style.link)) }
                text = ""
            }
            while index < chars.count {
                let c = chars[index]
                if c == "\\", let next = at(1), !next.isLetter, !next.isNumber, !next.isWhitespace {
                    text.append(next)
                    index += 2
                    continue
                }
                if c == "`", let end = chars[(index + 1)...].firstIndex(of: "`") {
                    flush()
                    runs.append(_InlineMarkdownRun(text: String(chars[(index + 1)..<end]), code: true))
                    index = end + 1
                    continue
                }
                if c == "[", let link = parseLink() {
                    flush()
                    runs += link
                    continue
                }
                if c == "*" || c == "_" {
                    let length = run(of: c)
                    if isLeftFlanking(length), let span = parseEmphasis(c, length: length) {
                        flush()
                        runs += span
                        continue
                    }
                }
                if c == "~", at(1) == "~", isLeftFlanking(2) {
                    index += 2
                    let saved = style
                    style.strikethrough = true
                    let inner = parseSpan(until: ["~", "~"])
                    style = saved
                    if let inner {
                        flush()
                        runs += inner
                        continue
                    }
                    index -= 2
                }
                text.append(c)
                index += 1
            }
            flush()
            return runs
        }

        private func matches(_ delimiter: [Character]) -> Bool {
            guard index + delimiter.count <= chars.count else { return false }
            return Array(chars[index..<(index + delimiter.count)]) == delimiter
        }

        private func run(of c: Character) -> Int {
            var length = 0
            while at(length) == c { length += 1 }
            return length
        }

        /// `*…*`, `**…**`, `***…***` (and the underscore forms): nil when no closing run follows.
        private mutating func parseEmphasis(_ c: Character, length: Int) -> [_InlineMarkdownRun]? {
            let start = index
            let saved = style
            let count = min(length, 3)
            index += count
            switch count {
            case 1: style.italic = true
            case 2: style.bold = true
            default: style.bold = true; style.italic = true
            }
            let closing = Array(repeating: c, count: count)
            let inner = parseSpan(until: closing)
            style = saved
            guard let inner else {
                index = start
                return nil
            }
            return inner
        }

        /// `parse(until:)` that reports whether the closing run was found.
        private mutating func parseSpan(until closing: [Character]) -> [_InlineMarkdownRun]? {
            let before = index
            var found = false
            var runs: [_InlineMarkdownRun] = []
            var text = ""
            while index < chars.count {
                if matches(closing), isRightFlanking(closing.count) {
                    index += closing.count
                    found = true
                    break
                }
                let c = chars[index]
                if c == "\\", let next = at(1), !next.isLetter, !next.isNumber, !next.isWhitespace {
                    text.append(next); index += 2; continue
                }
                if c == "`", let end = chars[(index + 1)...].firstIndex(of: "`") {
                    if !text.isEmpty { runs.append(_InlineMarkdownRun(text: text, bold: style.bold, italic: style.italic, strikethrough: style.strikethrough, link: style.link)); text = "" }
                    runs.append(_InlineMarkdownRun(text: String(chars[(index + 1)..<end]), bold: style.bold, italic: style.italic, code: true, strikethrough: style.strikethrough, link: style.link))
                    index = end + 1
                    continue
                }
                if c == "[", style.link == nil, let link = parseLink() {
                    if !text.isEmpty { runs.append(_InlineMarkdownRun(text: text, bold: style.bold, italic: style.italic, strikethrough: style.strikethrough, link: style.link)); text = "" }
                    runs += link
                    continue
                }
                if (c == "*" || c == "_"), c != closing[0] || run(of: c) != closing.count {
                    let length = run(of: c)
                    if isLeftFlanking(length), let span = parseEmphasis(c, length: length) {
                        if !text.isEmpty { runs.append(_InlineMarkdownRun(text: text, bold: style.bold, italic: style.italic, strikethrough: style.strikethrough, link: style.link)); text = "" }
                        runs += span
                        continue
                    }
                }
                if c == "~", at(1) == "~", isLeftFlanking(2) {
                    let saved = style
                    style.strikethrough = true
                    let inner = parseSpan(until: ["~", "~"])
                    style = saved
                    if let inner {
                        if !text.isEmpty { runs.append(_InlineMarkdownRun(text: text, bold: style.bold, italic: style.italic, strikethrough: style.strikethrough, link: style.link)); text = "" }
                        runs += inner
                        continue
                    }
                }
                text.append(c)
                index += 1
            }
            guard found else {
                index = before
                return nil
            }
            if !text.isEmpty { runs.append(_InlineMarkdownRun(text: text, bold: style.bold, italic: style.italic, strikethrough: style.strikethrough, link: style.link)) }
            return runs
        }

        /// `[text](url)`: nil when the brackets or parentheses do not close.
        private mutating func parseLink() -> [_InlineMarkdownRun]? {
            let start = index
            guard let close = chars[(index + 1)...].firstIndex(of: "]"), close + 1 < chars.count, chars[close + 1] == "(",
                  let end = chars[(close + 2)...].firstIndex(of: ")") else { return nil }
            var destinationChars = chars[(close + 2)..<end]
            while let first = destinationChars.first, first == " " { destinationChars.removeFirst() }
            while let last = destinationChars.last, last == " " { destinationChars.removeLast() }
            let destination = String(destinationChars)
            index += 1
            let saved = style
            style.link = destination
            let inner = parseSpan(until: ["]"])
            style = saved
            guard inner != nil, index == close + 1 else {
                index = start
                return nil
            }
            index = end + 1
            return inner
        }
    }
}
