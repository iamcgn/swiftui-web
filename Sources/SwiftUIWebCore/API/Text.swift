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

    /// A style for drawing a line under or through text.
    public struct LineStyle: Hashable, Sendable {
        /// The pattern of the line: continuous, or repeated dots and dashes.
        public enum Pattern: Hashable, Sendable {
            case solid, dot, dash, dashDot, dashDotDot
        }

        public var pattern: Pattern
        /// The colour of the line; `nil` draws it in the text's colour.
        public var color: Color?

        public init(pattern: Pattern = .solid, color: Color? = nil) {
            self.pattern = pattern
            self.color = color
        }

        /// A solid line in the text's colour.
        public static let single = LineStyle()
    }

    /// A capitalisation applied to text.
    public enum Case: Hashable, CaseIterable, Sendable {
        case uppercase, lowercase
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
        /// Decorations: unset (inherit), explicitly off (`.some(nil)`), or a line style.
        package var underline: LineStyle?? = nil
        package var strikethrough: LineStyle?? = nil
        package var baselineOffset: CGFloat?
        package var kerning: CGFloat?
        package var tracking: CGFloat?

        /// `self` applied on top of the enclosing text's modifiers.
        package func inheriting(_ parent: Modifiers) -> Modifiers {
            var result = Modifiers(font: font ?? parent.font, weight: weight ?? parent.weight, bold: bold || parent.bold,
                                   italic: italic || parent.italic, foregroundColor: foregroundColor ?? parent.foregroundColor,
                                   foregroundGradient: foregroundColor != nil ? nil : (foregroundGradient ?? parent.foregroundGradient))
            result.underline = underline ?? parent.underline
            result.strikethrough = strikethrough ?? parent.strikethrough
            result.baselineOffset = baselineOffset ?? parent.baselineOffset
            result.kerning = kerning ?? parent.kerning
            result.tracking = tracking ?? parent.tracking
            return result
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

    /// Applies an underline to the text.
    public func underline(_ isActive: Bool = true, pattern: LineStyle.Pattern = .solid, color: Color? = nil) -> Text {
        var t = self
        t.modifiers.underline = .some(isActive ? LineStyle(pattern: pattern, color: color) : nil)
        return t
    }

    /// Applies a strikethrough to the text.
    public func strikethrough(_ isActive: Bool = true, pattern: LineStyle.Pattern = .solid, color: Color? = nil) -> Text {
        var t = self
        t.modifiers.strikethrough = .some(isActive ? LineStyle(pattern: pattern, color: color) : nil)
        return t
    }

    /// Sets the vertical offset for the text relative to its baseline (positive raises it).
    public func baselineOffset(_ baselineOffset: CGFloat) -> Text {
        var t = self
        t.modifiers.baselineOffset = baselineOffset
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
package struct TextCaseKey: EnvironmentKey { package static let defaultValue: Text.Case? = nil }
package struct UnderlineStyleKey: EnvironmentKey { package static let defaultValue: Text.LineStyle? = nil }
package struct StrikethroughStyleKey: EnvironmentKey { package static let defaultValue: Text.LineStyle? = nil }
package struct BaselineOffsetKey: EnvironmentKey { package static let defaultValue: CGFloat = 0 }

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

    /// A stylistic override to transform the case of text in this environment (`View.textCase`).
    public var textCase: Text.Case? {
        get { self[TextCaseKey.self] }
        set { self[TextCaseKey.self] = newValue }
    }

    /// The underline of text in this environment (`View.underline`).
    package var _underlineStyle: Text.LineStyle? {
        get { self[UnderlineStyleKey.self] }
        set { self[UnderlineStyleKey.self] = newValue }
    }

    /// The strikethrough of text in this environment (`View.strikethrough`).
    package var _strikethroughStyle: Text.LineStyle? {
        get { self[StrikethroughStyleKey.self] }
        set { self[StrikethroughStyleKey.self] = newValue }
    }

    /// The baseline offset of text in this environment (`View.baselineOffset`).
    package var _baselineOffset: CGFloat {
        get { self[BaselineOffsetKey.self] }
        set { self[BaselineOffsetKey.self] = newValue }
    }

    package var textLayoutOptions: TextLayoutOptions {
        TextLayoutOptions(lineLimit: lineLimit, truncationMode: truncationMode, lineSpacing: lineSpacing, minimumLines: minimumLines,
                          kerning: _kerning, tracking: _tracking)
    }

    /// Letter spacing of text in this environment (`View.kerning`, `View.tracking`).
    package var _kerning: CGFloat {
        get { self[KerningKey.self] }
        set { self[KerningKey.self] = newValue }
    }

    package var _tracking: CGFloat {
        get { self[TrackingKey.self] }
        set { self[TrackingKey.self] = newValue }
    }
}

package struct KerningKey: EnvironmentKey {
    package static let defaultValue: CGFloat = 0
}

package struct TrackingKey: EnvironmentKey {
    package static let defaultValue: CGFloat = 0
}

extension Text {
    /// Sets the spacing, or kerning, between characters.
    public func kerning(_ kerning: CGFloat) -> Text {
        var copy = self
        copy.modifiers.kerning = kerning
        return copy
    }

    /// Sets the tracking for the text.
    public func tracking(_ tracking: CGFloat) -> Text {
        var copy = self
        copy.modifiers.tracking = tracking
        return copy
    }
}

extension View {
    /// Sets the spacing, or kerning, between characters for the text in this view.
    nonisolated public func kerning(_ kerning: CGFloat) -> some View {
        environment(\._kerning, kerning)
    }

    /// Sets the tracking for the text in this view.
    nonisolated public func tracking(_ tracking: CGFloat) -> some View {
        environment(\._tracking, tracking)
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

    /// Sets a transform for the case of the text contained in this view.
    nonisolated public func textCase(_ textCase: Text.Case?) -> some View {
        environment(\.textCase, textCase)
    }

    /// Applies an underline to the text in this view.
    nonisolated public func underline(_ isActive: Bool = true, pattern: Text.LineStyle.Pattern = .solid, color: Color? = nil) -> some View {
        environment(\._underlineStyle, isActive ? Text.LineStyle(pattern: pattern, color: color) : nil)
    }

    /// Applies a strikethrough to the text in this view.
    nonisolated public func strikethrough(_ isActive: Bool = true, pattern: Text.LineStyle.Pattern = .solid, color: Color? = nil) -> some View {
        environment(\._strikethroughStyle, isActive ? Text.LineStyle(pattern: pattern, color: color) : nil)
    }

    /// Sets the vertical offset for the text relative to its baseline in this view.
    nonisolated public func baselineOffset(_ baselineOffset: CGFloat) -> some View {
        environment(\._baselineOffset, baselineOffset)
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
        return (parts.map { StyledRun(cased($0.string), font: resolveFont($0.modifiers)) }, parts.map(\.modifiers.foregroundColor))
    }

    /// `string` with the environment's `textCase` applied.
    package func cased(_ string: String) -> String {
        switch environment.textCase {
        case nil: return string
        case .uppercase: return string.uppercased()
        case .lowercase: return string.lowercased()
        }
    }

    /// Each part's own gradient, if it has one.
    package var runGradients: [(any _GradientStyle)?] { view.parts().map { $0.modifiers.foregroundGradient?.style } }

    /// The environment's layout options with the text's own kerning and tracking.
    package var layoutOptions: TextLayoutOptions {
        var options = environment.textLayoutOptions
        if let kerning = view.modifiers.kerning { options.kerning = kerning }
        if let tracking = view.modifiers.tracking { options.tracking = tracking }
        return options
    }

    package func textLayout(width: CGFloat?) -> TextLayout {
        runtime.layoutText(styledRuns.runs, options: layoutOptions, width: width)
    }

    /// Each part's baseline offset (its own, else the environment's).
    package var baselineOffsets: [CGFloat] {
        view.parts().map { $0.modifiers.baselineOffset ?? environment._baselineOffset }
    }

    /// How far the text grows above and below for baseline offsets: the largest raise adds
    /// space below the (unmoved) baseline guide, the largest drop adds space below the glyphs
    /// (`textstyle/baseline`: a text 16 high with offset 6 is 22 high, with −4 it is 20).
    package var baselineShift: (up: CGFloat, down: CGFloat) {
        let offsets = baselineOffsets
        return (max(0, offsets.max() ?? 0), max(0, -(offsets.min() ?? 0)))
    }

    override package func computeSizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
        // Text wraps at the proposed width; an unspecified or infinite width means one line.
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil }
        var size = textLayout(width: width).size
        let shift = baselineShift
        size.height += shift.up + shift.down
        return size
    }

    override package func dimensions(in proposal: ProposedViewSize) -> ViewDimensions {
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil }
        let layout = textLayout(width: width)
        let shift = baselineShift
        return ViewDimensions(size: CGSize(width: layout.size.width, height: layout.size.height + shift.up + shift.down), explicit: [
            VerticalAlignment.firstTextBaseline.key: layout.firstBaseline + shift.up,
            VerticalAlignment.lastTextBaseline.key: layout.lastBaseline + shift.up,
        ])
    }

    override package func paintSelf(into list: inout DisplayList, context: PaintContext) {
        let (runs, colors) = styledRuns
        let layout = runtime.layoutText(runs, options: layoutOptions, width: frame.width)
        let inherited = (environment.foregroundColor ?? .primary)
        let resolvedColors = colors.map { ($0 ?? inherited).resolve(in: environment) }
        let spacing = TextLayouter.letterSpacing(layoutOptions)
        let fonts = runs.map { DisplayFont($0.font, letterSpacing: spacing) }
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
        let parts = view.parts()
        let offsets = baselineOffsets
        let shiftUp = baselineShift.up
        for line in layout.lines {
            let lineX = bounds.minX + (frame.width - line.inkWidth) * alignment
            for fragment in line.fragments where !fragment.text.isEmpty {
                let run = min(max(fragment.run, 0), max(runs.count - 1, 0))
                let font = fonts.indices.contains(run) ? fonts[run] : DisplayFont(resolvedFont)
                let offset = offsets.indices.contains(run) ? offsets[run] : 0
                let origin = CGPoint(x: lineX + fragment.x, y: bounds.minY + line.baseline + shiftUp - offset)
                let own = runGradients.indices.contains(run) ? runGradients[run]?._resolveGradient(in: bounds, environment: environment) : nil
                let color = resolvedColors.indices.contains(run) ? resolvedColors[run] : inherited.resolve(in: environment)
                if let gradient = own ?? inheritedGradient, colors.indices.contains(run) ? colors[run] == nil : true {
                    list.append(.drawTextGradient(fragment.text, font, origin: origin, gradient))
                } else {
                    list.append(.drawText(fragment.text, font, origin: origin, color))
                }
                if parts.indices.contains(run) {
                    let modifiers = parts[run].modifiers
                    let underline = modifiers.underline ?? environment._underlineStyle
                    let strikethrough = modifiers.strikethrough ?? environment._strikethroughStyle
                    if underline != nil || strikethrough != nil {
                        let metrics = environment.platformProfile.textDecorationMetrics(for: runs[run].font)
                        if let underline {
                            paintDecoration(underline, centre: origin.y + metrics.underlineOffset, thickness: metrics.thickness,
                                            from: origin.x, to: origin.x + fragment.width, textColor: color, context: context, into: &list)
                        }
                        if let strikethrough {
                            paintDecoration(strikethrough, centre: origin.y - metrics.xHeight / 2, thickness: metrics.thickness,
                                            from: origin.x, to: origin.x + fragment.width, textColor: color, context: context, into: &list)
                        }
                    }
                }
            }
        }
    }

    /// Draws one underline or strikethrough: the line snaps to whole device pixels (its top
    /// rounded, its thickness rounded up, its ends rounded inwards), and patterns repeat in
    /// multiples of the snapped thickness (`Docs/elements/TextStyle.md`).
    private func paintDecoration(_ style: Text.LineStyle, centre: CGFloat, thickness: CGFloat, from x0: CGFloat, to x1: CGFloat,
                                 textColor: RGBA, context: PaintContext, into list: inout DisplayList) {
        let scale = context.scale
        let thicknessPixels = max(1, (thickness * scale).rounded(.up))
        let snapped = thicknessPixels / scale
        let top = (centre * scale - thicknessPixels / 2).rounded(.toNearestOrAwayFromZero) / scale
        let start = (x0 * scale).rounded(.up) / scale, end = (x1 * scale).rounded(.down) / scale
        guard end > start else { return }
        let color = style.color?.resolve(in: environment) ?? textColor
        let dashes: [CGFloat]
        switch style.pattern {
        case .solid: dashes = []
        case .dot: dashes = [3, 3]
        case .dash: dashes = [10, 5]
        case .dashDot: dashes = [10, 3, 3, 3]
        case .dashDotDot: dashes = [10, 3, 3, 3, 3, 3]
        }
        if dashes.isEmpty {
            list.append(.fillRect(CGRect(x: start, y: top, width: end - start, height: snapped), color))
        } else {
            var path = Path()
            path.move(to: CGPoint(x: start, y: top + snapped / 2))
            path.addLine(to: CGPoint(x: end, y: top + snapped / 2))
            list.append(.strokePath(path, style: StrokeStyle(lineWidth: snapped, dash: dashes.map { $0 * snapped }), color))
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

extension Text {
    /// The text's characters without styling (tooltips, accessibility).
    package var _plainString: String { parts().map(\.string).joined() }
}
