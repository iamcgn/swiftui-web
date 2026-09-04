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

/// An alignment position for text along the horizontal axis.
public enum TextAlignment: Hashable, CaseIterable, Sendable {
    case leading, center, trailing
}

/// A view that displays one or more lines of read-only text.
public struct Text: Equatable, Sendable {
    /// The type of truncation to apply to a line of text when it's too long to fit in the
    /// available space.
    public enum TruncationMode: Hashable, Sendable {
        case head, tail, middle
    }

    package enum Storage: Equatable, Sendable {
        case verbatim(String)
        case localized(LocalizedStringKey)
        case concatenated([Text])
    }

    /// Modifiers applied on the `Text` value itself (they win over the environment). In a
    /// concatenation, a part's own modifiers win over the modifiers of the whole.
    package struct Modifiers: Equatable, Sendable {
        package var font: Font?
        package var weight: Font.Weight?
        package var bold = false
        package var italic = false
        package var foregroundColor: Color?
        /// A gradient foreground style set on the text itself (`Text.foregroundStyle`).
        package var foregroundGradient: _GradientBox?

        /// `self` applied on top of the enclosing text's modifiers.
        package func inheriting(_ parent: Modifiers) -> Modifiers {
            Modifiers(font: font ?? parent.font, weight: weight ?? parent.weight, bold: bold || parent.bold,
                      italic: italic || parent.italic, foregroundColor: foregroundColor ?? parent.foregroundColor,
                      foregroundGradient: foregroundColor != nil ? nil : (foregroundGradient ?? parent.foregroundGradient))
        }
    }

    /// One leaf of a (possibly concatenated) text with every modifier resolved.
    package struct Part: Equatable, Sendable {
        package var string: String
        package var modifiers: Modifiers
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

    /// The leaves of this text in order, each with the modifiers that apply to it.
    package func parts(inheriting parent: Modifiers = Modifiers()) -> [Part] {
        let effective = modifiers.inheriting(parent)
        switch storage {
        case .verbatim(let s): return [Part(string: s, modifiers: effective)]
        case .localized(let key): return [Part(string: key.key, modifiers: effective)]
        case .concatenated(let texts): return texts.flatMap { $0.parts(inheriting: effective) }
        }
    }

    // MARK: Text-level modifiers (return Text, as in SwiftUI)

    public func font(_ font: Font?) -> Text { var t = self; t.modifiers.font = font; return t }
    public func fontWeight(_ weight: Font.Weight?) -> Text { var t = self; t.modifiers.weight = weight; return t }
    /// See `Font.bold()`: the bold trait resolves per text style.
    public func bold() -> Text { var t = self; t.modifiers.bold = true; return t }
    public func bold(_ isActive: Bool) -> Text { isActive ? bold() : self }
    public func italic() -> Text { var t = self; t.modifiers.italic = true; return t }
    public func italic(_ isActive: Bool) -> Text { isActive ? italic() : self }
    public func foregroundColor(_ color: Color?) -> Text {
        var t = self
        t.modifiers.foregroundColor = color
        t.modifiers.foregroundGradient = nil
        return t
    }

    /// A colour or gradient replaces the text's style; a hierarchical style keeps it (`.primary`)
    /// or fades it; other styles leave it (`View.foregroundStyle`).
    public func foregroundStyle<S: ShapeStyle>(_ style: S) -> Text {
        var t = self
        if let color = style as? Color {
            t.modifiers.foregroundColor = color
            t.modifiers.foregroundGradient = nil
        } else if let level = style as? HierarchicalShapeStyle {
            if level.level > 0 {
                t.modifiers.foregroundColor = t.modifiers.foregroundColor.map { $0.opacity(level.opacity) }
                    ?? (level.level == 1 ? Color.secondary : Color.primary.opacity(level.opacity))
                t.modifiers.foregroundGradient = nil
            }
        } else if let gradient = MainActor.assumeIsolated({ style as? any _GradientStyle }) {
            t.modifiers.foregroundColor = nil
            t.modifiers.foregroundGradient = _GradientBox(gradient)
        }
        return t
    }

    /// Concatenates the text of two text views.
    public static func + (lhs: Text, rhs: Text) -> Text {
        Text(storage: .concatenated([lhs, rhs]))
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

// MARK: - Environment (line limit, alignment, truncation, spacing)

package struct LineLimitKey: EnvironmentKey { package static let defaultValue: Int? = nil }
package struct MinimumLinesKey: EnvironmentKey { package static let defaultValue = 0 }
package struct MultilineTextAlignmentKey: EnvironmentKey { package static let defaultValue = TextAlignment.leading }
package struct TruncationModeKey: EnvironmentKey { package static let defaultValue = Text.TruncationMode.tail }
package struct LineSpacingKey: EnvironmentKey { package static let defaultValue: CGFloat = 0 }
package struct AllowsTighteningKey: EnvironmentKey { package static let defaultValue = false }
package struct MinimumScaleFactorKey: EnvironmentKey { package static let defaultValue: CGFloat = 1 }

extension EnvironmentValues {
    /// The maximum number of lines that text can occupy in a view.
    public var lineLimit: Int? {
        get { self[LineLimitKey.self] }
        set { self[LineLimitKey.self] = newValue }
    }

    /// Lines whose height text reserves even when it is shorter (`lineLimit(_:reservesSpace:)`,
    /// the lower bound of a range limit).
    package var minimumLines: Int {
        get { self[MinimumLinesKey.self] }
        set { self[MinimumLinesKey.self] = newValue }
    }

    /// An environment value that indicates how a text view aligns its lines when the content
    /// wraps or contains newlines.
    public var multilineTextAlignment: TextAlignment {
        get { self[MultilineTextAlignmentKey.self] }
        set { self[MultilineTextAlignmentKey.self] = newValue }
    }

    /// A value that indicates how the layout truncates the last line of text to fit into the
    /// available space.
    public var truncationMode: Text.TruncationMode {
        get { self[TruncationModeKey.self] }
        set { self[TruncationModeKey.self] = newValue }
    }

    /// The distance in points between the bottom of one line fragment and the top of the next.
    public var lineSpacing: CGFloat {
        get { self[LineSpacingKey.self] }
        set { self[LineSpacingKey.self] = newValue }
    }

    /// Whether inter-character spacing should tighten to fit the text into the available space.
    /// Stored, not applied.
    public var allowsTightening: Bool {
        get { self[AllowsTighteningKey.self] }
        set { self[AllowsTighteningKey.self] = newValue }
    }

    /// The minimum permissible proportion to shrink the font size to fit the text. Stored, not applied.
    public var minimumScaleFactor: CGFloat {
        get { self[MinimumScaleFactorKey.self] }
        set { self[MinimumScaleFactorKey.self] = newValue }
    }

    package var textLayoutOptions: TextLayoutOptions {
        TextLayoutOptions(lineLimit: lineLimit, truncationMode: truncationMode, lineSpacing: lineSpacing, minimumLines: minimumLines)
    }
}

extension View {
    /// Sets the maximum number of lines that text can occupy in this view.
    nonisolated public func lineLimit(_ number: Int?) -> some View {
        environment(\.lineLimit, number).environment(\.minimumLines, 0)
    }

    /// Sets to a partial range the number of lines that text can occupy in this view: the lower
    /// bound reserves that many lines, there is no upper limit.
    nonisolated public func lineLimit(_ limit: PartialRangeFrom<Int>) -> some View {
        environment(\.lineLimit, nil).environment(\.minimumLines, limit.lowerBound)
    }

    nonisolated public func lineLimit(_ limit: PartialRangeThrough<Int>) -> some View {
        environment(\.lineLimit, limit.upperBound).environment(\.minimumLines, 0)
    }

    /// Sets to a closed range the number of lines text can occupy: the lower bound reserves
    /// lines, the upper bound truncates.
    nonisolated public func lineLimit(_ limit: ClosedRange<Int>) -> some View {
        environment(\.lineLimit, limit.upperBound).environment(\.minimumLines, limit.lowerBound)
    }

    /// Sets a limit for the number of lines text can occupy in this view, optionally reserving
    /// the space of that many lines.
    nonisolated public func lineLimit(_ limit: Int, reservesSpace: Bool) -> some View {
        environment(\.lineLimit, limit).environment(\.minimumLines, reservesSpace ? limit : 0)
    }

    /// Sets the alignment of a text view that contains multiple lines of text.
    nonisolated public func multilineTextAlignment(_ alignment: TextAlignment) -> some View {
        environment(\.multilineTextAlignment, alignment)
    }

    /// Sets the truncation mode for lines of text that are too long to fit in the available space.
    nonisolated public func truncationMode(_ mode: Text.TruncationMode) -> some View {
        environment(\.truncationMode, mode)
    }

    /// Sets the amount of space between lines of text in this view.
    nonisolated public func lineSpacing(_ lineSpacing: CGFloat) -> some View {
        environment(\.lineSpacing, lineSpacing)
    }

    /// Sets whether text in this view can compress the space between characters when necessary
    /// to fit text in a line. Stored only.
    nonisolated public func allowsTightening(_ flag: Bool) -> some View {
        environment(\.allowsTightening, flag)
    }

    /// Sets the minimum amount that text in this view scales down to fit in the available space.
    /// Stored only.
    nonisolated public func minimumScaleFactor(_ factor: CGFloat) -> some View {
        environment(\.minimumScaleFactor, factor)
    }
}

// MARK: - Node

/// Lays out a text run with the runtime's text engine.
@MainActor
package final class TextNode: LeafNode<Text> {
    package func resolveFont(_ modifiers: Text.Modifiers) -> ResolvedFont {
        let font = modifiers.font ?? environment.font ?? environment.platformProfile.defaultFont
        var resolved = font.resolve(profile: environment.platformProfile)
        if let weight = modifiers.weight {
            resolved.weight = weight; resolved.weightOverridden = true
        } else if modifiers.bold {
            resolved.weight = environment.platformProfile.boldTraitWeight(for: resolved.textStyle); resolved.weightOverridden = true
        } else if let weight = environment._fontWeight {
            resolved.weight = weight; resolved.weightOverridden = true
        } else if environment._boldTrait {
            resolved.weight = environment.platformProfile.boldTraitWeight(for: resolved.textStyle); resolved.weightOverridden = true
        }
        if modifiers.italic { resolved.italic = true }
        return resolved
    }

    /// The font of the text as a whole (its own modifiers over the environment); parts of a
    /// concatenation may differ.
    package var resolvedFont: ResolvedFont { resolveFont(view.modifiers) }

    /// The text's leaves as the engine sees them, with each part's colour.
    package var styledRuns: (runs: [StyledRun], colors: [Color?]) {
        let parts = view.parts()
        return (parts.map { StyledRun($0.string, font: resolveFont($0.modifiers)) }, parts.map(\.modifiers.foregroundColor))
    }

    /// Each part's own gradient, if it has one.
    package var runGradients: [(any _GradientStyle)?] { view.parts().map { $0.modifiers.foregroundGradient?.style } }

    package func textLayout(width: CGFloat?) -> TextLayout {
        runtime.textEngine.layout(styledRuns.runs, options: environment.textLayoutOptions, width: width)
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
        let (runs, colors) = styledRuns
        let layout = runtime.textEngine.layout(runs, options: environment.textLayoutOptions, width: frame.width)
        let inherited = (environment.foregroundColor ?? .primary)
        let resolvedColors = colors.map { ($0 ?? inherited).resolve(in: environment) }
        let fonts = runs.map { DisplayFont($0.font) }
        let bounds = absoluteBounds(context)
        // A gradient foreground style (the text's own or the environment's) fills the runs
        // without a colour of their own.
        let runGradients = runGradients
        let inheritedGradient = environment.foregroundGradient?._resolveGradient(in: bounds, environment: environment)
        let alignment: CGFloat
        switch environment.multilineTextAlignment {
        case .leading: alignment = 0
        case .center: alignment = 0.5
        case .trailing: alignment = 1
        }
        for line in layout.lines {
            let lineX = bounds.minX + (frame.width - line.inkWidth) * alignment
            for fragment in line.fragments where !fragment.text.isEmpty {
                let run = min(max(fragment.run, 0), max(runs.count - 1, 0))
                let font = fonts.indices.contains(run) ? fonts[run] : DisplayFont(resolvedFont)
                let origin = CGPoint(x: lineX + fragment.x, y: bounds.minY + line.baseline)
                let own = runGradients.indices.contains(run) ? runGradients[run]?._resolveGradient(in: bounds, environment: environment) : nil
                if let gradient = own ?? inheritedGradient, colors.indices.contains(run) ? colors[run] == nil : true {
                    list.append(.drawTextGradient(fragment.text, font, origin: origin, gradient))
                } else {
                    list.append(.drawText(fragment.text, font, origin: origin,
                                          resolvedColors.indices.contains(run) ? resolvedColors[run] : inherited.resolve(in: environment)))
                }
            }
        }
    }

    /// Text declares no default category vertically: its distances to neighbours come from the
    /// font (fixtures text/vstack-spacing*). Horizontally it behaves like any view (8 points).
    override package var layoutSpacing: ViewSpacing {
        let metrics = runtime.textEngine.metrics(for: styledRuns.runs.first?.font ?? resolvedFont)
        return ViewSpacing.text(metrics)
    }
}

// MARK: - View-level weight

package struct FontWeightKey: EnvironmentKey {
    package static let defaultValue: Font.Weight? = nil
}

package struct BoldTraitKey: EnvironmentKey {
    package static let defaultValue = false
}

extension EnvironmentValues {
    /// A font weight applied to text and symbols in this environment (`View.fontWeight`).
    package var _fontWeight: Font.Weight? {
        get { self[FontWeightKey.self] }
        set { self[FontWeightKey.self] = newValue }
    }

    /// Whether text and symbols in this environment take the bold trait (`View.bold`).
    package var _boldTrait: Bool {
        get { self[BoldTraitKey.self] }
        set { self[BoldTraitKey.self] = newValue }
    }

    /// The environment's font with its weight overrides applied (text and symbol images).
    package var _resolvedFont: ResolvedFont {
        var resolved = (font ?? platformProfile.defaultFont).resolve(profile: platformProfile)
        if let weight = _fontWeight {
            resolved.weight = weight; resolved.weightOverridden = true
        } else if _boldTrait {
            resolved.weight = platformProfile.boldTraitWeight(for: resolved.textStyle); resolved.weightOverridden = true
        }
        return resolved
    }
}

extension View {
    /// Sets the font weight of the text and symbol images in this view.
    nonisolated public func fontWeight(_ weight: Font.Weight?) -> some View {
        environment(\._fontWeight, weight)
    }

    /// Applies a bold font weight to the text and symbol images in this view.
    nonisolated public func bold(_ isActive: Bool = true) -> some View {
        environment(\._boldTrait, isActive)
    }
}
