// Base64 for `Data` on wasm (decision 0017), shared with the tests on every platform.

/// The standard alphabet with `=` padding; decoding also accepts the URL-safe alphabet and
/// unpadded input, and rejects whitespace unless asked to ignore unknown characters, as
/// Foundation's `Data(base64Encoded:)` does.
package enum _Base64 {
    private static let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/".utf8)

    package static func encode(_ bytes: [UInt8], lineLength: Int? = nil) -> String {
        var out: [UInt8] = []
        out.reserveCapacity((bytes.count + 2) / 3 * 4)
        var index = 0
        while index + 3 <= bytes.count {
            let chunk = (UInt32(bytes[index]) << 16) | (UInt32(bytes[index + 1]) << 8) | UInt32(bytes[index + 2])
            out.append(alphabet[Int(chunk >> 18)])
            out.append(alphabet[Int((chunk >> 12) & 63)])
            out.append(alphabet[Int((chunk >> 6) & 63)])
            out.append(alphabet[Int(chunk & 63)])
            index += 3
        }
        let rest = bytes.count - index
        if rest == 1 {
            let chunk = UInt32(bytes[index]) << 16
            out.append(alphabet[Int(chunk >> 18)])
            out.append(alphabet[Int((chunk >> 12) & 63)])
            out.append(UInt8(ascii: "="))
            out.append(UInt8(ascii: "="))
        } else if rest == 2 {
            let chunk = (UInt32(bytes[index]) << 16) | (UInt32(bytes[index + 1]) << 8)
            out.append(alphabet[Int(chunk >> 18)])
            out.append(alphabet[Int((chunk >> 12) & 63)])
            out.append(alphabet[Int((chunk >> 6) & 63)])
            out.append(UInt8(ascii: "="))
        }
        if let lineLength, lineLength > 0, out.count > lineLength {
            var wrapped: [UInt8] = []
            for (i, byte) in out.enumerated() {
                if i > 0, i % lineLength == 0 { wrapped.append(UInt8(ascii: "\r")); wrapped.append(UInt8(ascii: "\n")) }
                wrapped.append(byte)
            }
            out = wrapped
        }
        return String(decoding: out, as: UTF8.self)
    }

    package static func decode(_ text: some Sequence<UInt8>, ignoreUnknown: Bool = false) -> [UInt8]? {
        var bytes: [UInt8] = []
        var accumulator: UInt32 = 0, bits = 0, padding = 0, symbols = 0
        for scalar in text {
            let value: UInt32
            switch scalar {
            case UInt8(ascii: "A")...UInt8(ascii: "Z"): value = UInt32(scalar - UInt8(ascii: "A"))
            case UInt8(ascii: "a")...UInt8(ascii: "z"): value = UInt32(scalar - UInt8(ascii: "a")) + 26
            case UInt8(ascii: "0")...UInt8(ascii: "9"): value = UInt32(scalar - UInt8(ascii: "0")) + 52
            case UInt8(ascii: "+"), UInt8(ascii: "-"): value = 62
            case UInt8(ascii: "/"), UInt8(ascii: "_"): value = 63
            case UInt8(ascii: "="): padding += 1; continue
            default:
                if ignoreUnknown { continue }
                return nil
            }
            if padding > 0 { return nil }
            symbols += 1
            accumulator = (accumulator << 6) | value
            bits += 6
            if bits >= 8 {
                bits -= 8
                bytes.append(UInt8((accumulator >> UInt32(bits)) & 0xFF))
            }
        }
        // A lone trailing symbol holds no whole byte; padding is at most two characters.
        if padding > 2 || symbols % 4 == 1 { return nil }
        return bytes
    }
}
