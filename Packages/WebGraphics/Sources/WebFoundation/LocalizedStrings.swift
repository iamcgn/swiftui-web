// `String(localized:)` and `LocalizedStringResource` on wasm, where FoundationEssentials has
// neither (Docs/coverage.md: `localized:` is an extraneous label in 7 apps, the resource type
// is missing in 4). Both look the key up in the bundle's string tables the way
// `Bundle.localizedString(forKey:value:table:)` does, falling back to the default value and
// then to the key. The key of an interpolated literal is its text with the values in place
// (Foundation's turns the values into format specifiers and substitutes after the lookup, so a
// table entry keyed `"%lld items"` is not found here: the English text shows).
#if os(WASI)

extension String {
    /// Creates a localized string from a localization key and its default value.
    public init(localized keyAndValue: String, table: String? = nil, bundle: Bundle? = nil, locale: Locale = .current, comment: StaticString? = nil) {
        self = (bundle ?? .main).localizedString(forKey: keyAndValue, value: keyAndValue, table: table)
    }

    /// Creates a localized string from a static key, with a default value for when the tables
    /// have none.
    public init(localized key: StaticString, defaultValue: String, table: String? = nil, bundle: Bundle? = nil, locale: Locale = .current, comment: StaticString? = nil) {
        self = (bundle ?? .main).localizedString(forKey: "\(key)", value: defaultValue, table: table)
    }

    /// Creates a string from a localized string resource.
    public init(localized resource: LocalizedStringResource) {
        self = resource.resolved
    }
}

/// A reference to a localizable string, accessible from another process.
public struct LocalizedStringResource: Hashable, Sendable, Codable, CustomStringConvertible,
                                       ExpressibleByStringLiteral, ExpressibleByStringInterpolation {
    /// Where a resource's strings are looked up.
    public enum BundleDescription: Hashable, Sendable, Codable {
        case main
        case atURL(URL)
        /// A framework's bundle by the path it was built at; resolved like the main bundle here.
        case forClassPath(String)
    }

    public var key: String
    public var defaultValue: String
    public var table: String?
    public var locale: Locale
    public var bundle: BundleDescription

    public init(_ keyAndValue: String, table: String? = nil, locale: Locale = .current, bundle: BundleDescription = .main, comment: StaticString? = nil) {
        key = keyAndValue
        defaultValue = keyAndValue
        self.table = table
        self.locale = locale
        self.bundle = bundle
    }

    public init(_ key: StaticString, defaultValue: String, table: String? = nil, locale: Locale = .current, bundle: BundleDescription = .main, comment: StaticString? = nil) {
        self.key = "\(key)"
        self.defaultValue = defaultValue
        self.table = table
        self.locale = locale
        self.bundle = bundle
    }

    public init(stringLiteral value: String) { self.init(value) }
    public init(stringInterpolation: DefaultStringInterpolation) { self.init(String(stringInterpolation: stringInterpolation)) }

    /// The string the tables give the key, else the default value.
    var resolved: String { Bundle.main.localizedString(forKey: key, value: defaultValue, table: table) }

    public var description: String { resolved }

    public static func == (lhs: LocalizedStringResource, rhs: LocalizedStringResource) -> Bool {
        lhs.key == rhs.key && lhs.defaultValue == rhs.defaultValue && lhs.table == rhs.table && lhs.bundle == rhs.bundle
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(key)
        hasher.combine(table)
    }

    private enum CodingKeys: String, CodingKey { case key, defaultValue, table, bundle }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = try container.decode(String.self, forKey: .key)
        defaultValue = try container.decodeIfPresent(String.self, forKey: .defaultValue) ?? key
        table = try container.decodeIfPresent(String.self, forKey: .table)
        bundle = try container.decodeIfPresent(BundleDescription.self, forKey: .bundle) ?? .main
        locale = .current
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(key, forKey: .key)
        try container.encode(defaultValue, forKey: .defaultValue)
        try container.encodeIfPresent(table, forKey: .table)
        try container.encode(bundle, forKey: .bundle)
    }
}
#endif
