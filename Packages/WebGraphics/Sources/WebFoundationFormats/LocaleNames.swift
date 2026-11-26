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

    /// The name of a currency in this locale's language ("Euro" in en_US).
    public func localizedString(forCurrencyCode currencyCode: String) -> String? {
        Locale._hostDisplayName?(_bcp47, "currency", currencyCode)
    }

    public static var isoLanguageCodes: [String] { _isoLanguages }
    public static var isoRegionCodes: [String] { _isoRegions }
    /// The ISO 4217 codes of the regions' currencies the locale table knows.
    public static var isoCurrencyCodes: [String] { Locale.Currency.isoCurrencies.map(\.identifier) }
    /// The currencies in common use: here, the same list.
    public static var commonISOCurrencyCodes: [String] { isoCurrencyCodes }

    /// An identifier from its parts, keyed as `NSLocale.Key` names them: the language, script,
    /// region and variant, then the other keywords after "@", sorted ("de_DE@currency=EUR").
    public static func identifier(fromComponents components: [String: String]) -> String {
        var identifier = components[_LocaleKey.languageCode] ?? ""
        for key in [_LocaleKey.scriptCode, _LocaleKey.countryCode, _LocaleKey.variantCode] {
            if let part = components[key], !part.isEmpty { identifier += "_" + part }
        }
        let core: Set<String> = [_LocaleKey.languageCode, _LocaleKey.scriptCode, _LocaleKey.countryCode, _LocaleKey.variantCode, _LocaleKey.identifier]
        let keywords = components.filter { !core.contains($0.key) }.sorted { $0.key < $1.key }
        if !keywords.isEmpty { identifier += "@" + keywords.map { $0.key + "=" + $0.value }.joined(separator: ";") }
        return identifier
    }

    /// The parts of an identifier, keyed as `identifier(fromComponents:)` reads them.
    public static func components(fromIdentifier string: String) -> [String: String] {
        var result: [String: String] = [:]
        var base = Substring(string)
        if let at = string.firstIndex(of: "@") {
            base = string[..<at]
            for pair in string[string.index(after: at)...].split(separator: ";") {
                guard let equals = pair.firstIndex(of: "=") else { continue }
                result[String(pair[..<equals])] = String(pair[pair.index(after: equals)...])
            }
        }
        let parts = base.split(separator: "_", omittingEmptySubsequences: false).flatMap { $0.split(separator: "-", omittingEmptySubsequences: false) }
        guard let language = parts.first else { return result }
        if !language.isEmpty { result[_LocaleKey.languageCode] = String(language) }
        var rest = parts.dropFirst()
        if let script = rest.first, script.count == 4 { result[_LocaleKey.scriptCode] = String(script); rest = rest.dropFirst() }
        if let region = rest.first, !region.isEmpty { result[_LocaleKey.countryCode] = String(region); rest = rest.dropFirst() }
        if let variant = rest.first, !variant.isEmpty { result[_LocaleKey.variantCode] = String(variant) }
        return result
    }
}

/// The keys of a locale's parts, as Foundation spells `NSLocale.Key`'s raw values.
enum _LocaleKey {
    static let identifier = "kCFLocaleIdentifierKey"
    static let languageCode = "kCFLocaleLanguageCodeKey"
    static let countryCode = "kCFLocaleCountryCodeKey"
    static let scriptCode = "kCFLocaleScriptCodeKey"
    static let variantCode = "kCFLocaleVariantCodeKey"
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
