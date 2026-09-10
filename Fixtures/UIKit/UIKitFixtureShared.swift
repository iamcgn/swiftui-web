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
        }
    }

    @MainActor public var uiFont: UIFont {
        switch self {
        case .style(let name): return UIFont.preferredFont(forTextStyle: Self.styles[name]!)
        case .system(let size, let weight): return UIFont.systemFont(ofSize: size, weight: Self.weights[weight]!.0)
        }
    }
}

/// One string measured in one font the way a `UILabel` measures it: `lines` is the label's
/// `numberOfLines` (0: as many as the text needs), `width` the width it is fitted to (nil:
/// unbounded). A text field's text is measured with `lines: 0` (no line limit) and no width.
public struct UIKitTextRequest: Hashable, Sendable {
    public let string: String
    public let font: UIKitFixtureFont
    public let width: CGFloat?
    public let lines: Int

    public init(_ string: String, _ font: UIKitFixtureFont, width: CGFloat? = nil, lines: Int = 1) {
        self.string = string
        self.font = font
        self.width = width
        self.lines = lines
    }

    /// `<font>|<width>[;l<lines>]|<string>`, as `TextMetricsKey` spells the request UIKitWeb's
    /// `UILabel` makes (the width slot is empty when unbounded; a line limit of 0 adds nothing).
    public var key: String { "\(font.key)|\(width.map { "\($0)" } ?? "")\(lines > 0 ? ";l\(lines)" : "")|\(string)" }
}
#endif
