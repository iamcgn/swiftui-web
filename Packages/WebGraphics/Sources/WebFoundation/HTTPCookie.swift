// HTTPCookie and HTTPCookieStorage (decision 0021, the Ember app's account session): the
// cookie values an app makes and keeps, as Foundation's. The browser's own cookie jar is
// not readable from a page (`fetch` sends the origin's cookies itself and `HttpOnly` ones
// are never exposed), so this storage is the app's: what it sets here is what it reads back
// — the jar `URLSession` consults for `httpShouldSetCookies` is the browser's, not this one.
#if os(WASI)

/// A representation of an HTTP cookie.
public final class HTTPCookie: @unchecked Sendable, Hashable, CustomStringConvertible {
    public let properties: [HTTPCookiePropertyKey: Any]?
    public let name: String
    public let value: String
    public let domain: String
    public let path: String
    public let expiresDate: Date?
    public let isSecure: Bool
    public let isHTTPOnly: Bool
    public let isSessionOnly: Bool
    public let comment: String?
    public let commentURL: URL?
    public let portList: [Int]?
    public let version: Int
    public let sameSitePolicy: HTTPCookieStringPolicy?

    /// A cookie from its properties; nil without a name, value, path and a domain or origin URL.
    public init?(properties: [HTTPCookiePropertyKey: Any]) {
        guard let name = properties[.name] as? String, let value = properties[.value] as? String else { return nil }
        let path = properties[.path] as? String ?? "/"
        var domain = properties[.domain] as? String
        if domain == nil, let origin = properties[.originURL] as? URL { domain = origin.host }
        guard let domain else { return nil }
        self.properties = properties
        self.name = name
        self.value = value
        self.domain = domain
        self.path = path
        if let date = properties[.expires] as? Date { expiresDate = date }
        else if let seconds = properties[.maximumAge] as? String, let age = Double(seconds) { expiresDate = Date(timeIntervalSinceNow: age) }
        else { expiresDate = nil }
        isSessionOnly = expiresDate == nil && (properties[.discard] as? String)?.uppercased() != "FALSE"
        isSecure = Self.flag(properties[.secure])
        isHTTPOnly = Self.flag(properties[.init("HttpOnly")])
        comment = properties[.comment] as? String
        commentURL = properties[.commentURL] as? URL
        portList = (properties[.port] as? String)?.split(separator: ",").compactMap { Int($0) }
        version = Int(properties[.version] as? String ?? "0") ?? 0
        sameSitePolicy = (properties[.sameSitePolicy] as? String).map(HTTPCookieStringPolicy.init(rawValue:))
    }

    private static func flag(_ value: Any?) -> Bool {
        if let string = value as? String { return string.uppercased() == "TRUE" || string == "1" }
        return value as? Bool ?? false
    }

    /// Cookies from a response's `Set-Cookie` headers.
    public static func cookies(withResponseHeaderFields headerFields: [String: String], for URL: URL) -> [HTTPCookie] {
        var cookies: [HTTPCookie] = []
        for (field, value) in headerFields where field.lowercased() == "set-cookie" {
            for header in value.split(separator: "\n") {
                var properties: [HTTPCookiePropertyKey: Any] = [.originURL: URL, .domain: URL.host ?? "", .path: "/"]
                for (index, part) in header.split(separator: ";").enumerated() {
                    let trimmed = part.drop(while: { $0 == " " })
                    let key: Substring, item: Substring
                    if let equals = trimmed.firstIndex(of: "=") { key = trimmed[..<equals]; item = trimmed[trimmed.index(after: equals)...] }
                    else { key = trimmed; item = "" }
                    if index == 0 { properties[.name] = String(key); properties[.value] = String(item); continue }
                    switch key.lowercased() {
                    case "domain": properties[.domain] = String(item.hasPrefix(".") ? item.dropFirst() : item)
                    case "path": properties[.path] = String(item)
                    case "max-age": properties[.maximumAge] = String(item)
                    case "secure": properties[.secure] = "TRUE"
                    case "httponly": properties[.init("HttpOnly")] = "TRUE"
                    case "samesite": properties[.sameSitePolicy] = String(item)
                    default: break
                    }
                }
                if let cookie = HTTPCookie(properties: properties) { cookies.append(cookie) }
            }
        }
        return cookies
    }

    /// The `Cookie` header for the cookies.
    public static func requestHeaderFields(with cookies: [HTTPCookie]) -> [String: String] {
        cookies.isEmpty ? [:] : ["Cookie": cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")]
    }

    /// Whether the cookie applies to the URL: its domain is the host or a parent of it, its path a prefix.
    func matches(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        let domain = self.domain.lowercased()
        let domainMatches = host == domain || host.hasSuffix("." + domain) || domain.hasPrefix(".") && host.hasSuffix(domain)
        guard domainMatches else { return false }
        let urlPath = url.path.isEmpty ? "/" : url.path
        return urlPath.hasPrefix(path)
    }

    public static func == (lhs: HTTPCookie, rhs: HTTPCookie) -> Bool {
        lhs.name == rhs.name && lhs.domain.lowercased() == rhs.domain.lowercased() && lhs.path == rhs.path
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(name)
        hasher.combine(domain.lowercased())
        hasher.combine(path)
    }

    public var description: String { "<HTTPCookie \(name)=\(value) domain=\(domain) path=\(path)>" }
}

public struct HTTPCookiePropertyKey: RawRepresentable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ rawValue: String) { self.rawValue = rawValue }

    public static let comment = HTTPCookiePropertyKey("Comment")
    public static let commentURL = HTTPCookiePropertyKey("CommentURL")
    public static let discard = HTTPCookiePropertyKey("Discard")
    public static let domain = HTTPCookiePropertyKey("Domain")
    public static let expires = HTTPCookiePropertyKey("Expires")
    public static let maximumAge = HTTPCookiePropertyKey("Max-Age")
    public static let name = HTTPCookiePropertyKey("Name")
    public static let originURL = HTTPCookiePropertyKey("OriginURL")
    public static let path = HTTPCookiePropertyKey("Path")
    public static let port = HTTPCookiePropertyKey("Port")
    public static let secure = HTTPCookiePropertyKey("Secure")
    public static let value = HTTPCookiePropertyKey("Value")
    public static let version = HTTPCookiePropertyKey("Version")
    public static let sameSitePolicy = HTTPCookiePropertyKey("SameSite")
}

public struct HTTPCookieStringPolicy: RawRepresentable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let sameSiteLax = HTTPCookieStringPolicy(rawValue: "Lax")
    public static let sameSiteStrict = HTTPCookieStringPolicy(rawValue: "Strict")
}

/// A container that manages the storage of cookies.
public final class HTTPCookieStorage: @unchecked Sendable {
    public enum AcceptPolicy: UInt, Sendable {
        case always = 0
        case never = 1
        case onlyFromMainDocumentDomain = 2
    }

    /// The shared cookie storage: the app's own cookies, kept for the page's lifetime.
    public static let shared = HTTPCookieStorage()

    private var stored: [HTTPCookie] = []
    public var cookieAcceptPolicy: AcceptPolicy = .onlyFromMainDocumentDomain

    public init() {}

    public static func sharedCookieStorage(forGroupContainerIdentifier identifier: String) -> HTTPCookieStorage { shared }

    /// Every cookie, expired ones dropped.
    public var cookies: [HTTPCookie]? {
        let now = Date()
        stored.removeAll { cookie in cookie.expiresDate.map { $0 < now } ?? false }
        return stored
    }

    public func cookies(for URL: URL) -> [HTTPCookie]? {
        cookies?.filter { $0.matches(URL) }
    }

    /// Stores a cookie, replacing one with the same name, domain and path.
    public func setCookie(_ cookie: HTTPCookie) {
        guard cookieAcceptPolicy != .never else { return }
        stored.removeAll { $0 == cookie }
        stored.append(cookie)
    }

    public func setCookies(_ cookies: [HTTPCookie], for URL: URL?, mainDocumentURL: URL?) {
        for cookie in cookies { setCookie(cookie) }
    }

    public func deleteCookie(_ cookie: HTTPCookie) {
        stored.removeAll { $0 == cookie }
    }

    public func removeCookies(since date: Date) {
        stored.removeAll()
    }
}
#endif
