// Dynamic Type (Docs/elements/UIKit/UIFont.md): the text styles at every content size category
// (Apple's typography table) and `UIFontMetrics`, which scales any font the way its text style
// scales between categories.

/// Scales fonts and values for a text style across the content size categories.
@MainActor
public final class UIFontMetrics {
    public let textStyle: UIFont.TextStyle
    public init(forTextStyle textStyle: UIFont.TextStyle) { self.textStyle = textStyle }

    /// The metrics of the body style.
    public static let `default` = UIFontMetrics(forTextStyle: .body)

    /// The style's point size at a category (Apple's table; the large category is the default).
    nonisolated static func pointSize(of style: UIFont.TextStyle, at category: UIContentSizeCategory) -> CGFloat {
        let index = UIContentSizeCategory.ordered.firstIndex(of: category) ?? 3
        let row: [CGFloat]
        switch style {
        //                        XS  S   M   L   XL  XXL XXXL AXM AXL AXXL AXXXL AXXXXL
        case .largeTitle:  row = [31, 32, 33, 34, 36, 38, 40, 44, 48, 52, 56, 60]
        case .title1:      row = [25, 26, 27, 28, 30, 32, 34, 38, 43, 48, 53, 58]
        case .title2:      row = [19, 20, 21, 22, 24, 26, 28, 34, 39, 44, 50, 56]
        case .title3:      row = [17, 18, 19, 20, 22, 24, 26, 31, 37, 43, 49, 55]
        case .headline:    row = [14, 15, 16, 17, 19, 21, 23, 28, 33, 40, 47, 53]
        case .body:        row = [14, 15, 16, 17, 19, 21, 23, 28, 33, 40, 47, 53]
        case .callout:     row = [13, 14, 15, 16, 18, 20, 22, 26, 32, 38, 44, 51]
        case .subheadline: row = [12, 13, 14, 15, 17, 19, 21, 25, 30, 36, 42, 49]
        case .footnote:    row = [12, 12, 12, 13, 15, 17, 19, 23, 27, 33, 38, 44]
        case .caption1:    row = [11, 11, 11, 12, 14, 16, 18, 22, 26, 32, 37, 43]
        case .caption2:    row = [11, 11, 11, 11, 13, 15, 17, 20, 24, 29, 34, 40]
        default:           row = [14, 15, 16, 17, 19, 21, 23, 28, 33, 40, 47, 53]
        }
        return row[min(max(index, 0), row.count - 1)]
    }

    /// How much the style grows from its default size at `category`.
    nonisolated func scale(for category: UIContentSizeCategory) -> CGFloat {
        Self.pointSize(of: textStyle, at: category) / Self.pointSize(of: textStyle, at: .large)
    }

    /// `font` scaled for the current content size category.
    public func scaledFont(for font: UIFont) -> UIFont { scaledFont(for: font, compatibleWith: UITraitCollection.current) }

    public func scaledFont(for font: UIFont, maximumPointSize: CGFloat) -> UIFont {
        scaledFont(for: font, maximumPointSize: maximumPointSize, compatibleWith: UITraitCollection.current)
    }

    public func scaledFont(for font: UIFont, compatibleWith traitCollection: UITraitCollection?) -> UIFont {
        scaledFont(for: font, maximumPointSize: .greatestFiniteMagnitude, compatibleWith: traitCollection)
    }

    /// The font at the size the style's growth gives (16 pt with the body metrics is 19 at the
    /// XXL category, uikit/label/fonts: the product rounded down to the point), capped.
    public func scaledFont(for font: UIFont, maximumPointSize: CGFloat, compatibleWith traitCollection: UITraitCollection?) -> UIFont {
        let category = traitCollection?.preferredContentSizeCategory ?? .large
        let size = min((font.pointSize * scale(for: category == .unspecified ? .large : category)).rounded(.down), maximumPointSize)
        return size == font.pointSize ? font : font.withSize(size)
    }

    public func scaledValue(for value: CGFloat) -> CGFloat { scaledValue(for: value, compatibleWith: UITraitCollection.current) }

    public func scaledValue(for value: CGFloat, compatibleWith traitCollection: UITraitCollection?) -> CGFloat {
        let category = traitCollection?.preferredContentSizeCategory ?? .large
        return value * scale(for: category == .unspecified ? .large : category)
    }
}

extension UIFont {
    /// The text style sized for the traits' content size category: at the large category the
    /// measured style font, elsewhere the system font at the table's size (its line metrics
    /// follow the sized-font rules, the style's own metrics being measured for large only).
    nonisolated public static func preferredFont(forTextStyle style: TextStyle, compatibleWith traitCollection: UITraitCollection?) -> UIFont {
        let category = traitCollection?.preferredContentSizeCategory ?? .large
        if category == .large || category == .unspecified { return preferredFont(forTextStyle: style) }
        let size = UIFontMetrics.pointSize(of: style, at: category)
        let m = style.metrics
        return UIFont(resolved: ResolvedFont(family: "system", size: size, weight: FontWeight(m.weight.css), italic: false, textStyle: m.style, profile: "iOS", sizeCategory: category.shortName),
                      weight: m.weight, textStyle: style, scaledCategory: category)
    }

    /// The bundled font families (`UIFont(name:size:)` resolves them) and the system families.
    @MainActor public static var familyNames: [String] {
        Array(Set(UIKitScene.shared.assetCatalog.fonts.values.map(\.family))).sorted() + ["System Font"]
    }

    @MainActor public static func fontNames(forFamilyName familyName: String) -> [String] {
        UIKitScene.shared.assetCatalog.fonts.values.filter { $0.family == familyName }.map(\.postScriptName).sorted()
    }
}
