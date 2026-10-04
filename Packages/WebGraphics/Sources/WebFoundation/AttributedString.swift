// Foundation's `AttributedString` on wasm (decision 0017): FoundationEssentials there has none.
// Runs of characters with attribute containers, the attribute-key protocol and scopes that the
// SwiftUI module extends (`AttributeScopes.SwiftUIAttributes`), dynamic member lookup on
// containers, runs and substrings, and `init(markdown:)` through `_InlineMarkdown`.
#if os(WASI)
import FoundationEssentials

/// A key for an attribute of an attributed string.
public protocol AttributedStringKey {
    associatedtype Value: Hashable & Sendable
    static var name: String { get }
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

    /// Replaces this container's attributes with `other`'s where both are set.
    public func merging(_ other: AttributeContainer) -> AttributeContainer {
        var result = self
        for (key, value) in other.storage { result.storage[key] = value }
        return result
    }
}

/// A string with attributes that can differ from one stretch of characters to the next.
@dynamicMemberLookup
public struct AttributedString: Hashable, Sendable, CustomStringConvertible {
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
    public init(stringLiteral value: String) { self.init(value) }

    /// Markdown text parsed into runs with `inlinePresentationIntent` and `link` attributes.
    public init(markdown: String, options: MarkdownParsingOptions = MarkdownParsingOptions()) throws {
        _runs = _InlineMarkdown.parse(markdown).map { run in
            var container = AttributeContainer()
            var intent = InlinePresentationIntent()
            if run.bold { intent.insert(.stronglyEmphasized) }
            if run.italic { intent.insert(.emphasized) }
            if run.code { intent.insert(.code) }
            if run.strikethrough { intent.insert(.strikethrough) }
            if !intent.isEmpty { container.inlinePresentationIntent = intent }
            if let link = run.link, let url = URL(string: link) { container.link = url }
            return _Run(run.text, attributes: container)
        }.filter { !$0.string.isEmpty }
    }

    public struct MarkdownParsingOptions: Sendable {
        public enum InterpretedSyntax: Sendable { case full, inlineOnly, inlineOnlyPreservingWhitespace }
        public var interpretedSyntax: InterpretedSyntax
        public init(interpretedSyntax: InterpretedSyntax = .full) { self.interpretedSyntax = interpretedSyntax }
    }

    // MARK: Characters

    /// The characters without their attributes.
    public var characters: String { _runs.map(\.string).joined() }
    public var unicodeScalars: String.UnicodeScalarView { characters.unicodeScalars }
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

    public subscript<K: AttributedStringKey>(_ key: K.Type) -> K.Value? {
        get { _runs.first?.attributes[K.self] }
        set { for index in _runs.indices { _runs[index].attributes[K.self] = newValue } }
    }

    public subscript<K: AttributedStringKey>(dynamicMember keyPath: KeyPath<AttributeDynamicLookup, K>) -> K.Value? {
        get { self[K.self] }
        set { self[K.self] = newValue }
    }

    public subscript(range: Range<Index>) -> AttributedSubstring {
        get { AttributedSubstring(base: self, range: range) }
        set { replaceSubrange(range, with: AttributedString(newValue)) }
    }

    /// Applies `container`'s attributes to the whole string.
    public mutating func mergeAttributes(_ container: AttributeContainer) {
        for index in _runs.indices { _runs[index].attributes = _runs[index].attributes.merging(container) }
    }

    public mutating func setAttributes(_ container: AttributeContainer) {
        for index in _runs.indices { _runs[index].attributes = container }
    }

    public func settingAttributes(_ container: AttributeContainer) -> AttributedString {
        var copy = self
        copy.setAttributes(container)
        return copy
    }

    // MARK: Runs

    /// A run as seen from outside: its range and attributes.
    @dynamicMemberLookup
    public struct Run: Hashable, Sendable {
        public let range: Range<Index>
        public let attributes: AttributeContainer

        public subscript<K: AttributedStringKey>(_ key: K.Type) -> K.Value? { attributes[K.self] }
        public subscript<K: AttributedStringKey>(dynamicMember keyPath: KeyPath<AttributeDynamicLookup, K>) -> K.Value? { attributes[K.self] }
    }

    public var runs: [Run] {
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

    public mutating func append(_ other: AttributedString) { _runs += other._runs }
    public mutating func append(_ other: AttributedSubstring) { _runs += AttributedString(other)._runs }
    public mutating func append(_ string: String) { _runs.append(_Run(string, attributes: _runs.last?.attributes ?? AttributeContainer())) }

    public static func + (lhs: AttributedString, rhs: AttributedString) -> AttributedString {
        var result = lhs
        result.append(rhs)
        return result
    }
    public static func += (lhs: inout AttributedString, rhs: AttributedString) { lhs.append(rhs) }

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

    public mutating func replaceSubrange(_ range: Range<Index>, with replacement: AttributedString) {
        let whole = characters
        let before = whole.startIndex..<range.lowerBound, after = range.upperBound..<whole.endIndex
        _runs = _runs(in: before) + replacement._runs + _runs(in: after)
    }

    public mutating func replaceSubrange(_ range: Range<Index>, with replacement: AttributedSubstring) {
        replaceSubrange(range, with: AttributedString(replacement))
    }
}

/// A slice of an attributed string: reading its attributes reads the first run's, setting one
/// applies it across the slice.
@dynamicMemberLookup
public struct AttributedSubstring: Hashable, Sendable {
    public var base: AttributedString
    public let range: Range<AttributedString.Index>

    public var characters: String { String(base.characters[range]) }
    public var runs: [AttributedString.Run] { AttributedString(self).runs }

    public subscript<K: AttributedStringKey>(_ key: K.Type) -> K.Value? {
        get { base._runs(in: range).first?.attributes[K.self] }
        set {
            var slice = AttributedString(self)
            slice[K.self] = newValue
            base.replaceSubrange(range, with: slice)
        }
    }

    public subscript<K: AttributedStringKey>(dynamicMember keyPath: KeyPath<AttributeDynamicLookup, K>) -> K.Value? {
        get { self[K.self] }
        set { self[K.self] = newValue }
    }

    public mutating func mergeAttributes(_ container: AttributeContainer) {
        var slice = AttributedString(self)
        slice.mergeAttributes(container)
        base.replaceSubrange(range, with: slice)
    }
}

extension AttributedString: ExpressibleByStringLiteral {}
#endif
