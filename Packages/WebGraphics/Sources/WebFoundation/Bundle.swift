// Foundation's `Bundle` on wasm (decision 0021): FoundationEssentials has none. The app is one
// bundle whose resources are the files `scripts/assets.py` copied beside the module (asset
// catalogs by name; a package target's processed resources under the target's name), so a
// bundle made from any path answers for the app, and `Bundle.module` (SwiftPM's generated
// accessor extends `Foundation.Bundle` with it) resolves. Resource URLs are relative to the page.
#if os(WASI)
open class Bundle: @unchecked Sendable {
    /// The app's bundle.
    public static let main = Bundle(_path: "/")

    public let bundlePath: String
    public var bundleURL: URL { URL(fileURLWithPath: bundlePath) }
    public var resourcePath: String? { bundlePath }
    public var resourceURL: URL? { bundleURL }
    public var bundleIdentifier: String? { Bundle._identifier }
    public var infoDictionary: [String: Any]? { Bundle._info }
    public var preferredLocalizations: [String] { [Locale.current.languageCode ?? "en"] }

    /// The identifier and Info dictionary the host installs (`CFBundleName` and friends).
    nonisolated(unsafe) public static var _identifier: String?
    nonisolated(unsafe) public static var _info: [String: Any]?
    /// Where a resource of the app lives relative to the page (the host's assets directory).
    nonisolated(unsafe) public static var _resourceBase = "assets/"

    public required init(_path path: String) { bundlePath = path }
    public convenience init?(path: String) { self.init(_path: path) }
    public convenience init?(url: URL) { self.init(_path: url.path) }
    public convenience init(for aClass: AnyClass) { self.init(_path: "/") }
    public convenience init?(identifier: String) { self.init(_path: "/") }

    public func object(forInfoDictionaryKey key: String) -> Any? { infoDictionary?[key] }

    /// The URL of a resource beside the app's assets: `assets/<name>.<ext>`.
    public func url(forResource name: String?, withExtension ext: String?) -> URL? {
        url(forResource: name, withExtension: ext, subdirectory: nil)
    }
    public func url(forResource name: String?, withExtension ext: String?, subdirectory: String?) -> URL? {
        guard let name else { return nil }
        var path = Bundle._resourceBase
        if let subdirectory, !subdirectory.isEmpty { path += subdirectory + "/" }
        path += name
        if let ext, !ext.isEmpty { path += "." + ext }
        return URL(string: path)
    }
    public func path(forResource name: String?, ofType ext: String?) -> String? {
        url(forResource: name, withExtension: ext)?.relativeString
    }
    public func urls(forResourcesWithExtension ext: String?, subdirectory: String?) -> [URL]? { [] }

    /// Localized strings: the key itself (or `value`), as a bundle without tables answers.
    public func localizedString(forKey key: String, value: String?, table: String?) -> String {
        if let value, !value.isEmpty { return value }
        return key
    }
}
#endif
