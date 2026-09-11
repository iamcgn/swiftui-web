// SwiftUI values from UIKit ones, as the iOS SDK offers them: `Color(uiColor:)`, `Image(uiImage:)`,
// `Font(_ uiFont:)`.
import SwiftUIWebCore
import UIKitWebCore

extension Color {
    /// Creates a color from a UIKit color, resolved for the light and dark appearances.
    public init(uiColor: UIColor) {
        self.init(storage: .dynamic(light: uiColor.light, dark: uiColor.dark))
    }

    /// The older spelling, without the argument label.
    public init(_ uiColor: UIColor) { self.init(uiColor: uiColor) }
}

extension Image {
    /// Creates a SwiftUI image from a UIKit image: the catalog image or symbol it names.
    public init(uiImage: UIImage) {
        let image = uiImage.isSystemSymbol ? Image(systemName: uiImage.name) : Image(uiImage.name)
        self = uiImage.renderingMode == .alwaysTemplate ? image.renderingMode(.template) : image
    }
}

extension Font {
    /// Creates a SwiftUI font from a UIKit font: the same text style, or the same size and weight.
    public init(_ uiFont: UIFont) {
        // UIFont's weight is the CSS weight UIKitWeb resolved it to.
        let weight = Font.Weight(uiFont.weight.css)
        if let style = uiFont.textStyle, let textStyle = Self.textStyle(for: style) {
            self = Font.system(textStyle, weight: uiFont.weight == .regular ? nil : weight)
        } else {
            self = Font.system(size: uiFont.pointSize, weight: weight)
        }
    }

    private static func textStyle(for style: UIFont.TextStyle) -> Font.TextStyle? {
        switch style {
        case .largeTitle: return .largeTitle
        case .title1: return .title
        case .title2: return .title2
        case .title3: return .title3
        case .headline: return .headline
        case .subheadline: return .subheadline
        case .body: return .body
        case .callout: return .callout
        case .footnote: return .footnote
        case .caption1: return .caption
        case .caption2: return .caption2
        default: return nil
        }
    }
}
