// Foundation's `URL` on wasm (decision 0017): a parsed string. The parser follows RFC 3986's
// generic syntax and relative resolution; the surface is what `Link`, `AsyncImage`, `openURL`
// and ordinary apps call. `_URLParts` is the platform-neutral core the tests compare with
// Foundation. Not here: international host names (Foundation punycodes them), file system
// checks (`standardized`, `checkFileSystem`), and `URLComponents`.

/// The parts of a URL string, split by RFC 3986's generic syntax.
package struct _URLParts: Hashable, Sendable {
    package var scheme: String?
    package var user: String?
    package var password: String?
    package var host: String?
    package var port: Int?
    package var path: String
    package var query: String?
    package var fragment: String?
    /// Whether the string had an authority (`//host`); a file URL keeps an empty one.
    package var hasAuthority: Bool

    package init(scheme: String? = nil, user: String? = nil, password: String? = nil, host: String? = nil, port: Int? = nil,
                 path: String = "", query: String? = nil, fragment: String? = nil, hasAuthority: Bool = false) {
        self.scheme = scheme; self.user = user; self.password = password; self.host = host; self.port = port
        self.path = path; self.query = query; self.fragment = fragment; self.hasAuthority = hasAuthority
    }

    /// Parses a string, or nil when it holds whitespace or control characters or the scheme
    /// or port is malformed. Non-ASCII characters are percent-encoded as UTF-8.
    package static func parse(_ text: String) -> _URLParts? {
        guard !text.isEmpty else { return nil }
        var encoded = ""
        for scalar in text.unicodeScalars {
            if scalar.value <= 0x20 || scalar.value == 0x7F { return nil }
            if scalar.value < 0x80 { encoded.unicodeScalars.append(scalar) } else {
                for byte in String(scalar).utf8 { encoded += "%" + hex(byte) }
            }
        }
        var rest = Substring(encoded)
        var parts = _URLParts()
        if let hash = rest.firstIndex(of: "#") { parts.fragment = String(rest[rest.index(after: hash)...]); rest = rest[..<hash] }
        if let question = rest.firstIndex(of: "?") { parts.query = String(rest[rest.index(after: question)...]); rest = rest[..<question] }
        if let colon = rest.firstIndex(of: ":"), !rest[..<colon].contains("/") {
            let candidate = rest[..<colon]
            guard let first = candidate.first, first.isLetter, candidate.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "+" || $0 == "-" || $0 == "." }) else { return nil }
            parts.scheme = String(candidate)
            rest = rest[rest.index(after: colon)...]
        }
        if rest.hasPrefix("//") {
            parts.hasAuthority = true
            rest = rest.dropFirst(2)
            let authority: Substring
            if let slash = rest.firstIndex(of: "/") { authority = rest[..<slash]; rest = rest[slash...] } else { authority = rest; rest = "" }
            var hostPort = authority
            if let at = authority.lastIndex(of: "@") {
                let userInfo = authority[..<at]
                hostPort = authority[authority.index(after: at)...]
                if let colon = userInfo.firstIndex(of: ":") {
                    parts.user = String(userInfo[..<colon]); parts.password = String(userInfo[userInfo.index(after: colon)...])
                } else {
                    parts.user = String(userInfo)
                }
            }
            if hostPort.hasPrefix("["), let close = hostPort.firstIndex(of: "]") {
                parts.host = String(hostPort[hostPort.index(after: hostPort.startIndex)..<close])
                let after = hostPort[hostPort.index(after: close)...]
                if after.hasPrefix(":") {
                    guard let port = Int(after.dropFirst()) else { return nil }
                    parts.port = port
                } else if !after.isEmpty { return nil }
            } else if let colon = hostPort.lastIndex(of: ":") {
                let portText = hostPort[hostPort.index(after: colon)...]
                if !portText.isEmpty {
                    guard let port = Int(portText), portText.allSatisfy(\.isNumber) else { return nil }
                    parts.port = port
                }
                parts.host = String(hostPort[..<colon])
            } else {
                parts.host = String(hostPort)
            }
            if parts.host == "" { parts.host = nil }
        }
        parts.path = String(rest)
        return parts
    }

    private static func hex(_ byte: UInt8) -> String {
        let digits = Array("0123456789ABCDEF")
        return String(digits[Int(byte >> 4)]) + String(digits[Int(byte & 15)])
    }

    /// The string the parts spell, RFC 3986 section 5.3.
    package var string: String {
        var result = ""
        if let scheme { result += scheme + ":" }
        if hasAuthority {
            result += "//"
            if let user {
                result += user
                if let password { result += ":" + password }
                result += "@"
            }
            if let host { result += host.contains(":") ? "[" + host + "]" : host }
            if let port { result += ":" + String(port) }
        }
        result += path
        if let query { result += "?" + query }
        if let fragment { result += "#" + fragment }
        return result
    }

    /// Resolves the parts against a base, RFC 3986 section 5.2.2 (strict).
    package func resolved(against base: _URLParts) -> _URLParts {
        var target = _URLParts()
        if scheme != nil {
            target = self
            target.path = Self.removeDotSegments(path)
            return target
        }
        target.scheme = base.scheme
        if hasAuthority {
            target.hasAuthority = true; target.user = user; target.password = password; target.host = host; target.port = port
            target.path = Self.removeDotSegments(path); target.query = query
        } else {
            target.hasAuthority = base.hasAuthority; target.user = base.user; target.password = base.password
            target.host = base.host; target.port = base.port
            if path.isEmpty {
                target.path = base.path
                target.query = query ?? base.query
            } else {
                if path.hasPrefix("/") {
                    target.path = Self.removeDotSegments(path)
                } else {
                    let merged: String
                    if base.hasAuthority, base.path.isEmpty { merged = "/" + path } else if let slash = base.path.lastIndex(of: "/") {
                        merged = String(base.path[...slash]) + path
                    } else { merged = path }
                    target.path = Self.removeDotSegments(merged)
                }
                target.query = query
            }
        }
        target.fragment = fragment
        return target
    }

    /// RFC 3986 section 5.2.4.
    package static func removeDotSegments(_ path: String) -> String {
        var input = Substring(path)
        var output: [Substring] = []
        while !input.isEmpty {
            if input.hasPrefix("../") { input = input.dropFirst(3) }
            else if input.hasPrefix("./") { input = input.dropFirst(2) }
            else if input.hasPrefix("/./") { input = input.dropFirst(2) }
            else if input == "/." { input = "/" }
            else if input.hasPrefix("/../") { input = input.dropFirst(3); if !output.isEmpty { output.removeLast() } }
            else if input == "/.." { input = "/"; if !output.isEmpty { output.removeLast() } }
            else if input == "." || input == ".." { input = "" }
            else {
                let start = input.startIndex
                let searchStart = input.hasPrefix("/") ? input.index(after: start) : start
                let end = input[searchStart...].firstIndex(of: "/") ?? input.endIndex
                output.append(input[start..<end])
                input = input[end...]
            }
        }
        return output.joined()
    }

    /// The path's segments without empty ones, Foundation's `pathComponents` (a leading "/"),
    /// percent-decoded like every path accessor but `path(percentEncoded: true)`.
    package var pathComponents: [String] {
        var components: [String] = []
        if path.hasPrefix("/") { components.append("/") }
        components += path.split(separator: "/", omittingEmptySubsequences: true).map { Self.percentDecoded(String($0)) }
        return components
    }

    package var lastPathComponent: String {
        let trimmed = path.hasSuffix("/") && path.count > 1 ? String(path.dropLast()) : path
        if trimmed == "/" { return "/" }
        if let slash = trimmed.lastIndex(of: "/") { return Self.percentDecoded(String(trimmed[trimmed.index(after: slash)...])) }
        return Self.percentDecoded(trimmed)
    }

    package var pathExtension: String {
        let last = lastPathComponent
        guard let dot = last.lastIndex(of: "."), dot != last.startIndex, last.index(after: dot) != last.endIndex else { return "" }
        return String(last[last.index(after: dot)...])
    }

    /// `%XX` escapes replaced by their bytes, decoded as UTF-8 (invalid escapes stay as they are).
    package static func percentDecoded(_ text: String) -> String {
        guard text.contains("%") else { return text }
        var bytes: [UInt8] = []
        let utf8 = Array(text.utf8)
        var index = 0
        while index < utf8.count {
            if utf8[index] == UInt8(ascii: "%"), index + 2 < utf8.count, let high = hexValue(utf8[index + 1]), let low = hexValue(utf8[index + 2]) {
                bytes.append(high << 4 | low)
                index += 3
            } else {
                bytes.append(utf8[index])
                index += 1
            }
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    private static func hexValue(_ byte: UInt8) -> UInt8? {
        switch byte {
        case UInt8(ascii: "0")...UInt8(ascii: "9"): return byte - UInt8(ascii: "0")
        case UInt8(ascii: "a")...UInt8(ascii: "f"): return byte - UInt8(ascii: "a") + 10
        case UInt8(ascii: "A")...UInt8(ascii: "F"): return byte - UInt8(ascii: "A") + 10
        default: return nil
        }
    }
}

#if os(WASI)
public struct URL: Hashable, Sendable, Codable, CustomStringConvertible, CustomDebugStringConvertible {
    private let relative: String
    private let parts: _URLParts
    private let base: _URLBox?
    /// The base the string was resolved against, if any.
    public var baseURL: URL? { base?.url }

    private init(relative: String, parts: _URLParts, baseURL: URL?) {
        self.relative = relative
        self.parts = parts
        self.base = baseURL.map(_URLBox.init)
    }

    public init?(string: String) {
        guard let parts = _URLParts.parse(string) else { return nil }
        self.init(relative: string, parts: parts, baseURL: nil)
    }
    public init?(string: String, relativeTo base: URL?) {
        guard let own = _URLParts.parse(string) else { return nil }
        if let base, own.scheme == nil {
            self.init(relative: string, parts: own.resolved(against: base.parts), baseURL: base)
        } else {
            self.init(relative: string, parts: own, baseURL: nil)
        }
    }
    public init?(string: String, encodingInvalidCharacters: Bool) { self.init(string: string) }
    public init(fileURLWithPath path: String, isDirectory: Bool) {
        var parts = _URLParts(scheme: "file", path: path.hasPrefix("/") ? path : "/" + path, hasAuthority: true)
        if isDirectory, !parts.path.hasSuffix("/") { parts.path += "/" }
        self.init(relative: parts.string, parts: parts, baseURL: nil)
    }
    public init(fileURLWithPath path: String) { self.init(fileURLWithPath: path, isDirectory: path.hasSuffix("/")) }
    public init(filePath path: String) { self.init(fileURLWithPath: path) }

    public var absoluteString: String { parts.string }
    public var relativeString: String { relative }
    public var absoluteURL: URL { baseURL == nil ? self : URL(relative: parts.string, parts: parts, baseURL: nil) }
    public var scheme: String? { parts.scheme }
    public var host: String? { parts.host }
    public func host(percentEncoded: Bool = true) -> String? { parts.host }
    public var port: Int? { parts.port }
    public var user: String? { parts.user }
    public var password: String? { parts.password }
    public var path: String { _URLParts.percentDecoded(parts.path.hasSuffix("/") && parts.path.count > 1 ? String(parts.path.dropLast()) : parts.path) }
    public func path(percentEncoded: Bool = true) -> String { percentEncoded ? parts.path : _URLParts.percentDecoded(parts.path) }
    public var relativePath: String { path }
    public var query: String? { parts.query }
    public func query(percentEncoded: Bool = true) -> String? { parts.query }
    public var fragment: String? { parts.fragment }
    public func fragment(percentEncoded: Bool = true) -> String? { parts.fragment }
    public var isFileURL: Bool { parts.scheme == "file" }
    public var hasDirectoryPath: Bool { parts.path.hasSuffix("/") }
    public var pathComponents: [String] { parts.pathComponents }
    public var lastPathComponent: String { parts.lastPathComponent }
    public var pathExtension: String { parts.pathExtension }
    public var standardized: URL { self }
    public var standardizedFileURL: URL { self }

    private func withPath(_ path: String) -> URL {
        var parts = self.parts
        parts.path = path
        return URL(relative: parts.string, parts: parts, baseURL: nil)
    }
    public func appendingPathComponent(_ component: String, isDirectory: Bool = false) -> URL {
        var path = parts.path
        if !path.hasSuffix("/"), !path.isEmpty { path += "/" }
        if path.isEmpty, parts.hasAuthority { path = "/" }
        path += component
        if isDirectory, !path.hasSuffix("/") { path += "/" }
        return withPath(path)
    }
    public func appending(path: String, directoryHint: DirectoryHint = .inferFromPath) -> URL {
        appendingPathComponent(path, isDirectory: directoryHint == .isDirectory || (directoryHint == .inferFromPath && path.hasSuffix("/")))
    }
    public func appending(component: String, directoryHint: DirectoryHint = .inferFromPath) -> URL {
        appending(path: component, directoryHint: directoryHint)
    }
    public func appendingPathExtension(_ pathExtension: String) -> URL {
        guard !pathExtension.isEmpty else { return self }
        let trailing = parts.path.hasSuffix("/")
        let base = trailing ? String(parts.path.dropLast()) : parts.path
        return withPath(base + "." + pathExtension + (trailing ? "/" : ""))
    }
    public func deletingLastPathComponent() -> URL {
        let trimmed = parts.path.hasSuffix("/") && parts.path.count > 1 ? String(parts.path.dropLast()) : parts.path
        guard let slash = trimmed.lastIndex(of: "/") else { return withPath("") }
        return withPath(String(trimmed[...slash]))
    }
    public func deletingPathExtension() -> URL {
        let ext = pathExtension
        guard !ext.isEmpty else { return self }
        let trailing = parts.path.hasSuffix("/")
        let base = trailing ? String(parts.path.dropLast()) : parts.path
        return withPath(String(base.dropLast(ext.count + 1)) + (trailing ? "/" : ""))
    }
    public mutating func appendPathComponent(_ component: String) { self = appendingPathComponent(component) }
    public mutating func appendPathComponent(_ component: String, isDirectory: Bool) { self = appendingPathComponent(component, isDirectory: isDirectory) }
    public mutating func appendPathExtension(_ pathExtension: String) { self = appendingPathExtension(pathExtension) }
    public mutating func deleteLastPathComponent() { self = deletingLastPathComponent() }
    public mutating func deletePathExtension() { self = deletingPathExtension() }

    public enum DirectoryHint: Sendable { case isDirectory, notDirectory, checkFileSystem, inferFromPath }

    public var description: String { baseURL.map { "\(relative) -- \($0.absoluteString)" } ?? absoluteString }
    public var debugDescription: String { description }
    public var dataRepresentation: Data { Data(absoluteString.utf8) }

    public static func == (lhs: URL, rhs: URL) -> Bool { lhs.absoluteString == rhs.absoluteString }
    private final class _URLBox: Sendable {
        let url: URL
        init(_ url: URL) { self.url = url }
    }
    public func hash(into hasher: inout Hasher) { hasher.combine(absoluteString) }

    // Foundation's coding: `relative` and an optional `base`.
    private enum CodingKeys: String, CodingKey { case relative, base }
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let relative = try container.decode(String.self, forKey: .relative)
        let base = try container.decodeIfPresent(URL.self, forKey: .base)
        guard let url = URL(string: relative, relativeTo: base) else {
            throw DecodingError.dataCorruptedError(forKey: .relative, in: container, debugDescription: "Invalid URL string.")
        }
        self = url
    }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(relative, forKey: .relative)
        try container.encodeIfPresent(baseURL, forKey: .base)
    }
}
#endif
