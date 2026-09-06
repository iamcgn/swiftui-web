// The font values the text engine and the display list name: text styles and weights
// (`Font.TextStyle` and `Font.Weight` in SwiftUI, `UIFont.TextStyle` and `UIFont.Weight` in UIKit).

/// Dynamic text styles.
public enum FontTextStyle: Hashable, Sendable, CaseIterable {
    case largeTitle, title, title2, title3, headline, subheadline, body, callout, footnote, caption, caption2
}

/// A weight to use for fonts.
public struct FontWeight: Hashable, Sendable {
    public let value: Int   // 100…900 in CSS terms
    public init(_ value: Int) { self.value = value }
    public static let ultraLight = FontWeight(100)
    public static let thin = FontWeight(200)
    public static let light = FontWeight(300)
    public static let regular = FontWeight(400)
    public static let medium = FontWeight(500)
    public static let semibold = FontWeight(600)
    public static let bold = FontWeight(700)
    public static let heavy = FontWeight(800)
    public static let black = FontWeight(900)
}
