// Stand-ins for the Foundation types the frameworks' keyboard and command API names, which
// FoundationEssentials lacks on wasm: `CharacterSet` (predicate-based: the named sets, a set of
// characters, unions and inversion), `Selector` (a command name, as `#selector` has no runtime
// to resolve against) and `NSItemProvider` carrying a string. Apple platforms use Foundation's.
#if os(WASI)

/// A set of Unicode scalars, by predicate.
public struct CharacterSet: @unchecked Sendable {
    private let predicate: (Unicode.Scalar) -> Bool

    public init() { predicate = { _ in false } }
    private init(_ predicate: @escaping (Unicode.Scalar) -> Bool) { self.predicate = predicate }

    /// The scalars of `string`.
    public init(charactersIn string: String) {
        let scalars = Set(string.unicodeScalars)
        predicate = { scalars.contains($0) }
    }

    public func contains(_ member: Unicode.Scalar) -> Bool { predicate(member) }

    public var inverted: CharacterSet { CharacterSet { !self.predicate($0) } }
    public func union(_ other: CharacterSet) -> CharacterSet { CharacterSet { self.predicate($0) || other.predicate($0) } }
    public func intersection(_ other: CharacterSet) -> CharacterSet { CharacterSet { self.predicate($0) && other.predicate($0) } }
    public func subtracting(_ other: CharacterSet) -> CharacterSet { CharacterSet { self.predicate($0) && !other.predicate($0) } }
    public mutating func insert(charactersIn string: String) { self = union(CharacterSet(charactersIn: string)) }
    public mutating func formUnion(_ other: CharacterSet) { self = union(other) }
    public func isSuperset(of other: CharacterSet) -> Bool { false }

    public static let letters = CharacterSet { $0.properties.isAlphabetic }
    public static let uppercaseLetters = CharacterSet { $0.properties.isUppercase }
    public static let lowercaseLetters = CharacterSet { $0.properties.isLowercase }
    public static let decimalDigits = CharacterSet { $0.properties.generalCategory == .decimalNumber }
    public static let alphanumerics = CharacterSet { $0.properties.isAlphabetic || $0.properties.numericType != nil }
    public static let whitespaces = CharacterSet { $0.properties.isWhitespace && $0 != "\n" && $0 != "\r" }
    public static let newlines = CharacterSet { ["\n", "\r", "\u{85}", "\u{2028}", "\u{2029}", "\u{0B}", "\u{0C}"].contains($0) }
    public static let whitespacesAndNewlines = CharacterSet { $0.properties.isWhitespace }
    public static let punctuationCharacters = CharacterSet {
        switch $0.properties.generalCategory {
        case .connectorPunctuation, .dashPunctuation, .openPunctuation, .closePunctuation, .initialPunctuation, .finalPunctuation, .otherPunctuation: return true
        default: return false
        }
    }
    public static let symbols = CharacterSet {
        switch $0.properties.generalCategory {
        case .mathSymbol, .currencySymbol, .modifierSymbol, .otherSymbol: return true
        default: return false
        }
    }
    public static let controlCharacters = CharacterSet { $0.properties.generalCategory == .control }
}

/// A command name (`onCommand`); `#selector` needs an Objective-C runtime, so commands are
/// named by their selector string ("copy:", "selectAll:").
public struct Selector: Hashable, Sendable, ExpressibleByStringLiteral, CustomStringConvertible {
    public let name: String
    public init(_ name: String) { self.name = name }
    public init(stringLiteral value: String) { self.name = value }
    public var description: String { name }
}

/// An item for the pasteboard commands: a string, or a value with a type identifier.
public final class NSItemProvider: @unchecked Sendable {
    public private(set) var registeredTypeIdentifiers: [String] = []
    private var items: [String: Any] = [:]

    public init() {}

    /// An item carrying `object` (a string registers as UTF-8 plain text).
    public convenience init(object: String) {
        self.init()
        registerItem(object, typeIdentifier: "public.utf8-plain-text")
    }

    public convenience init(item: Any?, typeIdentifier: String?) {
        self.init()
        if let item, let typeIdentifier { registerItem(item, typeIdentifier: typeIdentifier) }
    }

    public func registerItem(_ item: Any, typeIdentifier: String) {
        items[typeIdentifier] = item
        registeredTypeIdentifiers.append(typeIdentifier)
    }

    public func hasItemConformingToTypeIdentifier(_ typeIdentifier: String) -> Bool {
        registeredTypeIdentifiers.contains(typeIdentifier)
            || (_textTypeIdentifiers.contains(typeIdentifier) && registeredTypeIdentifiers.contains(where: _textTypeIdentifiers.contains))
    }

    /// The item registered for `typeIdentifier`, delivered at once.
    public func loadItem(forTypeIdentifier typeIdentifier: String, options: [AnyHashable: Any]? = nil, completionHandler: ((Any?, Error?) -> Void)?) {
        completionHandler?(items[typeIdentifier] ?? (_textTypeIdentifiers.contains(typeIdentifier) ? _text : nil), nil)
    }

    /// The string the item carries, if any.
    public var _text: String? {
        for identifier in registeredTypeIdentifiers where _textTypeIdentifiers.contains(identifier) {
            if let text = items[identifier] as? String { return text }
        }
        return nil
    }
}

private let _textTypeIdentifiers: Set<String> = ["public.utf8-plain-text", "public.plain-text", "public.text"]

#endif
