/// One run of a text view: a string in a single resolved font. `Text` concatenation produces
/// several; a plain `Text` produces one.
public struct StyledRun: Hashable, Sendable {
    public var string: String
    public var font: ResolvedFont

    public init(_ string: String, font: ResolvedFont) {
        self.string = string
        self.font = font
    }
}

/// Environment-driven layout options of a text view (`lineLimit`, `truncationMode`,
/// `lineSpacing`). Alignment is not here: it moves lines but does not change the layout.
public struct TextLayoutOptions: Hashable, Sendable {
    public var lineLimit: Int?
    public var truncationMode: Text.TruncationMode
    public var lineSpacing: CGFloat
    /// Lines whose space is reserved even for shorter text: `lineLimit(n, reservesSpace: true)`
    /// reserves `n`, `lineLimit(a...b)` and `lineLimit(a...)` reserve `a`; 0 reserves nothing.
    public var minimumLines: Int
    /// Extra space between characters (`kerning`) and `tracking`, in points.
    public var kerning: CGFloat
    public var tracking: CGFloat
    /// `textScale`: the secondary scale draws smaller glyphs on the font's own line height.
    public var textScale: Text.Scale

    /// The same options with the letter spacing taken out (the layouter measures it itself).
    public var withoutLetterSpacing: TextLayoutOptions {
        var copy = self
        copy.kerning = 0
        copy.tracking = 0
        return copy
    }

    public init(lineLimit: Int? = nil, truncationMode: Text.TruncationMode = .tail, lineSpacing: CGFloat = 0, minimumLines: Int = 0,
                kerning: CGFloat = 0, tracking: CGFloat = 0, textScale: Text.Scale = .default) {
        self.lineLimit = lineLimit
        self.truncationMode = truncationMode
        self.lineSpacing = lineSpacing
        self.minimumLines = minimumLines
        self.kerning = kerning
        self.tracking = tracking
        self.textScale = textScale
    }

    public static let `default` = TextLayoutOptions()
    public var isDefault: Bool { self == .default }
}

/// Result of laying out a run of text.
public struct TextLayout: Equatable, Sendable {
    /// A piece of one line drawn in one font: the text as displayed (an ellipsis may replace
    /// truncated characters), the index of the run it belongs to, and its position within the line.
    public struct Fragment: Equatable, Sendable {
        public var text: String
        public var run: Int
        public var x: CGFloat
        public var width: CGFloat
        public init(text: String, run: Int, x: CGFloat, width: CGFloat) {
            self.text = text
            self.run = run
            self.x = x
            self.width = width
        }
    }

    public struct Line: Equatable, Sendable {
        /// The characters of the joined string this line shows (before truncation).
        public var range: Range<String.Index>
        /// The width the line reports for layout: SwiftUI includes a wrapped line's trailing space.
        public var width: CGFloat
        /// The width of the glyphs actually drawn (trailing spaces excluded); alignment uses it.
        public var inkWidth: CGFloat
        public var baseline: CGFloat      // y of the baseline from the top of the layout
        public var fragments: [Fragment]

        public init(range: Range<String.Index>, width: CGFloat, inkWidth: CGFloat? = nil, baseline: CGFloat, fragments: [Fragment]) {
            self.range = range
            self.width = width
            self.inkWidth = inkWidth ?? width
            self.baseline = baseline
            self.fragments = fragments
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

    /// A layout with one line holding every run in order at the given fragment positions.
    public static func singleLine(_ runs: [StyledRun], size: CGSize, baseline: CGFloat, runWidths: [CGFloat]) -> TextLayout {
        let string = runs.map(\.string).joined()
        var fragments: [Fragment] = []
        var x: CGFloat = 0
        for (index, run) in runs.enumerated() {
            let width = index < runWidths.count ? runWidths[index] : 0
            fragments.append(Fragment(text: run.string, run: index, x: x, width: width))
            x += width
        }
        let line = Line(range: string.startIndex..<string.endIndex, width: size.width, baseline: baseline, fragments: fragments)
        return TextLayout(size: size, firstBaseline: baseline, lastBaseline: baseline, lines: [line])
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
    /// Lays out `runs` (in order, as one paragraph) with `options`, wrapping at `width` when given.
    func layout(_ runs: [StyledRun], options: TextLayoutOptions, width: CGFloat?) -> TextLayout

    /// String-independent metrics of `font`.
    func metrics(for font: ResolvedFont) -> FontMetrics
}

extension TextEngine {
    /// Lays out a single string in one font.
    public func layout(_ string: String, font: ResolvedFont, width: CGFloat?) -> TextLayout {
        layout([StyledRun(string, font: font)], options: .default, width: width)
    }
}

/// The key under which the fixture harness records a text measurement
/// (`Fixtures/Goldens/text-metrics.json`). Must match `TextMetricRequest.key` in
/// `Fixtures/Sources/TextMetrics/TextMetricsRequests.swift`:
/// `<font>|<width>[;l<lineLimit>][;r<minimumLines>][;s<lineSpacing>][;t<head|middle>]|<string>`, where `<font>` is
/// `ResolvedFont.key` for one font and `rich:<key>=<count>,…` for a mixed-font text (adjacent
/// runs in the same font merged; count = characters of each run).
public enum TextMetricsKey {
    public static func make(runs: [StyledRun], options: TextLayoutOptions, width: CGFloat?) -> String {
        "\(fontSlot(runs))|\(widthSlot(width: width, options: options))|\(runs.map(\.string).joined())"
    }

    public static func fontSlot(_ runs: [StyledRun]) -> String {
        let merged = mergedByFont(runs)
        if merged.count == 1 { return merged[0].font.key }
        return "rich:" + merged.map { "\($0.font.key)=\($0.string.count)" }.joined(separator: ",")
    }

    public static func widthSlot(width: CGFloat?, options: TextLayoutOptions) -> String {
        var slot = width.map { "\($0)" } ?? ""
        if let limit = options.lineLimit { slot += ";l\(limit)" }
        if options.minimumLines > 0 { slot += ";r\(options.minimumLines)" }
        if options.lineSpacing != 0 { slot += ";s\(options.lineSpacing)" }
        switch options.truncationMode {
        case .tail: break
        case .head: slot += ";thead"
        case .middle: slot += ";tmiddle"
        }
        if options.kerning != 0 { slot += ";k\(options.kerning)" }
        if options.tracking != 0 { slot += ";tr\(options.tracking)" }
        if options.textScale == .secondary { slot += ";sc2" }
        return slot
    }

    /// Adjacent runs in the same font joined (colour differences do not affect measurement).
    public static func mergedByFont(_ runs: [StyledRun]) -> [StyledRun] {
        var merged: [StyledRun] = []
        for run in runs {
            if let last = merged.last, last.font == run.font {
                merged[merged.count - 1].string += run.string
            } else {
                merged.append(run)
            }
        }
        return merged
    }
}

/// Engine used until a host installs a real one: everything measures as zero, so layout tests
/// that do not involve text keep working and text tests fail loudly on size.
@MainActor
package final class ZeroTextEngine: TextEngine {
    package init() {}
    package func layout(_ runs: [StyledRun], options: TextLayoutOptions, width: CGFloat?) -> TextLayout {
        TextLayout(size: .zero, firstBaseline: 0, lastBaseline: 0, lines: [])
    }
    package func metrics(for font: ResolvedFont) -> FontMetrics { .plain }
}
