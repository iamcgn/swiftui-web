// Minimal `Text` so shared fixture sources compile before Phase 1 step 6, which adds the real
// text pipeline (LocalizedStringKey, Font, measurement).

/// The key used to look up an entry in a strings file or strings dictionary file.
@frozen
public struct LocalizedStringKey: Equatable, Sendable, ExpressibleByStringInterpolation {
    package var key: String

    public init(_ value: String) { key = value }
    public init(stringLiteral value: String) { key = value }
    public init(stringInterpolation: StringInterpolation) { key = stringInterpolation.output }

    public struct StringInterpolation: StringInterpolationProtocol, Sendable {
        package var output = ""
        public init(literalCapacity: Int, interpolationCount: Int) { output.reserveCapacity(literalCapacity) }
        public mutating func appendLiteral(_ literal: String) { output += literal }
        public mutating func appendInterpolation<T: CustomStringConvertible>(_ value: T) { output += value.description }
        public mutating func appendInterpolation<T>(_ value: T) { output += String(describing: value) }
    }
}

/// A view that displays one or more lines of read-only text.
public struct Text: Equatable, Sendable {
    package enum Storage: Equatable, Sendable {
        case verbatim(String)
        case localized(LocalizedStringKey)
    }

    package let storage: Storage

    /// Creates a text view that displays a string literal without localization.
    public init(verbatim content: String) {
        storage = .verbatim(content)
    }

    /// Creates a text view that displays a stored string without localization.
    @_disfavoredOverload
    public init<S: StringProtocol>(_ content: S) {
        storage = .verbatim(String(content))
    }

    /// Creates a text view that displays localized content identified by a key.
    public init(_ key: LocalizedStringKey) {
        storage = .localized(key)
    }

    /// The displayed string (localization is identity until Phase 3).
    package var resolvedString: String {
        switch storage {
        case .verbatim(let s): return s
        case .localized(let key): return key.key
        }
    }
}

extension Text: View {
    public typealias Body = Never

    public static func _makeNode(_ context: _NodeContext<Text>) -> TypedNode<Text> {
        TextNode(context)
    }
}

/// Placeholder node: sizes to zero until step 6 installs the text engine.
@MainActor
package final class TextNode: LeafNode<Text> {
    override package func computeSizeThatFits(_ proposal: ProposedViewSize) -> CGSize { .zero }
}
