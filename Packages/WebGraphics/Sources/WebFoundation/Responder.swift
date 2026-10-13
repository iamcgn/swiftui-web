// Stand-ins for the Foundation types the frameworks' keyboard and command API names, which
// FoundationEssentials lacks on wasm: `CharacterSet` (predicate-based: the named sets, a set of
// characters, unions and inversion), `Selector` (a command name, as `#selector` has no runtime
// to resolve against) and `NSItemProvider` carrying a string. Linux also needs the latter two;
// Apple platforms use Foundation's declarations.
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

#endif

#if !canImport(ObjectiveC)

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

    #if !os(WASI)
    /// Foundation clients commonly pass NSString, as Apple's NSItemProvider requires.
    public convenience init(object: NSString) { self.init(object: object as String) }
    #endif

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

#if os(WASI)
// MARK: - NSObject (decision 0021: the Countries app subclasses it for its notification
// delegate; `super.init()`, identity equality, a hash and a description)

/// The protocol the root class conforms to.
public protocol NSObjectProtocol: AnyObject {
    func isEqual(_ object: Any?) -> Bool
    var hash: Int { get }
    var description: String { get }
}

/// The root class of most Objective-C class hierarchies, without the runtime: identity
/// equality and hashing, overridable, as apps subclass it for delegates.
open class NSObject: NSObjectProtocol, Hashable, CustomStringConvertible {
    public init() {}
    open func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? NSObject else { return false }
        return other === self
    }
    open var hash: Int { ObjectIdentifier(self).hashValue }
    open var description: String { "<\(type(of: self))>" }
    open var debugDescription: String { description }
    public static func == (lhs: NSObject, rhs: NSObject) -> Bool { lhs.isEqual(rhs) }
    public func hash(into hasher: inout Hasher) { hasher.combine(hash) }
    open class var description: String { "\(self)" }
    public func isKind(of aClass: AnyClass) -> Bool { type(of: self) == aClass }
    public func isMember(of aClass: AnyClass) -> Bool { type(of: self) == aClass }
}

// MARK: - Percent encoding with the URL character sets

extension CharacterSet {
    private static let unreserved = CharacterSet { $0.isASCII && ($0.properties.isAlphabetic || ("0"..."9").contains($0) || "-._~".unicodeScalars.contains($0)) }
    private static func allowed(_ extra: String) -> CharacterSet { unreserved.union(CharacterSet(charactersIn: extra)) }
    /// The sets `URLComponents` allows in each part (RFC 3986 as Foundation applies it).
    public static let urlQueryAllowed = allowed("!$&'()*+,;=:@/?")
    public static let urlPathAllowed = allowed("!$&'()*+,;=:@/")
    public static let urlHostAllowed = allowed("!$&'()*+,;=:[]")
    public static let urlUserAllowed = allowed("!$&'()*+,;=")
    public static let urlPasswordAllowed = allowed("!$&'()*+,;=")
    public static let urlFragmentAllowed = allowed("!$&'()*+,;=:@/?")
}

extension StringProtocol {
    /// The string with every byte of a scalar outside `allowedCharacters` as `%XX`.
    public func addingPercentEncoding(withAllowedCharacters allowedCharacters: CharacterSet) -> String? {
        var result = ""
        for scalar in String(self).unicodeScalars {
            if allowedCharacters.contains(scalar) {
                result.unicodeScalars.append(scalar)
            } else {
                for byte in String(scalar).utf8 { result += "%" + String(byte, radix: 16, uppercase: true).leftPadded(to: 2) }
            }
        }
        return result
    }

    /// The string with its `%XX` escapes decoded; nil when a sequence is not valid UTF-8.
    public var removingPercentEncoding: String? {
        var bytes: [UInt8] = []
        var iterator = String(self).utf8.makeIterator()
        while let byte = iterator.next() {
            if byte == UInt8(ascii: "%") {
                guard let high = iterator.next(), let low = iterator.next(),
                      let value = UInt8(String(decoding: [high, low], as: UTF8.self), radix: 16) else { return nil }
                bytes.append(value)
            } else {
                bytes.append(byte)
            }
        }
        return String(validating: bytes, as: UTF8.self)
    }
}

extension String {
    fileprivate func leftPadded(to width: Int) -> String { count >= width ? self : String(repeating: "0", count: width - count) + self }
}
#endif
