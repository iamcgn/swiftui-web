// `PersonNameComponents`, which FoundationEssentials lacks on wasm (it lives with ICU's
// formatters): the parts of a person's name, as Sign in with Apple's credential and contact
// forms carry them. Formatting joins the parts in the English order ("Dr. Jane Q. Appleseed Jr."
// in the long style, "Jane Appleseed" by default, "JA" abbreviated).
#if os(WASI)

public struct PersonNameComponents: Hashable, Codable, Sendable, CustomStringConvertible {
    public var namePrefix: String?
    public var givenName: String?
    public var middleName: String?
    public var familyName: String?
    public var nameSuffix: String?
    public var nickname: String?
    /// The name as it sounds, for names whose spelling does not say.
    public var phoneticRepresentation: PersonNameComponents? {
        get { _phonetic?.first }
        set { _phonetic = newValue.map { [$0] } }
    }
    private var _phonetic: [PersonNameComponents]?

    public init() {}

    public init(namePrefix: String? = nil, givenName: String? = nil, middleName: String? = nil, familyName: String? = nil,
                nameSuffix: String? = nil, nickname: String? = nil, phoneticRepresentation: PersonNameComponents? = nil) {
        self.namePrefix = namePrefix
        self.givenName = givenName
        self.middleName = middleName
        self.familyName = familyName
        self.nameSuffix = nameSuffix
        self.nickname = nickname
        self.phoneticRepresentation = phoneticRepresentation
    }

    /// How much of the name a formatted name shows.
    public enum _Style: Sendable { case short, medium, long, abbreviated }

    /// The given and family names ("Jane Appleseed").
    public func formatted() -> String { _formatted(.medium) }

    public func _formatted(_ style: _Style) -> String {
        func join(_ parts: [String?]) -> String { parts.compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ") }
        switch style {
        case .short: return join([nickname ?? givenName ?? familyName])
        case .medium: return join([givenName, familyName])
        case .long: return join([namePrefix, givenName, middleName, familyName, nameSuffix])
        case .abbreviated: return [givenName, familyName].compactMap { $0?.first.map(String.init) }.joined()
        }
    }

    public var description: String { _formatted(.long) }
}
#endif
