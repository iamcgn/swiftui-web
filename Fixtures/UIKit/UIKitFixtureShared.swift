// Shared between the Apple harness (real UIKit on Mac Catalyst) and UIKitWeb: the fonts and
// text requests the UIKit fixtures use, spelled so both sides build the same UIFont and the
// same recording key (`ResolvedFont.key` in WebGraphics).
#if canImport(UIKit)
import UIKit

/// A font spelled in a toolchain-neutral way.
public enum UIKitFixtureFont: Hashable, Sendable {
    /// "largeTitle", "title", "title2", "title3", "headline", "subheadline", "body", "callout", "footnote", "caption", "caption2".
    case style(String)
    /// A point size and a weight name ("regular", "semibold", "bold", …).
    case system(size: CGFloat, weight: String = "regular")
    /// `monospacedDigitSystemFont(ofSize:weight:)`: the system font with tabular figures.
    case monospacedDigit(size: CGFloat, weight: String = "regular")
    /// `italicSystemFont(ofSize:)`.
    case italic(size: CGFloat)
    /// `monospacedSystemFont(ofSize:weight:)` (SF Mono).
    case monospaced(size: CGFloat, weight: String = "regular")
    /// `UIFont(name:size:)` for a bundled font (Fixtures/Fonts).
    case custom(name: String, size: CGFloat)
    /// `preferredFont(forTextStyle:compatibleWith:)` at a content size category ("XS", "S", "M",
    /// "L", "XL", "XXL", "XXXL", "AXM", "AXL", "AXXL", "AXXXL", "AXXXXL").
    case scaledStyle(String, category: String)
    /// `UIFontMetrics(forTextStyle:).scaledFont(for: systemFont(ofSize:), compatibleWith:)`.
    case scaled(size: CGFloat, style: String, category: String)

    public static let categories: [String: UIContentSizeCategory] = [
        "XS": .extraSmall, "S": .small, "M": .medium, "L": .large, "XL": .extraLarge, "XXL": .extraExtraLarge, "XXXL": .extraExtraExtraLarge,
        "AXM": .accessibilityMedium, "AXL": .accessibilityLarge, "AXXL": .accessibilityExtraLarge, "AXXXL": .accessibilityExtraExtraLarge, "AXXXXL": .accessibilityExtraExtraExtraLarge,
    ]

    public static let weights: [String: (UIFont.Weight, Int)] = [
        "ultraLight": (.ultraLight, 100), "thin": (.thin, 200), "light": (.light, 300), "regular": (.regular, 400),
        "medium": (.medium, 500), "semibold": (.semibold, 600), "bold": (.bold, 700), "heavy": (.heavy, 800), "black": (.black, 900),
    ]

    public static let styles: [String: UIFont.TextStyle] = [
        "largeTitle": .largeTitle, "title": .title1, "title2": .title2, "title3": .title3, "headline": .headline,
        "subheadline": .subheadline, "body": .body, "callout": .callout, "footnote": .footnote, "caption": .caption1, "caption2": .caption2,
    ]

    /// The recording key (`ResolvedFont.key`): `style:<name>` or `system:<size>:<weight>:default`.
    public var key: String {
        switch self {
        case .style(let name): return "style:\(name)"
        case .system(let size, let weight):
            let sizeText = size == size.rounded() ? "\(Int(size))" : "\(size)"
            return "system:\(sizeText):\(Self.weights[weight]!.1):default"
        case .monospacedDigit(let size, let weight):
            let sizeText = size == size.rounded() ? "\(Int(size))" : "\(size)"
            return "system:\(sizeText):\(Self.weights[weight]!.1):default:tabular"
        case .italic(let size):
            return "system:\(Self.sizeText(size)):400:default:italic"
        case .monospaced(let size, let weight):
            return "system:\(Self.sizeText(size)):\(Self.weights[weight]!.1):monospaced"
        case .custom(let name, let size):
            return "custom:\(name):\(Self.sizeText(size)):400"
        case .scaledStyle(let name, let category):
            return "style:\(name):\(category)"
        case .scaled(let size, let style, let category):
            // `UIFontMetrics` gives a plain system font: its key is the scaled size's.
            _ = (size, style, category)
            return MainActor.assumeIsolated { "system:\(Self.sizeText(uiFont.pointSize)):400:default" }
        }
    }

    static func sizeText(_ size: CGFloat) -> String { size == size.rounded() ? "\(Int(size))" : "\(size)" }

    @MainActor public var uiFont: UIFont {
        switch self {
        case .style(let name): return UIFont.preferredFont(forTextStyle: Self.styles[name]!)
        case .system(let size, let weight): return UIFont.systemFont(ofSize: size, weight: Self.weights[weight]!.0)
        case .monospacedDigit(let size, let weight): return UIFont.monospacedDigitSystemFont(ofSize: size, weight: Self.weights[weight]!.0)
        case .italic(let size): return UIFont.italicSystemFont(ofSize: size)
        case .monospaced(let size, let weight): return UIFont.monospacedSystemFont(ofSize: size, weight: Self.weights[weight]!.0)
        case .custom(let name, let size): return UIFont(name: name, size: size) ?? UIFont.systemFont(ofSize: size)
        case .scaledStyle(let name, let category):
            return UIFont.preferredFont(forTextStyle: Self.styles[name]!, compatibleWith: UITraitCollection(preferredContentSizeCategory: Self.categories[category]!))
        case .scaled(let size, let style, let category):
            return UIFontMetrics(forTextStyle: Self.styles[style]!).scaledFont(for: UIFont.systemFont(ofSize: size), compatibleWith: UITraitCollection(preferredContentSizeCategory: Self.categories[category]!))
        }
    }
}

/// One string measured in one font the way a `UILabel` measures it: `lines` is the label's
/// `numberOfLines` (0: as many as the text needs), `width` the width it is fitted to (nil:
/// unbounded). A text field's text is measured with `lines: 0` (no line limit) and no width.
public struct UIKitTextRequest: Hashable, Sendable {
    /// One run of an attributed request.
    public struct Run: Hashable, Sendable {
        public let string: String
        public let font: UIKitFixtureFont
        public init(_ string: String, _ font: UIKitFixtureFont) {
            self.string = string
            self.font = font
        }
    }

    public let runs: [Run]
    public let width: CGFloat?
    public let lines: Int

    public init(_ string: String, _ font: UIKitFixtureFont, width: CGFloat? = nil, lines: Int = 1) {
        runs = [Run(string, font)]
        self.width = width
        self.lines = lines
    }

    /// An attributed string of several runs (a `UILabel`'s `attributedText`).
    public init(runs: [Run], width: CGFloat? = nil, lines: Int = 1) {
        self.runs = runs
        self.width = width
        self.lines = lines
    }

    public var string: String { runs.map(\.string).joined() }
    public var font: UIKitFixtureFont { runs[0].font }

    /// `<font>|<width>[;l<lines>]|<string>`, as `TextMetricsKey` spells the request UIKitWeb's
    /// `UILabel` makes (the width slot is empty when unbounded; a line limit of 0 adds nothing);
    /// several runs spell `rich:<font>=<characters>,…` in the font slot.
    public var key: String {
        let fontSlot = runs.count == 1 ? runs[0].font.key : "rich:" + runs.map { "\($0.font.key)=\($0.string.count)" }.joined(separator: ",")
        return "\(fontSlot)|\(width.map { "\($0)" } ?? "")\(lines > 0 ? ";l\(lines)" : "")|\(string)"
    }
}
#endif
