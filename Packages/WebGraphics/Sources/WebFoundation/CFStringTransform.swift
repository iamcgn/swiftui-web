// Core Foundation's `CFStringTransform` on wasm, for the width transform: SwiftyChrono (Clendar's
// date parser) folds Japanese text's full-width digits and letters to ASCII with
// `CFStringTransform(str, nil, kCFStringTransformFullwidthHalfwidth, false)` before it parses.
// A `CFMutableString` is the `NSMutableString` an app passes `as CFMutableString` (an identity
// coercion here, as the other CF names in CoreFoundation.swift are). Only the width transform is
// carried; any other transform answers false and leaves the string as it was, as Core Foundation
// does for a transform it doesn't know. Tests/FrameworkTests/CoreFoundationTests.swift runs the
// same cases against Core Foundation on macOS.
#if os(WASI)

public typealias CFMutableString = NSMutableString

/// Full-width forms to half-width ones (reversed, half-width to full-width): ASCII, the
/// ideographic space, katakana and their voicing marks, and the full-width signs.
public let kCFStringTransformFullwidthHalfwidth: CFString = "FullwidthHalfwidth"

/// Transforms the characters of `string` in `range` (UTF-16 units; nil for all of it) and, when
/// `range` is given, sets its length to the transformed characters' length. Answers whether the
/// transform is one this knows.
@discardableResult
public func CFStringTransform(_ string: CFMutableString!, _ range: UnsafeMutablePointer<CFRange>!,
                              _ transform: CFString!, _ reverse: Bool) -> Bool {
    guard let string, transform == kCFStringTransformFullwidthHalfwidth else { return false }
    let units = Array(string.string.utf16)
    let span = range.map { $0.pointee.location..<($0.pointee.location + $0.pointee.length) } ?? 0..<units.count
    guard span.lowerBound >= 0, span.upperBound <= units.count else { return false }
    let input = String(decoding: units[span], as: UTF16.self)
    let output = reverse ? _WidthFolding.toFullwidth(input) : _WidthFolding.toHalfwidth(input)
    var result = units
    result.replaceSubrange(span, with: output.utf16)
    string.string = String(decoding: result, as: UTF16.self)
    range?.pointee.length = output.utf16.count
    return true
}

/// The width forms, one scalar to one or two (a voiced katakana is a half-width kana and a mark).
enum _WidthFolding {
    /// Full-width katakana and marks, and the half-width forms they fold to, in the half-width
    /// block's order (U+FF61 to U+FF9F).
    private static let kana: [(full: UInt32, half: UInt32)] = {
        let fulls: [UInt32] = [
            0x3002, 0x300C, 0x300D, 0x3001, 0x30FB,                         // ｡ ｢ ｣ ､ ･
            0x30F2, 0x30A1, 0x30A3, 0x30A5, 0x30A7, 0x30A9,                 // ｦ ｧ ｨ ｩ ｪ ｫ
            0x30E3, 0x30E5, 0x30E7, 0x30C3, 0x30FC,                         // ｬ ｭ ｮ ｯ ｰ
            0x30A2, 0x30A4, 0x30A6, 0x30A8, 0x30AA,                         // ｱ ｲ ｳ ｴ ｵ
            0x30AB, 0x30AD, 0x30AF, 0x30B1, 0x30B3,                         // ｶ ｷ ｸ ｹ ｺ
            0x30B5, 0x30B7, 0x30B9, 0x30BB, 0x30BD,                         // ｻ ｼ ｽ ｾ ｿ
            0x30BF, 0x30C1, 0x30C4, 0x30C6, 0x30C8,                         // ﾀ ﾁ ﾂ ﾃ ﾄ
            0x30CA, 0x30CB, 0x30CC, 0x30CD, 0x30CE,                         // ﾅ ﾆ ﾇ ﾈ ﾉ
            0x30CF, 0x30D2, 0x30D5, 0x30D8, 0x30DB,                         // ﾊ ﾋ ﾌ ﾍ ﾎ
            0x30DE, 0x30DF, 0x30E0, 0x30E1, 0x30E2,                         // ﾏ ﾐ ﾑ ﾒ ﾓ
            0x30E4, 0x30E6, 0x30E8,                                         // ﾔ ﾕ ﾖ
            0x30E9, 0x30EA, 0x30EB, 0x30EC, 0x30ED,                         // ﾗ ﾘ ﾙ ﾚ ﾛ
            0x30EF, 0x30F3, 0x309B, 0x309C,                                 // ﾜ ﾝ ﾞ ﾟ
        ]
        return fulls.enumerated().map { ($0.element, 0xFF61 + UInt32($0.offset)) }
    }()

    /// The full-width signs and arrows and their half-width forms.
    private static let signs: [(full: UInt32, half: UInt32)] = [
        (0xFFE0, 0x00A2), (0xFFE1, 0x00A3), (0xFFE2, 0x00AC), (0xFFE3, 0x00AF),
        (0xFFE4, 0x00A6), (0xFFE5, 0x00A5), (0xFFE6, 0x20A9),
        (0xFF5F, 0x2985), (0xFF60, 0x2986),
        (0x2502, 0xFFE8), (0x2190, 0xFFE9), (0x2191, 0xFFEA), (0x2192, 0xFFEB),
        (0x2193, 0xFFEC), (0x25A0, 0xFFED), (0x25CB, 0xFFEE),
    ]

    private static let toHalf: [UInt32: UInt32] = Dictionary(uniqueKeysWithValues: (kana + signs).map { ($0.full, $0.half) })
    private static let toFull: [UInt32: UInt32] = Dictionary(uniqueKeysWithValues: (kana + signs).map { ($0.half, $0.full) })

    private static let voicedMark: UInt32 = 0xFF9E      // ﾞ
    private static let semiVoicedMark: UInt32 = 0xFF9F  // ﾟ

    /// A voiced or semi-voiced katakana, as its unvoiced kana and the half-width mark.
    private static let voiced: [UInt32: (base: UInt32, mark: UInt32)] = {
        var table: [UInt32: (base: UInt32, mark: UInt32)] = [:]
        // ガ to ド: each voiced kana follows its unvoiced one (ッ, U+30C3, sits between ヂ and ツ).
        for base: UInt32 in [0x30AB, 0x30AD, 0x30AF, 0x30B1, 0x30B3, 0x30B5, 0x30B7, 0x30B9, 0x30BB,
                             0x30BD, 0x30BF, 0x30C1, 0x30C4, 0x30C6, 0x30C8] {
            table[base + 1] = (base, voicedMark)
        }
        // バ to ポ: each of ハ ヒ フ ヘ ホ is followed by its voiced and semi-voiced kana.
        for base: UInt32 in [0x30CF, 0x30D2, 0x30D5, 0x30D8, 0x30DB] {
            table[base + 1] = (base, voicedMark)
            table[base + 2] = (base, semiVoicedMark)
        }
        table[0x30F4] = (0x30A6, voicedMark)  // ヴ
        table[0x30F7] = (0x30EF, voicedMark)  // ヷ
        table[0x30FA] = (0x30F2, voicedMark)  // ヺ
        return table
    }()

    /// The voiced kana a full-width kana and a half-width mark make, keyed by kana then mark.
    private static let combined: [UInt32: [UInt32: UInt32]] = {
        var table: [UInt32: [UInt32: UInt32]] = [:]
        for (voicedKana, parts) in voiced { table[parts.base, default: [:]][parts.mark] = voicedKana }
        return table
    }()

    static func toHalfwidth(_ text: String) -> String {
        var out = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            let value = scalar.value
            if (0xFF01...0xFF5E).contains(value) {
                out.append(Unicode.Scalar(value - 0xFEE0)!)
            } else if value == 0x3000 {
                out.append(" ")
            } else if let parts = voiced[value] {
                out.append(Unicode.Scalar(toHalf[parts.base]!)!)
                out.append(Unicode.Scalar(parts.mark)!)
            } else if value == 0x3099 || value == 0x309A {
                // The combining voicing marks fold as the spacing ones do.
                out.append(Unicode.Scalar(value == 0x3099 ? voicedMark : semiVoicedMark)!)
            } else if let half = toHalf[value] {
                out.append(Unicode.Scalar(half)!)
            } else {
                out.append(scalar)
            }
        }
        return String(out)
    }

    static func toFullwidth(_ text: String) -> String {
        var out = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            let value = scalar.value
            // A half-width mark after a kana it voices makes the voiced kana.
            if value == voicedMark || value == semiVoicedMark, let last = out.last,
               let made = combined[last.value]?[value] {
                out.removeLast()
                out.append(Unicode.Scalar(made)!)
            } else if (0x21...0x7E).contains(value) {
                out.append(Unicode.Scalar(value + 0xFEE0)!)
            } else if value == 0x20 {
                out.append(Unicode.Scalar(0x3000)!)
            } else if let full = toFull[value] {
                out.append(Unicode.Scalar(full)!)
            } else {
                out.append(scalar)
            }
        }
        return String(out)
    }
}
#endif
