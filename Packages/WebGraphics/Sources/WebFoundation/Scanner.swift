// `Scanner` on wasm, where FoundationEssentials has none (Docs/coverage.md: 4 apps, most of
// them reading a hex colour with `scanHexInt64`). Both forms: the Swift one that returns
// optionals (`scanInt()`, `scanString(_:)`, `currentIndex`) and the older one that writes
// through a pointer and answers a Bool (`scanHexInt64(&value)`, `scanLocation`; deprecated on
// iOS 13, kept undeprecated here so an app's build shows no extra warnings). Each scan
// first skips `charactersToBeSkipped` (whitespace and newlines unless set), and a failed scan
// leaves the position where it was, as Foundation's do.
#if os(WASI)

/// A string parser that scans for substrings or characters in a character set, and for
/// numeric values from decimal, hexadecimal, and floating-point representations.
open class Scanner: @unchecked Sendable {
    /// How a scanned number is written.
    public enum NumberRepresentation: Sendable {
        case decimal
        case hexadecimal
    }

    /// The string the scanner reads.
    public let string: String
    /// The characters skipped before each scan.
    open var charactersToBeSkipped: CharacterSet? = .whitespacesAndNewlines
    /// Whether string scans tell case apart.
    open var caseSensitive = false
    open var locale: Any?
    /// Where the next scan starts.
    open var currentIndex: String.Index

    public init(string: String) {
        self.string = string
        currentIndex = string.startIndex
    }

    /// Whether only skipped characters remain.
    open var isAtEnd: Bool { skipped(from: currentIndex) == string.endIndex }

    /// The position as a count of UTF-16 units (the older API).
    open var scanLocation: Int {
        get { string.utf16.distance(from: string.startIndex, to: currentIndex) }
        set { currentIndex = string.utf16.index(string.startIndex, offsetBy: min(max(0, newValue), string.utf16.count)) }
    }

    // MARK: Strings and characters

    /// Scans `searchString`, returning it as the string spells it.
    open func scanString(_ searchString: String) -> String? {
        let start = skipped(from: currentIndex)
        var index = start
        for wanted in searchString.unicodeScalars {
            guard index < string.endIndex else { return nil }
            guard same(string.unicodeScalars[index], wanted) else { return nil }
            index = string.unicodeScalars.index(after: index)
        }
        currentIndex = index
        return String(string[start..<index])
    }

    /// Scans until `substring` (or the end), returning what came before it; nil when nothing did.
    open func scanUpToString(_ substring: String) -> String? {
        let start = skipped(from: currentIndex)
        guard start < string.endIndex else { return nil }
        let scalars = string.unicodeScalars
        let wanted = Array(substring.unicodeScalars)
        var end = start
        search: while end < string.endIndex {
            var probe = end
            for scalar in wanted {
                guard probe < string.endIndex, same(scalars[probe], scalar) else { end = scalars.index(after: end); continue search }
                probe = scalars.index(after: probe)
            }
            break
        }
        guard end > start else { return nil }
        currentIndex = end
        return String(string[start..<end])
    }

    /// Scans the longest run of characters in `set`.
    open func scanCharacters(from set: CharacterSet) -> String? {
        scanRun(while: { set.contains($0) })
    }

    /// Scans the longest run of characters outside `set`.
    open func scanUpToCharacters(from set: CharacterSet) -> String? {
        scanRun(while: { !set.contains($0) })
    }

    /// Scans one character.
    open func scanCharacter() -> Character? {
        let start = skipped(from: currentIndex)
        guard start < string.endIndex else { return nil }
        currentIndex = string.index(after: start)
        return string[start]
    }

    // MARK: Numbers

    open func scanInt(representation: NumberRepresentation = .decimal) -> Int? {
        scanInt64(representation: representation).flatMap { Int(exactly: $0) }
    }

    open func scanInt32(representation: NumberRepresentation = .decimal) -> Int32? {
        scanInt64(representation: representation).flatMap { Int32(exactly: $0) }
    }

    open func scanInt64(representation: NumberRepresentation = .decimal) -> Int64? {
        let start = skipped(from: currentIndex)
        var index = start
        var negative = false
        if index < string.endIndex, string.unicodeScalars[index] == "-" || string.unicodeScalars[index] == "+" {
            negative = string.unicodeScalars[index] == "-"
            index = string.unicodeScalars.index(after: index)
        }
        guard let (magnitude, end) = digits(from: index, hexadecimal: representation == .hexadecimal) else { return nil }
        currentIndex = end
        if negative { return magnitude > UInt64(Int64.max) + 1 ? .min : Int64(truncatingIfNeeded: 0 &- magnitude) }
        return magnitude > UInt64(Int64.max) ? .max : Int64(magnitude)
    }

    open func scanUInt64(representation: NumberRepresentation = .decimal) -> UInt64? {
        let start = skipped(from: currentIndex)
        var index = start
        if index < string.endIndex, string.unicodeScalars[index] == "+" { index = string.unicodeScalars.index(after: index) }
        guard let (value, end) = digits(from: index, hexadecimal: representation == .hexadecimal) else { return nil }
        currentIndex = end
        return value
    }

    open func scanDouble(representation: NumberRepresentation = .decimal) -> Double? {
        if representation == .hexadecimal { return scanInt64(representation: .hexadecimal).map(Double.init) }
        let start = skipped(from: currentIndex)
        let scalars = string.unicodeScalars
        var index = start
        func advance(while accept: (Unicode.Scalar) -> Bool) -> Int {
            var count = 0
            while index < string.endIndex, accept(scalars[index]) { index = scalars.index(after: index); count += 1 }
            return count
        }
        func isDigit(_ scalar: Unicode.Scalar) -> Bool { scalar.value >= 0x30 && scalar.value <= 0x39 }
        if index < string.endIndex, scalars[index] == "+" || scalars[index] == "-" { index = scalars.index(after: index) }
        var digitCount = advance(while: isDigit)
        if index < string.endIndex, scalars[index] == "." {
            index = scalars.index(after: index)
            digitCount += advance(while: isDigit)
        }
        guard digitCount > 0 else { return nil }
        let mantissaEnd = index
        if index < string.endIndex, scalars[index] == "e" || scalars[index] == "E" {
            index = scalars.index(after: index)
            if index < string.endIndex, scalars[index] == "+" || scalars[index] == "-" { index = scalars.index(after: index) }
            if advance(while: isDigit) == 0 { index = mantissaEnd }
        }
        guard let value = Double(String(string[start..<index])) else { return nil }
        currentIndex = index
        return value
    }

    open func scanFloat(representation: NumberRepresentation = .decimal) -> Float? {
        scanDouble(representation: representation).map(Float.init)
    }

    // MARK: The older, pointer-writing forms

    open func scanInt(_ result: UnsafeMutablePointer<Int>?) -> Bool { write(scanInt(), to: result) }
    open func scanInt32(_ result: UnsafeMutablePointer<Int32>?) -> Bool { write(scanInt32(), to: result) }
    open func scanInt64(_ result: UnsafeMutablePointer<Int64>?) -> Bool { write(scanInt64(), to: result) }
    open func scanUnsignedLongLong(_ result: UnsafeMutablePointer<UInt64>?) -> Bool { write(scanUInt64(), to: result) }
    open func scanDouble(_ result: UnsafeMutablePointer<Double>?) -> Bool { write(scanDouble(), to: result) }
    open func scanFloat(_ result: UnsafeMutablePointer<Float>?) -> Bool { write(scanFloat(), to: result) }
    open func scanHexInt64(_ result: UnsafeMutablePointer<UInt64>?) -> Bool { write(scanUInt64(representation: .hexadecimal), to: result) }
    open func scanHexInt32(_ result: UnsafeMutablePointer<UInt32>?) -> Bool {
        write(scanUInt64(representation: .hexadecimal).map { UInt32(truncatingIfNeeded: $0) }, to: result)
    }
    open func scanHexDouble(_ result: UnsafeMutablePointer<Double>?) -> Bool { write(scanDouble(representation: .hexadecimal), to: result) }

    // MARK: Positions

    /// The first index at or after `index` outside `charactersToBeSkipped`.
    private func skipped(from index: String.Index) -> String.Index {
        guard let skip = charactersToBeSkipped else { return index }
        var index = index
        while index < string.endIndex, skip.contains(string.unicodeScalars[index]) { index = string.unicodeScalars.index(after: index) }
        return index
    }

    /// Whether two scalars match under `caseSensitive`.
    private func same(_ a: Unicode.Scalar, _ b: Unicode.Scalar) -> Bool {
        caseSensitive ? a == b : (a == b || String(a).lowercased() == String(b).lowercased())
    }

    private func scanRun(while accept: (Unicode.Scalar) -> Bool) -> String? {
        let start = skipped(from: currentIndex)
        var index = start
        while index < string.endIndex, accept(string.unicodeScalars[index]) { index = string.unicodeScalars.index(after: index) }
        guard index > start else { return nil }
        currentIndex = index
        return String(string[start..<index])
    }

    /// The digits from `index` (after an optional `0x` for hexadecimal), saturating at the
    /// largest value, and the index after them; nil when there are none.
    private func digits(from index: String.Index, hexadecimal: Bool) -> (UInt64, String.Index)? {
        let scalars = string.unicodeScalars
        var index = index
        if hexadecimal, index < string.endIndex, scalars[index] == "0" {
            let next = scalars.index(after: index)
            if next < string.endIndex, scalars[next] == "x" || scalars[next] == "X" {
                let afterPrefix = scalars.index(after: next)
                if afterPrefix < string.endIndex, scalars[afterPrefix].properties.isASCIIHexDigit { index = afterPrefix }
            }
        }
        let radix: UInt64 = hexadecimal ? 16 : 10
        var value: UInt64 = 0
        var overflow = false
        let start = index
        while index < string.endIndex, let digit = Self.digitValue(scalars[index], hexadecimal: hexadecimal) {
            let (multiplied, o1) = value.multipliedReportingOverflow(by: radix)
            let (added, o2) = multiplied.addingReportingOverflow(digit)
            if o1 || o2 { overflow = true } else { value = added }
            index = scalars.index(after: index)
        }
        guard index > start else { return nil }
        return (overflow ? .max : value, index)
    }

    private static func digitValue(_ scalar: Unicode.Scalar, hexadecimal: Bool) -> UInt64? {
        switch scalar.value {
        case 0x30...0x39: return UInt64(scalar.value - 0x30)
        case 0x41...0x46 where hexadecimal: return UInt64(scalar.value - 0x41 + 10)
        case 0x61...0x66 where hexadecimal: return UInt64(scalar.value - 0x61 + 10)
        default: return nil
        }
    }

    private func write<T>(_ value: T?, to pointer: UnsafeMutablePointer<T>?) -> Bool {
        guard let value else { return false }
        pointer?.pointee = value
        return true
    }
}
#endif
