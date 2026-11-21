// Link Presentation on the web: `LPLinkMetadata` is the record apps fill in themselves (a share
// sheet's preview: IceCubes' title and image provider), and `LPMetadataProvider` fetches a page
// and reads its title and canonical URL from the markup: the Open Graph title, else the
// `<title>`. The browser only lets a page read another site's markup when that site allows it
// (CORS), so a fetch of most sites fails, as Apple's does offline: with `LPError`'s
// `metadataFetchFailed`. No icon, image or video is loaded, so those providers stay `nil`.
// Apple's framework re-exports Foundation: a file importing only this module names `URL`.
@_exported import WebFoundation
#if canImport(FoundationNetworking)
import FoundationNetworking   // Linux keeps URLSession here
#endif

/// What a link preview shows: the link, its title, and providers for its icon, image and video.
open class LPLinkMetadata: NSObject, @unchecked Sendable {
    /// The URL the metadata was asked for.
    open var originalURL: URL?
    /// The URL the metadata describes, after redirects and the page's canonical link.
    open var url: URL?
    open var title: String?
    open var iconProvider: NSItemProvider?
    open var imageProvider: NSItemProvider?
    open var videoProvider: NSItemProvider?
    open var remoteVideoURL: URL?
    public override init() { super.init() }
}

/// The domain of Link Presentation's errors.
public let LPErrorDomain = "LPErrorDomain"

/// Why a metadata fetch failed.
public struct LPError: Error, Hashable, Sendable {
    public enum Code: Int, Sendable {
        case unknown = 1, metadataFetchFailed, metadataFetchCancelled, metadataFetchTimedOut, metadataFetchNotAllowed
    }
    public let code: Code
    public init(_ code: Code) { self.code = code }
    public static var errorDomain: String { LPErrorDomain }
    public static let unknown = Code.unknown
    public static let metadataFetchFailed = Code.metadataFetchFailed
    public static let metadataFetchCancelled = Code.metadataFetchCancelled
    public static let metadataFetchTimedOut = Code.metadataFetchTimedOut
    public static let metadataFetchNotAllowed = Code.metadataFetchNotAllowed
    public static func ~= (code: Code, error: any Error) -> Bool { (error as? LPError)?.code == code }
}

/// Fetches a page's metadata, once per provider (a second fetch fails, as Apple's does).
open class LPMetadataProvider: NSObject, @unchecked Sendable {
    /// Whether icons, images and videos would be fetched too (none are, here).
    open var shouldFetchSubresources = true
    open var timeout: TimeInterval = 30
    private var started = false
    private var task: Task<LPLinkMetadata, any Error>?

    public override init() { super.init() }

    /// The page's metadata: its title and URL, read from the markup the fetch returned.
    open func startFetchingMetadata(for url: URL) async throws -> LPLinkMetadata {
        guard !started else { throw LPError(.metadataFetchNotAllowed) }
        started = true
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            throw LPError(.metadataFetchNotAllowed)
        }
        let timeout = timeout
        let fetch = Task<LPLinkMetadata, any Error> {
            var request = URLRequest(url: url)
            request.timeoutInterval = timeout
            let result: (Data, URLResponse)
            do {
                result = try await URLSession.shared.data(for: request)
            } catch let error as URLError where error.code == .cancelled {
                throw LPError(.metadataFetchCancelled)
            } catch let error as URLError where error.code == .timedOut {
                throw LPError(.metadataFetchTimedOut)
            } catch {
                throw LPError(.metadataFetchFailed)
            }
            let (data, response) = result
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw LPError(.metadataFetchFailed)
            }
            return _LinkMetadataReader.metadata(html: String(decoding: data, as: UTF8.self), original: url, loaded: response.url ?? url)
        }
        task = fetch
        return try await fetch.value
    }

    /// The page's metadata, or the error, handed to `completionHandler`.
    open func startFetchingMetadata(for url: URL, completionHandler: @escaping @Sendable (LPLinkMetadata?, (any Error)?) -> Void) {
        nonisolated(unsafe) let provider = self
        Task {
            do { completionHandler(try await provider.startFetchingMetadata(for: url), nil) } catch { completionHandler(nil, error) }
        }
    }

    /// Stops a fetch under way: it fails with `metadataFetchCancelled`.
    open func cancel() { task?.cancel() }
}

/// Reads a page's title and canonical URL out of its markup, without a parser: the `<meta>` and
/// `<link>` tags' attributes and the `<title>` element's text.
package enum _LinkMetadataReader {
    package static func metadata(html: String, original: URL, loaded: URL) -> LPLinkMetadata {
        let metadata = LPLinkMetadata()
        metadata.originalURL = original
        metadata.url = loaded
        let tags = self.tags(in: html)
        func meta(_ key: String) -> String? {
            tags.first { $0.name == "meta" && ($0.attributes["property"] == key || $0.attributes["name"] == key) }?.attributes["content"]
        }
        let title = meta("og:title") ?? meta("twitter:title") ?? titleElement(in: html)
        if let title = title.map(decodeEntities).map(collapseWhitespace), !title.isEmpty { metadata.title = title }
        let canonical = meta("og:url") ?? tags.first { $0.name == "link" && $0.attributes["rel"]?.lowercased() == "canonical" }?.attributes["href"]
        if let canonical, let resolved = URL(string: decodeEntities(canonical), relativeTo: loaded)?.absoluteURL,
           resolved.scheme == "http" || resolved.scheme == "https" {
            metadata.url = resolved
        }
        return metadata
    }

    struct Tag { let name: String; let attributes: [String: String] }

    /// The page's tags with their attributes (names lowercased), up to the end of `<head>`.
    static func tags(in html: String) -> [Tag] {
        let chars = Array(html.unicodeScalars)
        var tags: [Tag] = []
        var i = 0
        while i < chars.count {
            guard chars[i] == "<" else { i += 1; continue }
            var j = i + 1
            var name = ""
            while j < chars.count, chars[j].properties.isAlphabetic || chars[j] == "/" || chars[j] == "!" {
                name.unicodeScalars.append(chars[j]); j += 1
            }
            name = name.lowercased()
            if name == "/head" || name == "body" { break }
            var attributes: [String: String] = [:]
            while j < chars.count, chars[j] != ">" {
                if chars[j].properties.isWhitespace || chars[j] == "/" { j += 1; continue }
                var key = ""
                while j < chars.count, !chars[j].properties.isWhitespace, chars[j] != "=", chars[j] != ">" {
                    key.unicodeScalars.append(chars[j]); j += 1
                }
                while j < chars.count, chars[j].properties.isWhitespace { j += 1 }
                var value = ""
                if j < chars.count, chars[j] == "=" {
                    j += 1
                    while j < chars.count, chars[j].properties.isWhitespace { j += 1 }
                    if j < chars.count, chars[j] == "\"" || chars[j] == "'" {
                        let quote = chars[j]; j += 1
                        while j < chars.count, chars[j] != quote { value.unicodeScalars.append(chars[j]); j += 1 }
                        j += 1
                    } else {
                        while j < chars.count, !chars[j].properties.isWhitespace, chars[j] != ">" { value.unicodeScalars.append(chars[j]); j += 1 }
                    }
                }
                if !key.isEmpty { attributes[key.lowercased()] = value }
            }
            if !name.isEmpty { tags.append(Tag(name: name, attributes: attributes)) }
            i = j + 1
        }
        return tags
    }

    /// The text of the first `<title>` element.
    static func titleElement(in html: String) -> String? {
        let chars = Array(html.unicodeScalars)
        let open = Array("<title".unicodeScalars), close = Array("</title".unicodeScalars)
        func find(_ needle: [Unicode.Scalar], from start: Int) -> Int? {
            guard needle.count <= chars.count else { return nil }
            var i = start
            while i + needle.count <= chars.count {
                var k = 0
                while k < needle.count, lower(chars[i + k]) == needle[k] { k += 1 }
                if k == needle.count { return i }
                i += 1
            }
            return nil
        }
        guard let start = find(open, from: 0) else { return nil }
        var j = start + open.count
        while j < chars.count, chars[j] != ">" { j += 1 }
        guard j < chars.count, let end = find(close, from: j + 1) else { return nil }
        var text = ""
        text.unicodeScalars.append(contentsOf: chars[(j + 1)..<end])
        return text
    }

    private static func lower(_ scalar: Unicode.Scalar) -> Unicode.Scalar {
        (scalar.value >= 65 && scalar.value <= 90) ? Unicode.Scalar(scalar.value + 32)! : scalar
    }

    /// The text with runs of whitespace made one space and the ends trimmed.
    static func collapseWhitespace(_ text: String) -> String {
        var out = ""
        var pendingSpace = false
        for scalar in text.unicodeScalars {
            if scalar.properties.isWhitespace { pendingSpace = !out.isEmpty; continue }
            if pendingSpace { out.unicodeScalars.append(" "); pendingSpace = false }
            out.unicodeScalars.append(scalar)
        }
        return out
    }

    /// The text with HTML's character references decoded: the five named ones and numeric ones.
    static func decodeEntities(_ text: String) -> String {
        let named: [String: Unicode.Scalar] = ["amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": "\u{A0}"]
        let chars = Array(text.unicodeScalars)
        var out = ""
        var i = 0
        while i < chars.count {
            if chars[i] == "&", let semicolon = chars[(i + 1)...].prefix(10).firstIndex(of: ";") {
                var name = ""
                name.unicodeScalars.append(contentsOf: chars[(i + 1)..<semicolon])
                var decoded: Unicode.Scalar?
                if let first = name.unicodeScalars.first, first == "#" {
                    let digits = String(name.unicodeScalars.dropFirst())
                    let value = digits.first == "x" || digits.first == "X" ? UInt32(digits.dropFirst(), radix: 16) : UInt32(digits)
                    decoded = value.flatMap { Unicode.Scalar($0) }
                } else {
                    decoded = named[name.lowercased()]
                }
                if let decoded {
                    out.unicodeScalars.append(decoded)
                    i = semicolon + 1
                    continue
                }
            }
            out.unicodeScalars.append(chars[i])
            i += 1
        }
        return out
    }
}
