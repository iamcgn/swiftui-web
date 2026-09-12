// UIFont (Docs/elements/UIKit/UIFont.md): the system font by size and weight, the text styles
// at the default content size, and the vertical metrics UILabel lays out with, as UIKit reports
// them on an iPhone (UIFontMetricsTable, generated from Fixtures/Goldens/uikit/font-metrics.json).

/// A font as UIKit describes it: a resolved font for the text engine plus UIKit's metrics.
public final class UIFont: Hashable, @unchecked Sendable {
    /// A weight of the system font.
    public struct Weight: Hashable, Sendable, RawRepresentable {
        public let rawValue: CGFloat
        public init(rawValue: CGFloat) { self.rawValue = rawValue }
        public init(_ rawValue: CGFloat) { self.rawValue = rawValue }
        public static let ultraLight = Weight(-0.8)
        public static let thin = Weight(-0.6)
        public static let light = Weight(-0.4)
        public static let regular = Weight(0)
        public static let medium = Weight(0.23)
        public static let semibold = Weight(0.3)
        public static let bold = Weight(0.4)
        public static let heavy = Weight(0.56)
        public static let black = Weight(0.62)

        /// The CSS weight (100…900) the text engine uses.
        public var css: Int {
            switch rawValue {
            case ..<(-0.7): return 100
            case ..<(-0.5): return 200
            case ..<(-0.2): return 300
            case ..<0.115: return 400
            case ..<0.265: return 500
            case ..<0.35: return 600
            case ..<0.48: return 700
            case ..<0.59: return 800
            default: return 900
            }
        }
    }

    /// The text styles, sized for the default (large) content size category.
    public struct TextStyle: Hashable, Sendable, RawRepresentable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public static let largeTitle = TextStyle(rawValue: "UICTFontTextStyleTitle0")
        public static let title1 = TextStyle(rawValue: "UICTFontTextStyleTitle1")
        public static let title2 = TextStyle(rawValue: "UICTFontTextStyleTitle2")
        public static let title3 = TextStyle(rawValue: "UICTFontTextStyleTitle3")
        public static let headline = TextStyle(rawValue: "UICTFontTextStyleHeadline")
        public static let subheadline = TextStyle(rawValue: "UICTFontTextStyleSubhead")
        public static let body = TextStyle(rawValue: "UICTFontTextStyleBody")
        public static let callout = TextStyle(rawValue: "UICTFontTextStyleCallout")
        public static let footnote = TextStyle(rawValue: "UICTFontTextStyleFootnote")
        public static let caption1 = TextStyle(rawValue: "UICTFontTextStyleCaption1")
        public static let caption2 = TextStyle(rawValue: "UICTFontTextStyleCaption2")

        /// Size and weight at the large content size (Apple's HIG typography table).
        var metrics: (size: CGFloat, weight: Weight, style: FontTextStyle) {
            switch self {
            case .largeTitle: return (34, .regular, .largeTitle)
            case .title1: return (28, .regular, .title)
            case .title2: return (22, .regular, .title2)
            case .title3: return (20, .regular, .title3)
            case .headline: return (17, .semibold, .headline)
            case .subheadline: return (15, .regular, .subheadline)
            case .callout: return (16, .regular, .callout)
            case .footnote: return (13, .regular, .footnote)
            case .caption1: return (12, .regular, .caption)
            case .caption2: return (11, .regular, .caption2)
            default: return (17, .regular, .body)
            }
        }

        /// The style's name in the measured tables.
        var tableName: String {
            switch self {
            case .largeTitle: return "largeTitle"
            case .title1: return "title"
            case .title2: return "title2"
            case .title3: return "title3"
            case .headline: return "headline"
            case .subheadline: return "subheadline"
            case .callout: return "callout"
            case .footnote: return "footnote"
            case .caption1: return "caption"
            case .caption2: return "caption2"
            default: return "body"
            }
        }
    }

    /// The font as the text engine measures and paints it.
    public let resolved: ResolvedFont
    public let weight: Weight
    /// The text style this font was made for, if any (`preferredFont(forTextStyle:)`).
    public let textStyle: TextStyle?

    init(resolved: ResolvedFont, weight: Weight, textStyle: TextStyle? = nil) {
        self.resolved = resolved
        self.weight = weight
        self.textStyle = textStyle
    }

    public static func == (lhs: UIFont, rhs: UIFont) -> Bool { lhs.resolved == rhs.resolved }
    public func hash(into hasher: inout Hasher) { hasher.combine(resolved) }

    // MARK: Factories

    public static func systemFont(ofSize size: CGFloat, weight: Weight = .regular) -> UIFont {
        UIFont(resolved: ResolvedFont(family: "system", size: size, weight: FontWeight(weight.css), italic: false, textStyle: nil, profile: "iOS"), weight: weight)
    }

    /// SF Semibold, as iOS resolves the bold system font (`systemFont(ofSize:weight: .bold)` is Bold).
    public static func boldSystemFont(ofSize size: CGFloat) -> UIFont { systemFont(ofSize: size, weight: .semibold) }

    public static func italicSystemFont(ofSize size: CGFloat) -> UIFont {
        UIFont(resolved: ResolvedFont(family: "system", size: size, weight: .regular, italic: true, textStyle: nil, profile: "iOS"), weight: .regular)
    }

    public static func monospacedSystemFont(ofSize size: CGFloat, weight: Weight) -> UIFont {
        UIFont(resolved: ResolvedFont(family: "system-monospaced", size: size, weight: FontWeight(weight.css), italic: false, textStyle: nil, profile: "iOS"), weight: weight)
    }

    /// The system font with tabular figures (every digit on one advance; uikit/label/tabular).
    public static func monospacedDigitSystemFont(ofSize size: CGFloat, weight: Weight) -> UIFont {
        UIFont(resolved: ResolvedFont(family: "system", size: size, weight: FontWeight(weight.css), italic: false, textStyle: nil, profile: "iOS", tabularDigits: true), weight: weight)
    }

    public static func preferredFont(forTextStyle style: TextStyle) -> UIFont {
        let m = style.metrics
        return UIFont(resolved: ResolvedFont(family: "system", size: m.size, weight: FontWeight(m.weight.css), italic: false, textStyle: m.style, profile: "iOS"),
                      weight: m.weight, textStyle: style)
    }

    public convenience init?(name: String, size: CGFloat) {
        self.init(resolved: ResolvedFont(family: name, size: size, weight: .regular, italic: false, textStyle: nil, profile: "iOS"), weight: .regular)
    }

    /// The same face at another size: a plain font, as UIKit returns (a text style's metrics
    /// belong to its own size).
    public func withSize(_ size: CGFloat) -> UIFont {
        var font = resolved
        font.size = size
        font.textStyle = nil
        return UIFont(resolved: font, weight: weight, textStyle: nil)
    }

    // MARK: Metrics (Docs/elements/UIKit/UIFont.md)

    public var pointSize: CGFloat { resolved.size }
    public var familyName: String { resolved.family.hasPrefix("system") ? ".AppleSystemUIFont" : resolved.family }
    public var fontName: String { familyName }

    /// A text style's measured metrics (nil for a sized font).
    private var styleMetrics: UIFontMetricsTable.TextStyleMetrics? {
        textStyle.flatMap { UIFontMetricsTable.textStyles[$0.tableName] }
    }

    /// SF's hhea ratios of the point size for a sized font; a text style's own values.
    public var ascender: CGFloat { styleMetrics?.ascender ?? pointSize * UIFontMetricsTable.ascender }
    /// Negative, as UIKit reports it.
    public var descender: CGFloat { styleMetrics?.descender ?? -pointSize * UIFontMetricsTable.descender }
    public var capHeight: CGFloat { styleMetrics?.capHeight ?? pointSize * UIFontMetricsTable.capHeight }
    /// Per weight and size: SF's optical sizes lower the x-height from 18 pt up.
    public var xHeight: CGFloat {
        if let styleMetrics { return styleMetrics.xHeight }
        let table = UIFontMetricsTable.xHeight[weight.css] ?? UIFontMetricsTable.xHeight[400]!
        let index = min(max(Int(pointSize.rounded()) - 6, 0), table.count - 1)
        return pointSize * CGFloat(table[index]) / 2048
    }
    /// Zero for a sized font; a text style's leading spaces its lines (caption2's is negative).
    public var leading: CGFloat { styleMetrics?.leading ?? 0 }
    /// Ascender minus descender, unrounded, for every font.
    public var lineHeight: CGFloat { ascender - descender }

    /// The height a UILabel takes for `lines` lines: the line heights plus the leadings between
    /// them, rounded up to the pixel (20.5 for one 17 pt line, 41 for two; body 24.5 and 50.5).
    func labelHeight(lines: Int, scale: CGFloat) -> CGFloat {
        (lineHeight * CGFloat(lines) + leading * CGFloat(lines - 1)).roundedUp(to: scale)
    }
}
