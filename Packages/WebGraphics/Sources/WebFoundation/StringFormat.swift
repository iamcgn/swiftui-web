// `String(format:)` for wasm, where FoundationEssentials has none: the printf conversions apps
// and packages use (`%d %i %u %x %X %o %f %e %g %@ %s %c %%`), with the flags (`-+ 0#'`),
// widths, precisions (`*` from the arguments too), length modifiers (`hh h l ll q z t j`: an
// integer is cut to that width, as C reads it) and positional arguments (`%2$@`).
// The arguments are `Any`, because strings aren't `CVarArg` without Objective-C bridging; an
// argument that doesn't fit its conversion prints as its description. Numbers go through the C
// library's `vsnprintf`, as Apple's Foundation formats them, so rounding and padding match.
#if os(WASI)
import WASILibc

extension String {
    public init(format: String, _ arguments: Any...) {
        self = _PrintfFormat.format(format, arguments)
    }

    public init(format: String, arguments: [Any]) {
        self = _PrintfFormat.format(format, arguments)
    }

    /// Formats in `locale`'s conventions; only en_US's exist on wasm, so the locale is unused.
    public init(format: String, locale: Locale?, _ arguments: Any...) {
        self = _PrintfFormat.format(format, arguments)
    }

    public init(format: String, locale: Locale?, arguments: [Any]) {
        self = _PrintfFormat.format(format, arguments)
    }

    public static func localizedStringWithFormat(_ format: String, _ arguments: Any...) -> String {
        _PrintfFormat.format(format, arguments)
    }

    /// The string with `%` conversions filled from `arguments`, as `String(format:)`.
    public func appendingFormat(_ format: String, _ arguments: Any...) -> String {
        self + _PrintfFormat.format(format, arguments)
    }
}

public enum _PrintfFormat {
    struct Spec {
        // `'` (grouping) is read and dropped: without a locale Foundation doesn't group either.
        var leftAlign = false, plus = false, space = false, zero = false, alternate = false
        var width: Int?
        var precision: Int?
        var length = ""
        var conversion: Character = "@"
    }

    public static func format(_ format: String, _ arguments: [Any]) -> String {
        var out = ""
        var next = 0
        let characters = Array(format)
        var i = 0
        func argument(_ position: Int?) -> Any? {
            let index: Int
            if let position { index = position - 1 } else { index = next; next += 1 }
            return arguments.indices.contains(index) ? arguments[index] : nil
        }
        while i < characters.count {
            let c = characters[i]
            i += 1
            guard c == "%", i < characters.count else { out.append(c); continue }
            if characters[i] == "%" { out.append("%"); i += 1; continue }
            var spec = Spec()
            // A positional argument: digits followed by `$`.
            var position: Int?
            var j = i
            while j < characters.count, let d = characters[j].wholeNumberValue, characters[j].isASCII { _ = d; j += 1 }
            if j > i, j < characters.count, characters[j] == "$" {
                position = Int(String(characters[i..<j]))
                i = j + 1
            }
            // Flags.
            flags: while i < characters.count {
                switch characters[i] {
                case "-": spec.leftAlign = true
                case "+": spec.plus = true
                case " ": spec.space = true
                case "0": spec.zero = true
                case "#": spec.alternate = true
                case "'": break
                default: break flags
                }
                i += 1
            }
            // Width.
            if i < characters.count, characters[i] == "*" {
                spec.width = integer(argument(nil)).map { Int($0) }
                if let w = spec.width, w < 0 { spec.leftAlign = true; spec.width = -w }
                i += 1
            } else {
                var digits = ""
                while i < characters.count, characters[i].isASCII, characters[i].isNumber { digits.append(characters[i]); i += 1 }
                if !digits.isEmpty { spec.width = Int(digits) }
            }
            // Precision.
            if i < characters.count, characters[i] == "." {
                i += 1
                if i < characters.count, characters[i] == "*" {
                    spec.precision = integer(argument(nil)).map { max(0, Int($0)) }
                    i += 1
                } else {
                    var digits = ""
                    while i < characters.count, characters[i].isASCII, characters[i].isNumber { digits.append(characters[i]); i += 1 }
                    spec.precision = Int(digits) ?? 0
                }
            }
            // Length modifiers.
            while i < characters.count, "hlqLzjt".contains(characters[i]) { spec.length.append(characters[i]); i += 1 }
            guard i < characters.count else { break }
            spec.conversion = characters[i]
            i += 1
            out += render(spec, argument(position))
        }
        return out
    }

    static func render(_ spec: Spec, _ value: Any?) -> String {
        switch spec.conversion {
        case "d", "i", "D":
            guard let n = integer(value) else { return pad(describe(value), spec) }
            return printf(spec, "lld", signed(n, spec.conversion == "D" ? "l" : spec.length))
        case "u", "U":
            guard let n = integer(value) else { return pad(describe(value), spec) }
            return printf(spec, "llu", unsigned(n, spec.conversion == "U" ? "l" : spec.length))
        case "x", "X", "o", "O":
            guard let n = integer(value) else { return pad(describe(value), spec) }
            return printf(spec, "ll" + (spec.conversion == "O" ? "o" : String(spec.conversion)), unsigned(n, spec.conversion == "O" ? "l" : spec.length))
        case "f", "F", "e", "E", "g", "G", "a", "A":
            guard let d = double(value) else { return pad(describe(value), spec) }
            return printf(spec, String(spec.conversion), d)
        case "c", "C":
            if let ch = value as? Character { return pad(String(ch), spec) }
            if let s = value as? String { return pad(String(s.prefix(1)), spec) }
            if let n = integer(value), let scalar = Unicode.Scalar(UInt32(truncatingIfNeeded: n)) { return pad(String(Character(scalar)), spec) }
            return pad(describe(value), spec)
        case "s", "S", "@":
            var body = describe(value)
            if let p = spec.precision, spec.conversion != "@" { body = String(body.prefix(p)) }
            return pad(body, spec)
        case "p":
            return pad("0x" + String(integer(value).map { UInt64(bitPattern: $0) } ?? 0, radix: 16), spec)
        default:
            return "%" + String(spec.conversion)
        }
    }

    /// A number through the C library's own `printf`, so widths, flags and rounding match the
    /// platform's (`%.2f` of 2.675 is "2.67": the double just below it).
    static func printf(_ spec: Spec, _ conversion: String, _ value: CVarArg) -> String {
        var format = "%"
        if spec.leftAlign { format += "-" }
        if spec.plus { format += "+" }
        if spec.space { format += " " }
        if spec.zero { format += "0" }
        if spec.alternate { format += "#" }
        if let width = spec.width { format += String(width) }
        if let precision = spec.precision { format += "." + String(precision) }
        format += conversion
        var buffer = [CChar](repeating: 0, count: 128)
        let needed = withVaList([value]) { vsnprintf(&buffer, buffer.count, format, $0) }
        guard needed >= 0 else { return "" }
        if Int(needed) >= buffer.count {
            buffer = [CChar](repeating: 0, count: Int(needed) + 1)
            _ = withVaList([value]) { vsnprintf(&buffer, buffer.count, format, $0) }
        }
        return String(decoding: buffer.prefix(Int(needed)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    /// An integer cut to the width its length modifier names, as C reads it: an `int` with none
    /// (`%d` of 5_000_000_000 is 705032704, as on Apple platforms), `short` for `h`, `char` for
    /// `hh`, 64 bits for `l`, `ll`, `q`, `z`, `j` and `t`. `D`, `U` and `O` are always long.
    static func signed(_ n: Int64, _ length: String) -> Int64 {
        switch length {
        case "": return Int64(Int32(truncatingIfNeeded: n))
        case "h": return Int64(Int16(truncatingIfNeeded: n))
        case "hh": return Int64(Int8(truncatingIfNeeded: n))
        default: return n
        }
    }

    static func unsigned(_ n: Int64, _ length: String) -> UInt64 {
        switch length {
        case "": return UInt64(UInt32(truncatingIfNeeded: n))
        case "h": return UInt64(UInt16(truncatingIfNeeded: n))
        case "hh": return UInt64(UInt8(truncatingIfNeeded: n))
        default: return UInt64(bitPattern: n)
        }
    }

    /// Strings, characters and descriptions padded to the width.
    static func pad(_ text: String, _ spec: Spec) -> String {
        guard let width = spec.width, text.count < width else { return text }
        let fill = String(repeating: " ", count: width - text.count)
        return spec.leftAlign ? text + fill : fill + text
    }

    /// `nil` prints as "(null)", optionals as their wrapped value, everything else as its
    /// description.
    static func describe(_ value: Any?) -> String {
        guard let value else { return "(null)" }
        if let optional = value as? _OptionalForFormat { return optional._formatDescription }
        if let string = value as? String { return string }
        return String(describing: value)
    }

    static func integer(_ value: Any?) -> Int64? {
        switch value {
        case let v as Int: return Int64(v)
        case let v as Int8: return Int64(v)
        case let v as Int16: return Int64(v)
        case let v as Int32: return Int64(v)
        case let v as Int64: return v
        case let v as UInt: return Int64(truncatingIfNeeded: v)
        case let v as UInt8: return Int64(v)
        case let v as UInt16: return Int64(v)
        case let v as UInt32: return Int64(v)
        case let v as UInt64: return Int64(truncatingIfNeeded: v)
        case let v as Bool: return v ? 1 : 0
        case let v as Character: return v.unicodeScalars.first.map { Int64($0.value) }
        case let v as NSNumber: return v.int64Value
        case let v as any BinaryFloatingPoint:
            let d = Double(v)
            return d.isFinite && abs(d) < 9.2e18 ? Int64(d) : nil
        default: return nil
        }
    }

    static func double(_ value: Any?) -> Double? {
        switch value {
        case let v as Double: return v
        case let v as Float: return Double(v)
        case let v as any BinaryFloatingPoint: return Double(v)
        case let v as NSNumber: return v.doubleValue
        case let v as any BinaryInteger: return Double(Int64(truncatingIfNeeded: v))
        default: return nil
        }
    }
}

/// Lets `%@` print an optional argument's wrapped value, or "(null)" for nil.
protocol _OptionalForFormat { var _formatDescription: String { get } }

extension Optional: _OptionalForFormat {
    var _formatDescription: String {
        switch self {
        case .some(let wrapped): return _PrintfFormat.describe(wrapped)
        case .none: return "(null)"
        }
    }
}
#endif
