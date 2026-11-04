// JSON5 read as JSON on wasm (`JSONDecoder.allowsJSON5`, `JSONSerialization`'s
// `.json5Allowed`): a rewrite of the text into strict JSON before the ordinary reader sees it.
// It takes comments, trailing commas, unquoted keys, single-quoted strings, escaped line
// breaks in strings, hexadecimal numbers, a leading `+` or `.`, a trailing `.`, `Infinity` and
// `NaN` (as the strings a non-conforming-float strategy reads). With `assumesTopLevelDictionary`
// the text may leave out the outer braces.
#if os(WASI)

public enum _JSON5 {
    /// Strict JSON for `text`; nil when it isn't JSON5.
    public static func json(_ text: [UInt8], assumesTopLevelDictionary: Bool = false) -> [UInt8]? {
        var reader = Reader(input: text)
        guard let body = reader.rewrite() else { return nil }
        if assumesTopLevelDictionary, body.first != UInt8(ascii: "{") { return Array("{".utf8) + body + Array("}".utf8) }
        return body
    }

    struct Reader {
        let input: [UInt8]
        var i = 0
        var out: [UInt8] = []

        init(input: [UInt8]) { self.input = input }

        mutating func rewrite() -> [UInt8]? {
            while i < input.count {
                let c = input[i]
                switch c {
                case UInt8(ascii: "/"):
                    guard skipComment() else { return nil }
                case UInt8(ascii: "\""), UInt8(ascii: "'"):
                    guard string(quote: c) else { return nil }
                case UInt8(ascii: ","):
                    // A comma before a closing bracket is dropped.
                    var j = i + 1
                    while j < input.count, isSpace(input[j]) || input[j] == UInt8(ascii: "/") {
                        if input[j] == UInt8(ascii: "/") { let saved = i; i = j; guard skipComment() else { return nil }; j = i; i = saved; continue }
                        j += 1
                    }
                    if j < input.count, input[j] == UInt8(ascii: "}") || input[j] == UInt8(ascii: "]") { i += 1 } else { out.append(c); i += 1 }
                default:
                    if isIdentifierStart(c) { word() } else if isNumberStart(c) { guard number() else { return nil } } else { out.append(c); i += 1 }
                }
            }
            return out
        }

        func isSpace(_ c: UInt8) -> Bool { c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D }
        func isIdentifierStart(_ c: UInt8) -> Bool { (c | 0x20) >= 0x61 && (c | 0x20) <= 0x7A || c == UInt8(ascii: "_") || c == UInt8(ascii: "$") }
        func isNumberStart(_ c: UInt8) -> Bool { (0x30...0x39).contains(c) || c == UInt8(ascii: "-") || c == UInt8(ascii: "+") || c == UInt8(ascii: ".") }

        mutating func skipComment() -> Bool {
            guard i + 1 < input.count else { return false }
            if input[i + 1] == UInt8(ascii: "/") {
                while i < input.count, input[i] != 0x0A { i += 1 }
                return true
            }
            guard input[i + 1] == UInt8(ascii: "*") else { return false }
            i += 2
            while i + 1 < input.count, !(input[i] == UInt8(ascii: "*") && input[i + 1] == UInt8(ascii: "/")) { i += 1 }
            guard i + 1 < input.count else { return false }
            i += 2
            return true
        }

        /// A string in either quotes, written in double quotes.
        mutating func string(quote: UInt8) -> Bool {
            out.append(UInt8(ascii: "\""))
            i += 1
            while i < input.count {
                let c = input[i]
                if c == quote { out.append(UInt8(ascii: "\"")); i += 1; return true }
                if c == UInt8(ascii: "\\"), i + 1 < input.count {
                    let next = input[i + 1]
                    switch next {
                    case 0x0A: i += 2                                  // a line continuation
                    case 0x0D: i += (i + 2 < input.count && input[i + 2] == 0x0A) ? 3 : 2
                    case UInt8(ascii: "'"): out.append(next); i += 2
                    case UInt8(ascii: "x"): out += Array("\\u00".utf8); i += 2   // `\x41` is `A`
                    case UInt8(ascii: "v"): out += Array("\\u000b".utf8); i += 2
                    case UInt8(ascii: "0"): out += Array("\\u0000".utf8); i += 2
                    default: out += [c, next]; i += 2
                    }
                    continue
                }
                if c == UInt8(ascii: "\"") { out += Array("\\\"".utf8) } else { out.append(c) }
                i += 1
            }
            return false
        }

        /// An unquoted key, or a literal (`true`, `false`, `null`, `Infinity`, `NaN`).
        mutating func word() {
            var j = i
            while j < input.count, isIdentifierStart(input[j]) || (0x30...0x39).contains(input[j]) { j += 1 }
            let name = String(decoding: input[i..<j], as: UTF8.self)
            i = j
            var k = j
            while k < input.count, isSpace(input[k]) { k += 1 }
            let isKey = k < input.count && input[k] == UInt8(ascii: ":")
            if !isKey, ["true", "false", "null"].contains(name) { out += Array(name.utf8); return }
            out += Array(("\"" + name + "\"").utf8)
        }

        /// A number as JSON writes it (hexadecimal as decimal, no `+`, digits around the point).
        mutating func number() -> Bool {
            var j = i
            var negative = false
            if input[j] == UInt8(ascii: "+") || input[j] == UInt8(ascii: "-") { negative = input[j] == UInt8(ascii: "-"); j += 1 }
            if j < input.count, isIdentifierStart(input[j]) {
                // `-Infinity` and `+NaN`.
                var k = j
                while k < input.count, isIdentifierStart(input[k]) { k += 1 }
                let name = String(decoding: input[j..<k], as: UTF8.self)
                guard name == "Infinity" || name == "NaN" else { return false }
                out += Array(("\"" + (negative && name == "Infinity" ? "-" : "") + name + "\"").utf8)
                i = k
                return true
            }
            if j + 1 < input.count, input[j] == UInt8(ascii: "0"), input[j + 1] | 0x20 == UInt8(ascii: "x") {
                var k = j + 2
                while k < input.count, input[k].isHexDigit { k += 1 }
                guard let value = UInt64(String(decoding: input[(j + 2)..<k], as: UTF8.self), radix: 16) else { return false }
                out += Array(((negative ? "-" : "") + String(value)).utf8)
                i = k
                return true
            }
            var k = j
            while k < input.count, (0x30...0x39).contains(input[k]) || "eE+-.".utf8.contains(input[k]) { k += 1 }
            var digits = String(decoding: input[j..<k], as: UTF8.self)
            if digits.hasPrefix(".") { digits = "0" + digits }
            if digits.hasSuffix(".") { digits += "0" }
            digits = digits.replacingOccurrences(of: ".e", with: ".0e").replacingOccurrences(of: ".E", with: ".0E")
            out += Array(((negative ? "-" : "") + digits).utf8)
            i = k
            return true
        }
    }
}

extension UInt8 {
    fileprivate var isHexDigit: Bool { (0x30...0x39).contains(self) || ((self | 0x20) >= 0x61 && (self | 0x20) <= 0x66) }
}
#endif
