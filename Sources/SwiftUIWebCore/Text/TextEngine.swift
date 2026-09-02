/// Result of laying out a run of text.
public struct TextLayout: Equatable, Sendable {
    public struct Line: Equatable, Sendable {
        public var range: Range<String.Index>
        public var width: CGFloat
        public var baseline: CGFloat      // y of the baseline from the top of the layout
        public init(range: Range<String.Index>, width: CGFloat, baseline: CGFloat) {
            self.range = range
            self.width = width
            self.baseline = baseline
        }
    }

    public var size: CGSize
    public var firstBaseline: CGFloat
    public var lastBaseline: CGFloat
    public var lines: [Line]

    public init(size: CGSize, firstBaseline: CGFloat, lastBaseline: CGFloat, lines: [Line]) {
        self.size = size
        self.firstBaseline = firstBaseline
        self.lastBaseline = lastBaseline
        self.lines = lines
    }
}

/// Per-font values that do not depend on the string.
public struct FontMetrics: Equatable, Sendable {
    /// Height of one line of this font as SwiftUI lays it out.
    public var lineHeight: CGFloat
    /// Stack spacing a run of this font wants towards a non-text neighbour below / above it,
    /// and towards another text run below it.
    public var spacingBelow: CGFloat
    public var spacingAbove: CGFloat
    public var textToText: CGFloat

    public init(lineHeight: CGFloat, spacingBelow: CGFloat, spacingAbove: CGFloat, textToText: CGFloat) {
        self.lineHeight = lineHeight
        self.spacingBelow = spacingBelow
        self.spacingAbove = spacingAbove
        self.textToText = textToText
    }

    /// Non-text neighbours' defaults, so an engine without font data behaves like plain views.
    public static let plain = FontMetrics(lineHeight: 0, spacingBelow: 8, spacingAbove: 8, textToText: 8)
}

/// What a text run needs from the platform: measurement and line breaking.
@MainActor
public protocol TextEngine: AnyObject {
    /// Lays out `string` in `font`, wrapping at `width` when given.
    func layout(_ string: String, font: ResolvedFont, width: CGFloat?) -> TextLayout

    /// String-independent metrics of `font`.
    func metrics(for font: ResolvedFont) -> FontMetrics
}

/// Engine used until a host installs a real one: everything measures as zero, so layout tests
/// that do not involve text keep working and text tests fail loudly on size.
@MainActor
package final class ZeroTextEngine: TextEngine {
    package init() {}
    package func layout(_ string: String, font: ResolvedFont, width: CGFloat?) -> TextLayout {
        TextLayout(size: .zero, firstBaseline: 0, lastBaseline: 0, lines: [])
    }
    package func metrics(for font: ResolvedFont) -> FontMetrics { .plain }
}
