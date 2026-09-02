/// Per-platform metrics and defaults. macOS is the reference profile (goldens come from a Mac);
/// iOS arrives later behind the same table.
public struct PlatformProfile: Sendable {
    public struct TextStyleMetrics: Sendable, Equatable {
        public var size: CGFloat
        public var weight: Font.Weight
        public init(size: CGFloat, weight: Font.Weight) { self.size = size; self.weight = weight }
    }

    public var name: String
    package var textStyles: [Font.TextStyle: TextStyleMetrics]

    package func textStyle(_ style: Font.TextStyle) -> TextStyleMetrics {
        textStyles[style] ?? TextStyleMetrics(size: 13, weight: .regular)
    }

    /// macOS text styles (Apple HIG typography table, default dynamic type size).
    public static let macOS = PlatformProfile(name: "macOS", textStyles: [
        .largeTitle: .init(size: 26, weight: .regular),
        .title: .init(size: 22, weight: .regular),
        .title2: .init(size: 17, weight: .regular),
        .title3: .init(size: 15, weight: .regular),
        .headline: .init(size: 13, weight: .bold),
        .subheadline: .init(size: 11, weight: .regular),
        .body: .init(size: 13, weight: .regular),
        .callout: .init(size: 12, weight: .regular),
        .footnote: .init(size: 10, weight: .regular),
        .caption: .init(size: 10, weight: .regular),
        .caption2: .init(size: 10, weight: .medium),
    ])
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
