// Foundation's `AttributedString` on wasm (decision 0017): FoundationEssentials there has none.
// Runs of characters with attribute containers, the attribute-key protocol and scopes that the
// SwiftUI module extends (`AttributeScopes.SwiftUIAttributes`), dynamic member lookup on
// containers, runs and substrings, and `init(markdown:)` through `_InlineMarkdown`.
// `AttributedStringProtocol` is Foundation's shape: attributes a whole string or slice shares,
// scoped containers (`text.uiKit`), any range expression, merge policies and attribute
// replacement, so a type of an app's own conforms as on Apple's (EmojiText's partial string).
#if os(WASI)
import FoundationEssentials

/// A key for an attribute of an attributed string.
public protocol AttributedStringKey {
    associatedtype Value: Hashable & Sendable
    static var name: String { get }
    /// `object`, an `NSAttributedString` attribute's value, as this key's value (an underline
    /// style's raw number as the style); nil when it is not one.
    static func _webValue(of object: Any) -> _AttributeValue?
}

/// A hashable box for an attribute value.
public struct _AttributeValue: Hashable, @unchecked Sendable {
    public let base: AnyHashable
    public init<T: Hashable>(_ value: T) { base = AnyHashable(value) }
    public func value<T>(as type: T.Type) -> T? { base.base as? T }
}

/// The namespaces of attribute keys: Foundation's, and whatever modules add.
public enum AttributeScopes {
    public struct FoundationAttributes {
        // Key paths name the keys; the scope is never instantiated.
        public let link: LinkAttribute
        public let inlinePresentationIntent: InlinePresentationIntentAttribute
        public let languageIdentifier: LanguageIdentifierAttribute

        public enum LinkAttribute: AttributedStringKey {
            public typealias Value = URL
            public static let name = "NSLink"
        }
        public enum InlinePresentationIntentAttribute: AttributedStringKey {
            public typealias Value = InlinePresentationIntent
            public static let name = "NSInlinePresentationIntent"
        }
        public enum LanguageIdentifierAttribute: AttributedStringKey {
            public typealias Value = String
            public static let name = "NSLanguage"
        }
    }

    public var foundation: FoundationAttributes.Type { FoundationAttributes.self }
}

/// Resolves `container.link`, `run.font` and the like: a key path into a scope names the key.
@dynamicMemberLookup
public final class AttributeDynamicLookup {
    public subscript<T: AttributedStringKey>(_ key: T.Type) -> T { fatalError("a key type, never instantiated") }
    public subscript<T: AttributedStringKey>(dynamicMember keyPath: KeyPath<AttributeScopes.FoundationAttributes, T>) -> T { self[T.self] }
}

/// The attributes applied to a stretch of text, by key name.
@dynamicMemberLookup
public struct AttributeContainer: Hashable, Sendable {
    public var storage: [String: _AttributeValue] = [:]

    public init() {}

    public subscript<K: AttributedStringKey>(_ key: K.Type) -> K.Value? {
        get { storage[K.name]?.value(as: K.Value.self) }
        set { storage[K.name] = newValue.map { _AttributeValue($0) } }
    }

    public subscript<K: AttributedStringKey>(dynamicMember keyPath: KeyPath<AttributeDynamicLookup, K>) -> K.Value? {
        get { self[K.self] }
        set { self[K.self] = newValue }
    }

    /// A scope's view of the attributes (`container.uiKit.foregroundColor = .red`).
    public subscript<S: AttributeScope>(dynamicMember keyPath: KeyPath<AttributeScopes, S.Type>) -> ScopedAttributeContainer<S> {
        get { ScopedAttributeContainer(self) }
        set { self = newValue._container }
    }

    /// Adds `other`'s attributes; where both set one, `mergePolicy` decides which value stays.
    public mutating func merge(_ other: AttributeContainer, mergePolicy: AttributedString.AttributeMergePolicy = .keepNew) {
        for (key, value) in other.storage where mergePolicy == .keepNew || storage[key] == nil { storage[key] = value }
    }

    public func merging(_ other: AttributeContainer, mergePolicy: AttributedString.AttributeMergePolicy = .keepNew) -> AttributeContainer {
        var result = self
        result.merge(other, mergePolicy: mergePolicy)
        return result
    }

    /// The attributes `new` changes from `old` set here, and those it dropped removed, as are
    /// those `cleared` names (set to nil where their value varied, so `old` never had them).
    mutating func _apply(_ new: AttributeContainer, over old: AttributeContainer, cleared: Set<String> = []) {
        for (key, value) in new.storage where old.storage[key] != value { storage[key] = value }
        for key in old.storage.keys where new.storage[key] == nil { storage[key] = nil }
        for key in cleared where new.storage[key] == nil { storage[key] = nil }
    }

    /// When every one of `attributes` is here with its value: those taken off, `others` merged in.
    mutating func _replace(_ attributes: AttributeContainer, with others: AttributeContainer) {
        guard attributes.storage.allSatisfy({ storage[$0.key] == $0.value }) else { return }
        for key in attributes.storage.keys { storage[key] = nil }
        merge(others)
    }

    /// The attributes of an `NSAttributedString`-style dictionary that `keys` name, each kept
    /// when its value is of its key's type.
    public init(_attributes attributes: [NSAttributedString.Key: Any], keys: [any AttributedStringKey.Type]) {
        for key in keys {
            if let object = attributes[NSAttributedString.Key(key.name)], let value = key._webValue(of: object) {
                storage[key.name] = value
            }
        }
    }

    /// A dictionary's Foundation attributes (UIKit's version, imported with UIKit, keeps its
    /// fonts and colours too).
    @_disfavoredOverload
    public init(_ attributes: [NSAttributedString.Key: Any]) {
        self.init(_attributes: attributes, keys: AttributeScopes.FoundationAttributes._webKeys)
    }
}

/// A string with attributes that can differ from one stretch of characters to the next.
@dynamicMemberLookup
public struct AttributedString: AttributedStringProtocol, Hashable, Sendable, CustomStringConvertible {
    /// A stretch of characters sharing one container.
    public struct _Run: Hashable, Sendable {
        public var string: String
        public var attributes: AttributeContainer
        public init(_ string: String, attributes: AttributeContainer = AttributeContainer()) {
            self.string = string
            self.attributes = attributes
        }
    }

    public typealias Index = String.Index
    /// The characters as a collection (a `String` here, with the same indices).
    public typealias CharacterView = String
    public typealias UnicodeScalarView = String.UnicodeScalarView
    public typealias UTF8View = String.UTF8View
    public typealias UTF16View = String.UTF16View
    /// The runs in order, each a stretch whose attributes all match.
    public typealias Runs = [Run]

    /// How a merge treats an attribute both sides set: the new value wins, or the current one.
    public enum AttributeMergePolicy: Hashable, Sendable {
        case keepNew
        case keepCurrent
    }

    /// The runs, adjacent ones with equal attributes always joined, as Foundation keeps them.
    public private(set) var _runs: [_Run]

    public init() { _runs = [] }
    public init(_ string: String, attributes: AttributeContainer = AttributeContainer()) {
        _runs = string.isEmpty ? [] : [_Run(string, attributes: attributes)]
    }
    public init<S: Sequence>(_ characters: S, attributes: AttributeContainer = AttributeContainer()) where S.Element == Character {
        self.init(String(characters), attributes: attributes)
    }
    public init(_ substring: AttributedSubstring) {
        _runs = substring.base._runs(in: substring.range)
    }
    /// Any attributed string's characters and attributes (a substring, or a type of an app's
    /// own that conforms), through its whole range as a substring.
    public init<S: AttributedStringProtocol>(_ other: S) {
        self.init(other[other.startIndex..<other.endIndex])
    }
    public init(stringLiteral value: String) { self.init(value) }

    /// Markdown text parsed into runs with `inlinePresentationIntent` and `link` attributes.
    public init(markdown: String, options: MarkdownParsingOptions = MarkdownParsingOptions(), baseURL: URL? = nil) throws {
        _runs = Self._joined(_InlineMarkdown.parse(markdown).map { run in
            var container = AttributeContainer()
            var intent = InlinePresentationIntent()
            if run.bold { intent.insert(.stronglyEmphasized) }
            if run.italic { intent.insert(.emphasized) }
            if run.code { intent.insert(.code) }
            if run.strikethrough { intent.insert(.strikethrough) }
            if !intent.isEmpty { container.inlinePresentationIntent = intent }
            if let link = run.link, let url = URL(string: link, relativeTo: baseURL) { container.link = url }
            return _Run(run.text, attributes: container)
        })
    }

    /// How markdown is read. The inline syntax is what's parsed in every case; the other
    /// options are kept for the code that sets them (IceCubes asks for extended attributes).
    public struct MarkdownParsingOptions: Hashable, Sendable {
        public enum InterpretedSyntax: Hashable, Sendable { case full, inlineOnly, inlineOnlyPreservingWhitespace }
        public enum FailurePolicy: Hashable, Sendable { case throwError, returnPartiallyParsedIfPossible }
        public var allowsExtendedAttributes: Bool
        public var interpretedSyntax: InterpretedSyntax
        public var failurePolicy: FailurePolicy
        public var languageCode: String?
        public var appliesSourcePositionAttributes: Bool
        public init(allowsExtendedAttributes: Bool = false, interpretedSyntax: InterpretedSyntax = .full,
                    failurePolicy: FailurePolicy = .throwError, languageCode: String? = nil, appliesSourcePositionAttributes: Bool = false) {
            self.allowsExtendedAttributes = allowsExtendedAttributes
            self.interpretedSyntax = interpretedSyntax
            self.failurePolicy = failurePolicy
            self.languageCode = languageCode
            self.appliesSourcePositionAttributes = appliesSourcePositionAttributes
        }
    }

    // MARK: Characters

    /// The characters without their attributes.
    public var characters: CharacterView { _runs.map(\.string).joined() }
    public var unicodeScalars: UnicodeScalarView { characters.unicodeScalars }
    public var utf8: UTF8View { characters.utf8 }
    public var utf16: UTF16View { characters.utf16 }
    public var description: String { characters }
    public var startIndex: Index { characters.startIndex }
    public var endIndex: Index { characters.endIndex }

    /// The range of the first occurrence of `string`.
    public func range(of string: String) -> Range<Index>? {
        let whole = characters
        guard !string.isEmpty else { return nil }
        var start = whole.startIndex
        while start < whole.endIndex {
            if whole[start...].hasPrefix(string) {
                return start..<whole.index(start, offsetBy: string.count)
            }
            start = whole.index(after: start)
        }
        return nil
    }

    // MARK: Attributes

    /// An attribute's value where the whole string has the same one, nil where it varies.
    public subscript<K: AttributedStringKey>(_ key: K.Type) -> K.Value? {
        get { _uniformAttributes(in: startIndex..<endIndex)[K.self] }
        set { _edit(startIndex..<endIndex) { $0[K.self] = newValue } }
    }

    public subscript<K: AttributedStringKey>(dynamicMember keyPath: KeyPath<AttributeDynamicLookup, K>) -> K.Value? {
        get { self[K.self] }
        set { self[K.self] = newValue }
    }

    /// A scope's attributes that the whole string shares (`text.uiKit`, `text.swiftUI`); setting
    /// one through it sets it everywhere, and clearing one removes it everywhere.
    public subscript<S: AttributeScope>(dynamicMember keyPath: KeyPath<AttributeScopes, S.Type>) -> ScopedAttributeContainer<S> {
        get { ScopedAttributeContainer(_uniformAttributes(in: startIndex..<endIndex)) }
        set {
            let old = _uniformAttributes(in: startIndex..<endIndex)
            _edit(startIndex..<endIndex) { $0._apply(newValue._container, over: old, cleared: newValue._cleared) }
        }
    }

    public subscript<R: RangeExpression>(bounds: R) -> AttributedSubstring where R.Bound == Index {
        get { AttributedSubstring(base: self, range: bounds.relative(to: characters)) }
        set { replaceSubrange(bounds.relative(to: characters), with: AttributedString(newValue)) }
    }

    /// Applies `attributes` to the whole string; where both set one, `mergePolicy` decides.
    public mutating func mergeAttributes(_ attributes: AttributeContainer, mergePolicy: AttributeMergePolicy = .keepNew) {
        _edit(startIndex..<endIndex) { $0.merge(attributes, mergePolicy: mergePolicy) }
    }

    public mutating func setAttributes(_ attributes: AttributeContainer) {
        _edit(startIndex..<endIndex) { $0 = attributes }
    }

    /// Where a run has every one of `attributes`, takes them off and applies `others`.
    public mutating func replaceAttributes(_ attributes: AttributeContainer, with others: AttributeContainer) {
        _edit(startIndex..<endIndex) { $0._replace(attributes, with: others) }
    }

    // MARK: Runs

    /// A run as seen from outside: its range and attributes.
    @dynamicMemberLookup
    public struct Run: Hashable, Sendable {
        public let range: Range<Index>
        public let attributes: AttributeContainer

        public subscript<K: AttributedStringKey>(_ key: K.Type) -> K.Value? { attributes[K.self] }
        public subscript<K: AttributedStringKey>(dynamicMember keyPath: KeyPath<AttributeDynamicLookup, K>) -> K.Value? { attributes[K.self] }
        public subscript<S: AttributeScope>(dynamicMember keyPath: KeyPath<AttributeScopes, S.Type>) -> ScopedAttributeContainer<S> {
            ScopedAttributeContainer(attributes)
        }
    }

    public var runs: Runs {
        let whole = characters
        var result: [Run] = []
        var index = whole.startIndex
        for run in _runs {
            let end = whole.index(index, offsetBy: run.string.count)
            result.append(Run(range: index..<end, attributes: run.attributes))
            index = end
        }
        return result
    }

    // MARK: Editing

    public mutating func append(_ other: AttributedString) { _runs = Self._joined(_runs + other._runs) }
    public mutating func append(_ other: AttributedSubstring) { append(AttributedString(other)) }
    public mutating func append<S: AttributedStringProtocol>(_ other: S) { append(AttributedString(other)) }
    public mutating func append(_ string: String) { append(AttributedString(string, attributes: _runs.last?.attributes ?? AttributeContainer())) }

    public static func + (lhs: AttributedString, rhs: AttributedString) -> AttributedString {
        var result = lhs
        result.append(rhs)
        return result
    }
    public static func + <T: AttributedStringProtocol>(lhs: AttributedString, rhs: T) -> AttributedString {
        var result = lhs
        result.append(rhs)
        return result
    }
    public static func += (lhs: inout AttributedString, rhs: AttributedString) { lhs.append(rhs) }
    public static func += <T: AttributedStringProtocol>(lhs: inout AttributedString, rhs: T) { lhs.append(rhs) }

    public mutating func insert<S: AttributedStringProtocol>(_ s: S, at index: Index) {
        replaceSubrange(index..<index, with: AttributedString(s))
    }

    public mutating func removeSubrange<R: RangeExpression>(_ range: R) where R.Bound == Index {
        replaceSubrange(range.relative(to: characters), with: AttributedString())
    }

    /// The runs covering `range` (split at its ends), in order.
    func _runs(in range: Range<Index>) -> [_Run] {
        let whole = characters
        let lower = whole.distance(from: whole.startIndex, to: range.lowerBound)
        let upper = whole.distance(from: whole.startIndex, to: range.upperBound)
        var result: [_Run] = []
        var offset = 0
        for run in _runs {
            let start = offset, end = offset + run.string.count
            offset = end
            let from = max(start, lower), to = min(end, upper)
            guard to > from else { continue }
            let chars = Array(run.string)
            result.append(_Run(String(chars[(from - start)..<(to - start)]), attributes: run.attributes))
        }
        return result
    }

    /// The attributes every character in `range` has, with the same value.
    func _uniformAttributes(in range: Range<Index>) -> AttributeContainer {
        let covering = _runs(in: range)
        guard var common = covering.first?.attributes else { return AttributeContainer() }
        for run in covering.dropFirst() {
            common.storage = common.storage.filter { run.attributes.storage[$0.key] == $0.value }
        }
        return common
    }

    /// Changes the attributes of each run in `range` (split at its ends), joining runs left equal.
    mutating func _edit(_ range: Range<Index>, _ change: (inout AttributeContainer) -> Void) {
        let whole = characters
        var middle = _runs(in: range)
        for index in middle.indices { change(&middle[index].attributes) }
        _runs = Self._joined(_runs(in: whole.startIndex..<range.lowerBound) + middle + _runs(in: range.upperBound..<whole.endIndex))
    }

    /// `runs` with empty ones dropped and neighbours of equal attributes made one.
    static func _joined(_ runs: [_Run]) -> [_Run] {
        var result: [_Run] = []
        for run in runs where !run.string.isEmpty {
            if let last = result.last, last.attributes == run.attributes {
                result[result.count - 1].string += run.string
            } else {
                result.append(run)
            }
        }
        return result
    }

    public mutating func replaceSubrange(_ range: Range<Index>, with replacement: AttributedString) {
        let whole = characters
        let before = whole.startIndex..<range.lowerBound, after = range.upperBound..<whole.endIndex
        _runs = Self._joined(_runs(in: before) + replacement._runs + _runs(in: after))
    }

    public mutating func replaceSubrange(_ range: Range<Index>, with replacement: AttributedSubstring) {
        replaceSubrange(range, with: AttributedString(replacement))
    }

    public mutating func replaceSubrange<R: RangeExpression, S: AttributedStringProtocol>(_ range: R, with replacement: S) where R.Bound == Index {
        replaceSubrange(range.relative(to: characters), with: AttributedString(replacement))
    }
}

/// A slice of an attributed string, in the base string's indices. Reading an attribute gives
/// the value the whole slice shares; setting one applies it across the slice.
@dynamicMemberLookup
public struct AttributedSubstring: AttributedStringProtocol, Sendable, CustomStringConvertible {
    public var base: AttributedString
    public let range: Range<AttributedString.Index>

    public init() {
        let empty = AttributedString()
        base = empty
        range = empty.startIndex..<empty.endIndex
    }
    init(base: AttributedString, range: Range<AttributedString.Index>) {
        self.base = base
        self.range = range
    }

    public var startIndex: AttributedString.Index { range.lowerBound }
    public var endIndex: AttributedString.Index { range.upperBound }
    /// The slice's characters (a new string, its indices from zero).
    public var characters: AttributedString.CharacterView { String(base.characters[range]) }
    public var unicodeScalars: AttributedString.UnicodeScalarView { characters.unicodeScalars }
    public var description: String { characters }
    /// The runs within the slice, cut at its ends, in the base string's indices.
    public var runs: AttributedString.Runs {
        base.runs.compactMap { run in
            let lower = Swift.max(run.range.lowerBound, range.lowerBound), upper = Swift.min(run.range.upperBound, range.upperBound)
            return lower < upper ? AttributedString.Run(range: lower..<upper, attributes: run.attributes) : nil
        }
    }

    public subscript<K: AttributedStringKey>(_ key: K.Type) -> K.Value? {
        get { base._uniformAttributes(in: range)[K.self] }
        set { base._edit(range) { $0[K.self] = newValue } }
    }

    public subscript<K: AttributedStringKey>(dynamicMember keyPath: KeyPath<AttributeDynamicLookup, K>) -> K.Value? {
        get { self[K.self] }
        set { self[K.self] = newValue }
    }

    public subscript<S: AttributeScope>(dynamicMember keyPath: KeyPath<AttributeScopes, S.Type>) -> ScopedAttributeContainer<S> {
        get { ScopedAttributeContainer(base._uniformAttributes(in: range)) }
        set {
            let old = base._uniformAttributes(in: range)
            base._edit(range) { $0._apply(newValue._container, over: old, cleared: newValue._cleared) }
        }
    }

    public subscript<R: RangeExpression>(bounds: R) -> AttributedSubstring where R.Bound == AttributedString.Index {
        AttributedSubstring(base: base, range: bounds.relative(to: base.characters).clamped(to: range))
    }

    public func index(_ i: AttributedString.Index, offsetByCharacters distance: Int) -> AttributedString.Index {
        base.characters.index(i, offsetBy: distance)
    }

    public mutating func mergeAttributes(_ attributes: AttributeContainer, mergePolicy: AttributedString.AttributeMergePolicy = .keepNew) {
        base._edit(range) { $0.merge(attributes, mergePolicy: mergePolicy) }
    }

    public mutating func setAttributes(_ attributes: AttributeContainer) {
        base._edit(range) { $0 = attributes }
    }

    public mutating func replaceAttributes(_ attributes: AttributeContainer, with others: AttributeContainer) {
        base._edit(range) { $0._replace(attributes, with: others) }
    }

    /// Two slices are equal when their characters and attributes are, wherever they sit.
    public static func == (lhs: AttributedSubstring, rhs: AttributedSubstring) -> Bool {
        AttributedString(lhs) == AttributedString(rhs)
    }
    public func hash(into hasher: inout Hasher) { hasher.combine(AttributedString(self)) }
}

/// What an attributed string, its substrings and a type of an app's own can change.
public protocol AttributedStringAttributeMutation {
    mutating func setAttributes(_ attributes: AttributeContainer)
    mutating func mergeAttributes(_ attributes: AttributeContainer, mergePolicy: AttributedString.AttributeMergePolicy)
    mutating func replaceAttributes(_ attributes: AttributeContainer, with others: AttributeContainer)
}

/// What an attributed string and its substrings share, so code can take either (EmojiText's
/// partial string conforms too).
@dynamicMemberLookup
public protocol AttributedStringProtocol: AttributedStringAttributeMutation, Hashable, CustomStringConvertible, Sendable {
    var startIndex: AttributedString.Index { get }
    var endIndex: AttributedString.Index { get }
    var runs: AttributedString.Runs { get }
    var characters: AttributedString.CharacterView { get }
    var unicodeScalars: AttributedString.UnicodeScalarView { get }
    subscript<K: AttributedStringKey>(_: K.Type) -> K.Value? { get }
    subscript<K: AttributedStringKey>(dynamicMember keyPath: KeyPath<AttributeDynamicLookup, K>) -> K.Value? { get }
    subscript<S: AttributeScope>(dynamicMember keyPath: KeyPath<AttributeScopes, S.Type>) -> ScopedAttributeContainer<S> { get }
    subscript<R: RangeExpression>(bounds: R) -> AttributedSubstring where R.Bound == AttributedString.Index { get }
}

extension AttributedStringProtocol {
    public func settingAttributes(_ attributes: AttributeContainer) -> AttributedString {
        var copy = AttributedString(self)
        copy.setAttributes(attributes)
        return copy
    }

    public func mergingAttributes(_ attributes: AttributeContainer, mergePolicy: AttributedString.AttributeMergePolicy = .keepNew) -> AttributedString {
        var copy = AttributedString(self)
        copy.mergeAttributes(attributes, mergePolicy: mergePolicy)
        return copy
    }

    public func replacingAttributes(_ attributes: AttributeContainer, with others: AttributeContainer) -> AttributedString {
        var copy = AttributedString(self)
        copy.replaceAttributes(attributes, with: others)
        return copy
    }

    public func index(_ i: AttributedString.Index, offsetByCharacters distance: Int) -> AttributedString.Index {
        characters.index(i, offsetBy: distance)
    }
}

/// One scope's view of a container's attributes (`container.uiKit.foregroundColor`).
@dynamicMemberLookup
public struct ScopedAttributeContainer<S: AttributeScope>: Sendable {
    public var _container: AttributeContainer
    /// The keys set to nil through this view: on a string whose runs differ in one, the view
    /// never held it, and clearing it still clears every run (`text.uiKit.foregroundColor = nil`).
    public var _cleared: Set<String> = []

    public init(_ container: AttributeContainer = AttributeContainer()) { _container = container }

    public subscript<T: AttributedStringKey>(dynamicMember keyPath: KeyPath<S, T>) -> T.Value? {
        get { _container[T.self] }
        set {
            _container[T.self] = newValue
            if newValue == nil { _cleared.insert(T.name) } else { _cleared.remove(T.name) }
        }
    }
}

extension AttributedString: ExpressibleByStringLiteral {}

// MARK: - Scopes and Foundation's attributed strings

/// A namespace of attribute keys (`AttributeScopes.FoundationAttributes`, SwiftUI's, UIKit's):
/// the keys an attributed string keeps when it is made from an `NSAttributedString`.
public protocol AttributeScope {
    /// The scope's keys, each named as its `NSAttributedString.Key` is.
    static var _webKeys: [any AttributedStringKey.Type] { get }
}

extension AttributeScope {
    /// A scope of an app's own names its keys only through its members, so an
    /// `NSAttributedString` brings none of them in.
    public static var _webKeys: [any AttributedStringKey.Type] { [] }
}

extension AttributeScopes.FoundationAttributes: AttributeScope {
    public static var _webKeys: [any AttributedStringKey.Type] {
        [LinkAttribute.self, InlinePresentationIntentAttribute.self, LanguageIdentifierAttribute.self]
    }
}

extension AttributedStringKey {
    /// `object` as this key's value, when it is one.
    public static func _webValue(of object: Any) -> _AttributeValue? {
        (object as? Value).map { _AttributeValue($0) }
    }
}

extension AttributedString {
    /// The attributed string's characters and its Foundation attributes (links, inline
    /// presentation intents, languages); attributes of other scopes are left out.
    public init(_ nsStr: NSAttributedString) {
        self.init(nsStr, keys: AttributeScopes.FoundationAttributes._webKeys)
    }

    /// The attributed string's characters and the attributes of `scope` (as
    /// `AttributedString(text, including: \.uiKit)`): each attribute whose key the scope names
    /// and whose value is of the key's type; others are left out.
    public init<S: AttributeScope>(_ nsStr: NSAttributedString, including scope: KeyPath<AttributeScopes, S.Type>) throws {
        self.init(nsStr, keys: S._webKeys)
    }

    public init<S: AttributeScope>(_ nsStr: NSAttributedString, including scope: S.Type) throws {
        self.init(nsStr, keys: S._webKeys)
    }

    private init(_ nsStr: NSAttributedString, keys: [any AttributedStringKey.Type]) {
        self.init()
        let units = Array(nsStr.string.utf16)
        var covered = 0
        func add(_ range: NSRange, _ attributes: [NSAttributedString.Key: Any]) {
            let start = max(0, min(range.location, units.count)), end = max(start, min(range.location + range.length, units.count))
            guard end > start else { return }
            let container = AttributeContainer(_attributes: attributes, keys: keys)
            let text = String(decoding: units[start..<end], as: UTF16.self)
            if let last = _runs.last, last.attributes == container {
                _runs[_runs.count - 1].string += text
            } else {
                _runs.append(_Run(text, attributes: container))
            }
            covered = end
        }
        for run in nsStr.runs {
            if run.range.location > covered { add(NSRange(location: covered, length: run.range.location - covered), [:]) }
            add(run.range, run.attributes)
        }
        if covered < units.count { add(NSRange(location: covered, length: units.count - covered), [:]) }
    }
}

#endif

// corelibs Foundation has AttributedString, but not the Darwin inline presentation attribute.
// Add only that key and value on Linux, retaining Foundation's attributed-string identity.
#if os(Linux)
import Foundation

extension AttributeScopes.FoundationAttributes {
    public enum InlinePresentationIntentAttribute: AttributedStringKey {
        public typealias Value = InlinePresentationIntent
        public static let name = "NSInlinePresentationIntent"
    }

    public var inlinePresentationIntent: InlinePresentationIntentAttribute {
        fatalError("an attribute key path, never instantiated")
    }
}
#endif

#if os(WASI) || os(Linux)
/// Inline styling intents of markdown and attributed text.
public struct InlinePresentationIntent: OptionSet, Hashable, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let emphasized = InlinePresentationIntent(rawValue: 1)
    public static let stronglyEmphasized = InlinePresentationIntent(rawValue: 2)
    public static let code = InlinePresentationIntent(rawValue: 4)
    public static let strikethrough = InlinePresentationIntent(rawValue: 32)
    public static let softBreak = InlinePresentationIntent(rawValue: 64)
    public static let lineBreak = InlinePresentationIntent(rawValue: 128)
    public static let inlineHTML = InlinePresentationIntent(rawValue: 256)
    public static let blockHTML = InlinePresentationIntent(rawValue: 512)
}

#endif
