// Foundation's `URLComponents` and `URLQueryItem` on wasm (pf-web-foundation-gaps), and the
// international host names `URL` punycodes (RFC 3492). The platform-neutral cores
// (`_Punycode`, the percent-encoding sets and the query item split in `_URLParts`) are held
// to Foundation on macOS. Not here: UTS #46 mapping beyond lower-casing (Foundation maps
// compatibility characters and normalises; a host written with those stays as typed).

/// RFC 3492 Punycode, as IDNA uses it: `xn--` labels.
package enum _Punycode {
    private static let base = 36, tMin = 1, tMax = 26, skew = 38, damp = 700, initialBias = 72, initialN = 128

    private static func adapt(_ delta: Int, _ numPoints: Int, _ first: Bool) -> Int {
        var delta = first ? delta / damp : delta / 2
        delta += delta / numPoints
        var k = 0
        while delta > ((base - tMin) * tMax) / 2 {
            delta /= base - tMin
            k += base
        }
        return k + (base - tMin + 1) * delta / (delta + skew)
    }

    private static func digit(_ value: Int) -> Character {
        Character(Unicode.Scalar(UInt8(value < 26 ? 97 + value : 22 + value)))
    }

    private static func value(of character: Character) -> Int? {
        guard let scalar = character.unicodeScalars.first, character.unicodeScalars.count == 1 else { return nil }
        switch scalar.value {
        case 48...57: return Int(scalar.value) - 22
        case 65...90: return Int(scalar.value) - 65
        case 97...122: return Int(scalar.value) - 97
        default: return nil
        }
    }

    /// The Punycode of a label's scalars (without the `xn--` prefix); nil if it overflows.
    package static func encode(_ label: String) -> String? {
        let input = label.unicodeScalars.map { Int($0.value) }
        var output = String(String.UnicodeScalarView(label.unicodeScalars.filter { $0.value < 128 }))
        let basicCount = output.unicodeScalars.count
        var handled = basicCount
        if basicCount > 0 { output.append("-") }
        var n = initialN, delta = 0, bias = initialBias
        while handled < input.count {
            let m = input.filter { $0 >= n }.min()!
            delta += (m - n) * (handled + 1)
            n = m
            for c in input {
                if c < n { delta += 1 }
                if c == n {
                    var q = delta
                    var k = base
                    while true {
                        let t = k <= bias ? tMin : k >= bias + tMax ? tMax : k - bias
                        if q < t { break }
                        output.append(digit(t + (q - t) % (base - t)))
                        q = (q - t) / (base - t)
                        k += base
                    }
                    output.append(digit(q))
                    bias = adapt(delta, handled + 1, handled == basicCount)
                    delta = 0
                    handled += 1
                }
            }
            delta += 1
            n += 1
        }
        return output
    }

    /// The label a Punycode string (without `xn--`) spells, nil when malformed.
    package static func decode(_ text: String) -> String? {
        var output: [Int] = []
        var rest = Substring(text)
        if let dash = text.lastIndex(of: "-") {
            for character in text[..<dash] {
                guard let scalar = character.unicodeScalars.first, scalar.value < 128 else { return nil }
                output.append(Int(scalar.value))
            }
            rest = text[text.index(after: dash)...]
        }
        var n = initialN, i = 0, bias = initialBias
        var characters = Array(rest)
        var index = 0
        while index < characters.count {
            let oldi = i
            var w = 1
            var k = base
            while true {
                guard index < characters.count, let digit = value(of: characters[index]) else { return nil }
                index += 1
                i += digit * w
                let t = k <= bias ? tMin : k >= bias + tMax ? tMax : k - bias
                if digit < t { break }
                w *= base - t
                k += base
            }
            bias = adapt(i - oldi, output.count + 1, oldi == 0)
            n += i / (output.count + 1)
            i %= output.count + 1
            output.insert(n, at: i)
            i += 1
        }
        characters = []
        var scalars = String.UnicodeScalarView()
        for value in output {
            guard let scalar = Unicode.Scalar(UInt32(value)) else { return nil }
            scalars.append(scalar)
        }
        return String(scalars)
    }

    /// A host as the wire carries it: each label lower-cased, the non-ASCII ones Punycoded
    /// with the `xn--` prefix. ASCII hosts come back as written (Foundation keeps their case).
    package static func encodedHost(_ host: String) -> String? {
        guard host.unicodeScalars.contains(where: { $0.value >= 128 }) else { return host }
        var labels: [String] = []
        for label in folded(host).split(separator: ".", omittingEmptySubsequences: false) {
            // IDNA rejects empty labels and hyphens at a label's ends.
            guard !label.isEmpty, !label.hasPrefix("-"), !label.hasSuffix("-") else { return nil }
            if label.unicodeScalars.allSatisfy({ $0.value < 128 }) { labels.append(String(label)); continue }
            guard let encoded = encode(String(label)) else { return nil }
            labels.append("xn--" + encoded)
        }
        return labels.joined(separator: ".")
    }

    /// UTS #46 case folding as far as the bundle carries it: lower case, except Cherokee,
    /// whose small letters fold to the capitals.
    private static func folded(_ host: String) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in host.lowercased().unicodeScalars {
            switch scalar.value {
            case 0xAB70...0xABBF: scalars.append(Unicode.Scalar(scalar.value - 0xAB70 + 0x13A0)!)
            case 0x13F8...0x13FD: scalars.append(Unicode.Scalar(scalar.value - 8)!)
            default: scalars.append(scalar)
            }
        }
        return String(scalars)
    }

    /// The Unicode form of a host whose labels may be Punycoded.
    package static func decodedHost(_ host: String) -> String {
        host.split(separator: ".", omittingEmptySubsequences: false).map { label -> String in
            guard label.lowercased().hasPrefix("xn--"), let decoded = decode(String(label.dropFirst(4))) else { return String(label) }
            return decoded
        }.joined(separator: ".")
    }
}

extension _URLParts {
    /// The characters Foundation's `CharacterSet.url…Allowed` sets admit.
    package enum Allowed: Sendable {
        case user, password, host, path, query, fragment, queryItem

        package func admits(_ byte: UInt8) -> Bool {
            switch byte {
            case 0x41...0x5A, 0x61...0x7A, 0x30...0x39, 0x2D, 0x2E, 0x5F, 0x7E: return true   // unreserved
            case 0x21, 0x24, 0x27, 0x28, 0x29, 0x2A, 0x2B, 0x2C, 0x3B: return true   // sub-delims but & and =
            case 0x26, 0x3D: return self != .queryItem   // & and =
            case 0x3A: return self == .query || self == .fragment || self == .queryItem   // :
            case 0x40: return self == .path || self == .query || self == .fragment || self == .queryItem   // @
            case 0x2F: return self == .path || self == .query || self == .fragment || self == .queryItem   // /
            case 0x3F: return self == .query || self == .fragment || self == .queryItem   // ?
            default: return false
            }
        }
    }

    /// `text` with every byte the set does not admit percent-encoded (existing escapes too:
    /// the text is taken as unencoded).
    package static func percentEncoded(_ text: String, allowing allowed: Allowed) -> String {
        var result = ""
        for byte in text.utf8 {
            if allowed.admits(byte) { result.unicodeScalars.append(Unicode.Scalar(byte)) } else { result += "%" + hex(byte) }
        }
        return result
    }

    /// `text` with the bytes that cannot appear in a URL percent-encoded, keeping the escapes
    /// it has (a stray `%` becomes `%25`), as `URLComponents(string:)` repairs its input.
    package static func repairedForParsing(_ text: String) -> String {
        var result = ""
        let bytes = Array(text.utf8)
        // One stray `%` and Foundation encodes every `%`, the well-formed escapes included.
        var strayPercent = false
        for (index, byte) in bytes.enumerated() where byte == 0x25 {
            if !(index + 2 < bytes.count && hexValue(bytes[index + 1]) != nil && hexValue(bytes[index + 2]) != nil) { strayPercent = true }
        }
        var index = 0
        while index < bytes.count {
            let byte = bytes[index]
            if byte == 0x25 {
                result += strayPercent ? "%25" : "%"
            } else if byte <= 0x20 || byte == 0x7F || byte == 0x22 || byte == 0x3C || byte == 0x3E || byte == 0x5C || byte == 0x5E || byte == 0x60 || byte == 0x7B || byte == 0x7C || byte == 0x7D {
                result += "%" + hex(byte)
            } else {
                result.unicodeScalars.append(Unicode.Scalar(byte))
            }
            index += 1
        }
        return result
    }

    /// The query split into items at `&` and the first `=`, percent-encoded as stored; an
    /// item without `=` has a nil value. An empty query is an empty list.
    package static func queryItems(_ query: String) -> [(name: String, value: String?)] {
        guard !query.isEmpty else { return [] }
        return query.split(separator: "&", omittingEmptySubsequences: false).map { item in
            if let equals = item.firstIndex(of: "=") {
                return (String(item[..<equals]), String(item[item.index(after: equals)...]))
            }
            return (String(item), nil)
        }
    }

    /// The query for items whose names and values are unencoded (`&`, `=`, `#`, spaces and
    /// non-ASCII encoded; `+`, `?` and `/` kept), as Foundation's `queryItems` setter writes.
    package static func query(items: [(name: String, value: String?)]) -> String {
        items.map { item in
            let name = percentEncoded(item.name, allowing: .queryItem)
            guard let value = item.value else { return name }
            return name + "=" + percentEncoded(value, allowing: .queryItem)
        }.joined(separator: "&")
    }
}

#if os(WASI)
/// A name and value from a URL's query.
public struct URLQueryItem: Hashable, Sendable, Codable, CustomStringConvertible {
    public var name: String
    public var value: String?
    public init(name: String, value: String?) {
        self.name = name
        self.value = value
    }
    public var description: String { value.map { name + "=" + $0 } ?? name }
}

/// A URL taken apart: the components read decoded and set from unencoded text, with the
/// percent-encoded forms beside them.
public struct URLComponents: Hashable, Sendable, CustomStringConvertible {
    private var parts: _URLParts

    public init() { parts = _URLParts() }

    /// The components of a string, nil when it is not a URL even after its spaces and stray
    /// characters are percent-encoded.
    public init?(string: String) {
        guard let parts = _URLParts.parse(_URLParts.repairedForParsing(string)) else { return nil }
        self.parts = parts
    }

    public init?(string: String, encodingInvalidCharacters: Bool) {
        guard let parts = _URLParts.parse(encodingInvalidCharacters ? _URLParts.repairedForParsing(string) : string) else { return nil }
        self.parts = parts
    }

    /// The components of a URL: its absolute string when resolving, its relative string otherwise.
    public init?(url: URL, resolvingAgainstBaseURL resolve: Bool) {
        self.init(string: resolve ? url.absoluteString : url.relativeString)
    }

    // MARK: Components

    public var scheme: String? {
        get { parts.scheme }
        set { parts.scheme = newValue }
    }

    public var user: String? {
        get { parts.user.map(_URLParts.percentDecoded) }
        set { parts.user = newValue.map { _URLParts.percentEncoded($0, allowing: .user) }; if newValue != nil { parts.hasAuthority = true } }
    }
    public var percentEncodedUser: String? {
        get { parts.user }
        set { parts.user = newValue; if newValue != nil { parts.hasAuthority = true } }
    }

    public var password: String? {
        get { parts.password.map(_URLParts.percentDecoded) }
        set { parts.password = newValue.map { _URLParts.percentEncoded($0, allowing: .password) }; if newValue != nil { parts.hasAuthority = true } }
    }
    public var percentEncodedPassword: String? {
        get { parts.password }
        set { parts.password = newValue; if newValue != nil { parts.hasAuthority = true } }
    }

    /// The host in Unicode (a Punycoded label decoded).
    public var host: String? {
        get { parts.host.map { _Punycode.decodedHost(_URLParts.percentDecoded($0)) } }
        set { parts.host = newValue.map { _URLParts.percentEncoded($0, allowing: .host) }; parts.hasAuthority = newValue != nil || parts.hasAuthority }
    }
    /// The host with its non-ASCII percent-encoded.
    public var percentEncodedHost: String? {
        get { parts.host }
        set { parts.host = newValue; parts.hasAuthority = newValue != nil || parts.hasAuthority }
    }
    /// The host as the wire carries it (Punycoded).
    public var encodedHost: String? {
        get { parts.host.flatMap { _Punycode.encodedHost(_URLParts.percentDecoded($0)) } }
        set { percentEncodedHost = newValue }
    }

    public var port: Int? {
        get { parts.port }
        set { parts.port = newValue; if newValue != nil { parts.hasAuthority = true } }
    }

    public var path: String {
        get { _URLParts.percentDecoded(parts.path) }
        set { parts.path = _URLParts.percentEncoded(newValue, allowing: .path) }
    }
    public var percentEncodedPath: String {
        get { parts.path }
        set { parts.path = newValue }
    }

    public var query: String? {
        get { parts.query.map(_URLParts.percentDecoded) }
        set { parts.query = newValue.map { _URLParts.percentEncoded($0, allowing: .query) } }
    }
    public var percentEncodedQuery: String? {
        get { parts.query }
        set { parts.query = newValue }
    }

    public var fragment: String? {
        get { parts.fragment.map(_URLParts.percentDecoded) }
        set { parts.fragment = newValue.map { _URLParts.percentEncoded($0, allowing: .fragment) } }
    }
    public var percentEncodedFragment: String? {
        get { parts.fragment }
        set { parts.fragment = newValue }
    }

    /// The query's items, decoded (a `+` stays a `+`); nil without a query, empty for `?`.
    public var queryItems: [URLQueryItem]? {
        get { parts.query.map { _URLParts.queryItems($0).map { URLQueryItem(name: _URLParts.percentDecoded($0.name), value: $0.value.map(_URLParts.percentDecoded)) } } }
        set { parts.query = newValue.map { _URLParts.query(items: $0.map { ($0.name, $0.value) }) } }
    }
    public var percentEncodedQueryItems: [URLQueryItem]? {
        get { parts.query.map { _URLParts.queryItems($0).map { URLQueryItem(name: $0.name, value: $0.value) } } }
        set { parts.query = newValue.map { items in items.map { item in item.value.map { item.name + "=" + $0 } ?? item.name }.joined(separator: "&") } }
    }

    // MARK: Composition

    /// The URL string, nil when the parts cannot form one (a host with a path that does not
    /// start with `/`, a scheme that is not one).
    public var string: String? {
        var parts = self.parts
        if let host = parts.host {
            guard let encoded = _Punycode.encodedHost(_URLParts.percentDecoded(host)) else { return nil }
            parts.host = encoded
            parts.hasAuthority = true
            if !parts.path.isEmpty, !parts.path.hasPrefix("/") { return nil }
        }
        if let scheme = parts.scheme {
            guard let first = scheme.first, first.isLetter, scheme.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "+" || $0 == "-" || $0 == "." }) else { return nil }
        }
        if parts.hasAuthority, parts.host == nil, parts.user == nil, parts.port == nil { parts.hasAuthority = parts.scheme == "file" }
        return parts.string
    }

    public var url: URL? { string.flatMap { URL(string: $0) } }
    public func url(relativeTo base: URL?) -> URL? { string.flatMap { URL(string: $0, relativeTo: base) } }

    public var description: String { string ?? "URLComponents(invalid)" }
}

extension URL {
    /// The URL with its query items replaced (Foundation's `appending(queryItems:)` adds).
    public func appending(queryItems: [URLQueryItem]) -> URL {
        var components = URLComponents(url: self, resolvingAgainstBaseURL: true) ?? URLComponents()
        components.queryItems = (components.queryItems ?? []) + queryItems
        return components.url ?? self
    }
    public mutating func append(queryItems: [URLQueryItem]) { self = appending(queryItems: queryItems) }
}
#endif
