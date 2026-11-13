// Foundation's `Bundle` on wasm (decision 0021): FoundationEssentials has none. The app is one
// bundle whose resources are the files `scripts/assets.py` copied beside the module (asset
// catalogs by name; a package target's processed resources under the target's name), so a
// bundle made from any path answers for the app, and `Bundle.module` (SwiftPM's generated
// accessor extends `Foundation.Bundle` with it) resolves. Resource URLs are relative to the page.
#if os(WASI)
open class Bundle: _WebObjectBase, @unchecked Sendable {
    /// The app's bundle.
    public static let main = Bundle(_path: "/")

    public let bundlePath: String
    public var bundleURL: URL { URL(fileURLWithPath: bundlePath) }
    public var resourcePath: String? { bundlePath }
    public var resourceURL: URL? { bundleURL }
    /// The App Store receipt: none on the web, where nothing was bought from the App Store.
    public var appStoreReceiptURL: URL? { nil }
    public var bundleIdentifier: String? { Bundle._identifier }
    public var infoDictionary: [String: Any]? { Bundle._info }
    /// The app's languages, from its string catalogs and `.lproj` folders as the bundle's build
    /// recorded them (`scripts/assets.py`, the manifest; the browser host installs them).
    nonisolated(unsafe) public static var _hostLocalizations: (languages: [String], source: String?)?

    /// The localizations the bundle holds, as on iOS: every language of its string catalogs
    /// and `.lproj` folders (EnvironmentOverrides builds its locale picker from them, decision
    /// 0021); the development language alone when the build recorded none.
    public var localizations: [String] {
        let recorded = Self._hostLocalizations?.languages ?? []
        return recorded.isEmpty ? [developmentLocalization ?? "en"] : recorded
    }

    /// The catalogs' source language (`en` without catalogs).
    public var developmentLocalization: String? { Self._hostLocalizations?.source ?? "en" }

    /// The bundle's languages the user prefers, best first: the current locale's language
    /// where the bundle has it (a region-specific tag or its language), else the development one.
    public var preferredLocalizations: [String] {
        let current = Locale.current
        let identifier = current.identifier.replacingOccurrences(of: "_", with: "-")
        let language = current.languageCode ?? "en"
        let held = localizations
        if held.contains(identifier) { return [identifier] }
        if let match = held.first(where: { $0 == language || $0.hasPrefix(language + "-") }) { return [match] }
        return [developmentLocalization ?? held.first ?? "en"]
    }

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

    /// Whether the bundle's executable code is loaded. The app's code is all in its one wasm
    /// module, which is running, so the main bundle's is; no other bundle has code on the web.
    public var isLoaded: Bool { bundlePath == Bundle.main.bundlePath }

    /// Loads the bundle's executable code. A page can't load code from another bundle, so this
    /// answers `true` for the app's own (already loaded) and `false` for any other, as a bundle
    /// whose code fails to load does on iOS (Inject's `InjectionIII` bundle in a debug build).
    @discardableResult
    open func load() -> Bool { isLoaded }

    /// Unloads the bundle's code: nothing a page loaded can be unloaded, so `false`.
    open func unload() -> Bool { false }

    /// Loads the bundle's code, throwing `NSExecutableLoadError` (3587) where `load()` answers `false`.
    open func loadAndReturnError() throws {
        guard load() else { throw NSError(domain: NSCocoaErrorDomain, code: 3587, userInfo: [NSFilePathErrorKey: bundlePath]) }
    }

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
