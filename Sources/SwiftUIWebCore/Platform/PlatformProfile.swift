/// Per-platform metrics and defaults. macOS is the reference profile (goldens come from a Mac);
/// iOS arrives later behind the same table.
public struct PlatformProfile: Sendable {
    public struct TextStyleMetrics: Sendable, Equatable {
        public var size: CGFloat
        public var weight: Font.Weight
        /// The weight the bold trait (`bold()`) resolves to for this style.
        public var boldTraitWeight: Font.Weight
        public init(size: CGFloat, weight: Font.Weight, boldTraitWeight: Font.Weight) {
            self.size = size; self.weight = weight; self.boldTraitWeight = boldTraitWeight
        }
    }

    public var name: String
    package var textStyles: [Font.TextStyle: TextStyleMetrics]

    /// The font text uses when neither a modifier nor the environment sets one. On macOS this
    /// is the 13 pt system font (16 pt line, baseline 13), not `.body` (18.5 pt line): measured
    /// in a hosted window, decision 0010.
    package var defaultFont: Font

    package func textStyle(_ style: Font.TextStyle) -> TextStyleMetrics {
        textStyles[style] ?? TextStyleMetrics(size: 13, weight: .regular, boldTraitWeight: .bold)
    }

    /// Weight of the bold trait: per text style, and bold for point-size and custom fonts
    /// (macOS 26.2, fixtures text/modifiers and text/bold-trait).
    package func boldTraitWeight(for style: Font.TextStyle?) -> Font.Weight {
        style.map { textStyle($0).boldTraitWeight } ?? .bold
    }

    /// macOS text styles (Apple HIG typography table, default dynamic type size) and the weight
    /// each style's bold trait resolves to (fixture text/bold-trait).
    public static let macOS = PlatformProfile(name: "macOS", textStyles: [
        .largeTitle: .init(size: 26, weight: .regular, boldTraitWeight: .bold),
        .title: .init(size: 22, weight: .regular, boldTraitWeight: .bold),
        .title2: .init(size: 17, weight: .regular, boldTraitWeight: .bold),
        .title3: .init(size: 15, weight: .regular, boldTraitWeight: .semibold),
        .headline: .init(size: 13, weight: .bold, boldTraitWeight: .heavy),
        .subheadline: .init(size: 11, weight: .regular, boldTraitWeight: .semibold),
        .body: .init(size: 13, weight: .regular, boldTraitWeight: .semibold),
        .callout: .init(size: 12, weight: .regular, boldTraitWeight: .semibold),
        .footnote: .init(size: 10, weight: .regular, boldTraitWeight: .semibold),
        .caption: .init(size: 10, weight: .regular, boldTraitWeight: .medium),
        .caption2: .init(size: 10, weight: .medium, boldTraitWeight: .semibold),
    ], defaultFont: .system(size: 13))
}

package struct PlatformProfileKey: EnvironmentKey {
    package static let defaultValue = PlatformProfile.macOS
}

extension EnvironmentValues {
    /// The platform whose look the runtime reproduces.
    public var platformProfile: PlatformProfile {
        get { self[PlatformProfileKey.self] }
        set { self[PlatformProfileKey.self] = newValue }
    }
}
