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
        public mutating func appendInterpolation(_ string: String) { output += string }
        public mutating func appendInterpolation<S: StringProtocol>(_ string: S) { output += String(string) }
        public mutating func appendInterpolation<T: CustomStringConvertible>(_ value: T) { output += value.description }
        public mutating func appendInterpolation<T>(_ value: T) { output += String(describing: value) }
        public mutating func appendInterpolation(_ text: Text) { output += text.resolvedString }
    }
}

/// A view that displays one or more lines of read-only text.
public struct Text: Equatable, Sendable {
    package enum Storage: Equatable, Sendable {
        case verbatim(String)
        case localized(LocalizedStringKey)
        case concatenated([Text])
    }

    /// Modifiers applied on the `Text` value itself (they win over the environment).
    package struct Modifiers: Equatable, Sendable {
        package var font: Font?
        package var weight: Font.Weight?
        package var italic = false
        package var foregroundColor: Color?
    }

    package let storage: Storage
    package var modifiers = Modifiers()

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
        case .concatenated(let parts): return parts.map(\.resolvedString).joined()
        }
    }

    // MARK: Text-level modifiers (return Text, as in SwiftUI)

    public func font(_ font: Font?) -> Text { var t = self; t.modifiers.font = font; return t }
    public func fontWeight(_ weight: Font.Weight?) -> Text { var t = self; t.modifiers.weight = weight; return t }
    /// See `Font.bold()`: the bold trait is the semibold face on macOS.
    public func bold() -> Text { fontWeight(PlatformMetrics.boldTraitWeight) }
    public func bold(_ isActive: Bool) -> Text { isActive ? bold() : self }
    public func italic() -> Text { var t = self; t.modifiers.italic = true; return t }
    public func italic(_ isActive: Bool) -> Text { isActive ? italic() : self }
    public func foregroundColor(_ color: Color?) -> Text { var t = self; t.modifiers.foregroundColor = color; return t }
    public func foregroundStyle<S: ShapeStyle>(_ style: S) -> Text {
        var t = self
        t.modifiers.foregroundColor = style as? Color
        return t
    }

    /// Concatenates the text of two text views.
    public static func + (lhs: Text, rhs: Text) -> Text {
        var t = Text(verbatim: "")
        t = Text(storage: .concatenated([lhs, rhs]))
        return t
    }

    package init(storage: Storage) {
        self.storage = storage
    }
}

extension Text: View {
    public typealias Body = Never

    public static func _makeNode(_ context: _NodeContext<Text>) -> TypedNode<Text> {
        TextNode(context)
    }
}

/// Lays out a text run with the runtime's text engine.
@MainActor
package final class TextNode: LeafNode<Text> {
    package var resolvedFont: ResolvedFont {
        let font = view.modifiers.font ?? environment.font ?? .body
        var resolved = font.resolve(profile: environment.platformProfile)
        if let weight = view.modifiers.weight { resolved.weight = weight; resolved.weightOverridden = true }
        if view.modifiers.italic { resolved.italic = true }
        return resolved
    }

    package func textLayout(width: CGFloat?) -> TextLayout {
        runtime.textEngine.layout(view.resolvedString, font: resolvedFont, width: width)
    }

    override package func computeSizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
        // Text wraps at the proposed width; an unspecified or infinite width means one line.
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil }
        return textLayout(width: width).size
    }

    override package func dimensions(in proposal: ProposedViewSize) -> ViewDimensions {
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil }
        let layout = textLayout(width: width)
        return ViewDimensions(size: layout.size, explicit: [
            VerticalAlignment.firstTextBaseline.key: layout.firstBaseline,
            VerticalAlignment.lastTextBaseline.key: layout.lastBaseline,
        ])
    }

    override package func paintSelf(into list: inout DisplayList, context: PaintContext) {
        let layout = textLayout(width: frame.width)
        let color = (view.modifiers.foregroundColor ?? environment.foregroundColor ?? .primary).resolve(in: environment)
        let font = DisplayFont(resolvedFont)
        let bounds = absoluteBounds(context)
        let string = view.resolvedString
        if layout.lines.isEmpty {
            list.append(.drawText(string, font, origin: CGPoint(x: bounds.minX, y: bounds.minY + layout.firstBaseline), color))
        } else {
            for line in layout.lines {
                list.append(.drawText(String(string[line.range]), font, origin: CGPoint(x: bounds.minX, y: bounds.minY + line.baseline), color))
            }
        }
    }

    /// Text declares no default category vertically: its distances to neighbours come from the
    /// font (fixtures text/vstack-spacing*). Horizontally it behaves like any view (8 points).
    override package var layoutSpacing: ViewSpacing {
        let metrics = runtime.textEngine.metrics(for: resolvedFont)
        return ViewSpacing.text(metrics)
    }
}
