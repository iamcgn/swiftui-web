// The locale's lists of codes and the names of languages and regions on wasm. Names come from
// the browser's `Intl.DisplayNames` through `Locale._hostDisplayName` (nil where the host
// hasn't set it or doesn't know the code). The lists are the ISO 639-1 languages and the
// ISO 3166-1 regions; Apple's lists add some three-letter languages.
#if os(WASI)
import WebFoundation

extension Locale {
    /// A locale for a language, script and region ("zh-Hans_CN").
    public init(languageComponents: Language.Components) {
        var identifier = languageComponents.languageCode?.identifier ?? ""
        if let script = languageComponents.script { identifier += (identifier.isEmpty ? "" : "-") + script.identifier }
        if let region = languageComponents.region { identifier += "_" + region.identifier }
        self.init(identifier: identifier)
    }

    public init(languageCode: LanguageCode? = nil, script: Script? = nil, languageRegion: Region? = nil) {
        self.init(languageComponents: Language.Components(languageCode: languageCode, script: script, region: languageRegion))
    }

    /// A locale's parts: its language, script and region, and the region it's used in
    /// ("en" used in "GB"). The keyword preferences Apple's carries (calendar, currency,
    /// measurement and the like) aren't kept here.
    public struct Components: Hashable, Sendable, Codable {
        public var languageComponents: Language.Components
        /// The region the locale is used in, when it differs from its language's region.
        public var region: Region?

        public init(languageCode: LanguageCode? = nil, script: Script? = nil, languageRegion: Region? = nil) {
            languageComponents = Language.Components(languageCode: languageCode, script: script, region: languageRegion)
            region = nil
        }

        public init(identifier: String) {
            languageComponents = Language.Components(identifier: identifier)
            region = nil
        }

        public init(locale: Locale) {
            self.init(identifier: locale.identifier)
        }
    }

    /// A locale made of parts ("_US" for a region alone, "zh-Hans_CN").
    public init(components: Components) {
        var parts = components.languageComponents
        if let region = components.region { parts.region = region }
        self.init(languageComponents: parts)
    }

    private var _bcp47: String { String(identifier.map { $0 == "_" ? "-" : $0 }) }

    /// The name of a language in this locale's language ("French" in en_US, "français" in fr).
    public func localizedString(forLanguageCode languageCode: String) -> String? {
        Locale._hostDisplayName?(_bcp47, "language", languageCode)
    }
    public func localizedString(forRegionCode regionCode: String) -> String? {
        Locale._hostDisplayName?(_bcp47, "region", regionCode)
    }
    public func localizedString(forScriptCode scriptCode: String) -> String? {
        Locale._hostDisplayName?(_bcp47, "script", scriptCode)
    }
    /// The name of a whole locale identifier ("English (United States)").
    public func localizedString(forIdentifier identifier: String) -> String? {
        Locale._hostDisplayName?(_bcp47, "language", identifier)
    }

    public static var isoLanguageCodes: [String] { _isoLanguages }
    public static var isoRegionCodes: [String] { _isoRegions }
}

extension Locale.LanguageCode {
    public static var isoLanguageCodes: [Locale.LanguageCode] { Locale._isoLanguages.map { Locale.LanguageCode($0) } }
}

extension Locale.Region {
    public static var isoRegions: [Locale.Region] { Locale._isoRegions.map { Locale.Region($0) } }
}

extension Locale.Currency {
    /// The currencies of the regions the locale table knows.
    public static var isoCurrencies: [Locale.Currency] {
        Set(Locale._currencies.values).sorted().map { Locale.Currency($0) }
    }
}

extension Locale {
    /// The currency of the locale's region ("USD" for en_US).
    public var currency: Currency? { currencyCode.map { Currency($0) } }
}
#endif
