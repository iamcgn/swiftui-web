// UIFont (Docs/elements/UIKit/UIFont.md): the system font by size and weight, the text styles
// at the default content size, and the vertical metrics UILabel lays out with. The metrics are
// SF's hhea values (ascender 1950, descender 494, cap height 1443, x-height 1062 on a 2048
// em; line gap 0), the ratios UIKit reports for `systemFont(ofSize:)`, until a UIKit
// text-metrics recorder pins them per size.

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

    public static func boldSystemFont(ofSize size: CGFloat) -> UIFont { systemFont(ofSize: size, weight: .bold) }

    public static func italicSystemFont(ofSize size: CGFloat) -> UIFont {
        UIFont(resolved: ResolvedFont(family: "system", size: size, weight: .regular, italic: true, textStyle: nil, profile: "iOS"), weight: .regular)
    }

    public static func monospacedSystemFont(ofSize size: CGFloat, weight: Weight) -> UIFont {
        UIFont(resolved: ResolvedFont(family: "system-monospaced", size: size, weight: FontWeight(weight.css), italic: false, textStyle: nil, profile: "iOS"), weight: weight)
    }

    public static func monospacedDigitSystemFont(ofSize size: CGFloat, weight: Weight) -> UIFont {
        systemFont(ofSize: size, weight: weight)
    }

    public static func preferredFont(forTextStyle style: TextStyle) -> UIFont {
        let m = style.metrics
        return UIFont(resolved: ResolvedFont(family: "system", size: m.size, weight: FontWeight(m.weight.css), italic: false, textStyle: m.style, profile: "iOS"),
                      weight: m.weight, textStyle: style)
    }

    public convenience init?(name: String, size: CGFloat) {
        self.init(resolved: ResolvedFont(family: name, size: size, weight: .regular, italic: false, textStyle: nil, profile: "iOS"), weight: .regular)
    }

    public func withSize(_ size: CGFloat) -> UIFont {
        var font = resolved
        font.size = size
        return UIFont(resolved: font, weight: weight, textStyle: textStyle)
    }

    // MARK: Metrics

    public var pointSize: CGFloat { resolved.size }
    public var familyName: String { resolved.family.hasPrefix("system") ? ".AppleSystemUIFont" : resolved.family }
    public var fontName: String { familyName }
    /// SF's hhea ascender, descender (negative, as UIKit reports it), cap height and x-height.
    public var ascender: CGFloat { pointSize * 1950 / 2048 }
    public var descender: CGFloat { -pointSize * 494 / 2048 }
    public var capHeight: CGFloat { pointSize * 1443 / 2048 }
    public var xHeight: CGFloat { pointSize * 1062 / 2048 }
    public var leading: CGFloat { 0 }
    /// Ascender plus descender: the pitch of UILabel's lines.
    public var lineHeight: CGFloat { ascender - descender }
}
