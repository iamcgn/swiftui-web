/// Platform constants that SwiftUI does not document. Every value here must be backed by a
/// fixture in `Fixtures/Sources` and recorded in `Docs/elements/`; until measured, a value is
/// marked `// unverified`.
package enum PlatformMetrics {
    /// `.padding()` with no length.
    package static let defaultPadding: CGFloat = 16          // macOS 26.2: fixture layout/padding-default
    /// Default stack spacing and `Spacer` minimum length.
    package static let defaultSpacing: CGFloat = 8           // macOS 26.2: fixtures layout/spacing-default, layout/spacer-min-length
    /// `Divider` thickness.
    package static let dividerThickness: CGFloat = 1         // macOS 26.2: fixture layout/divider
    /// Weight the bold trait (`Font.bold()`, `Text.bold()`) resolves to.
    package static let boldTraitWeight: Font.Weight = .semibold   // macOS 26.2: fixture text/modifiers

    // Bordered buttons (macOS 26.2: fixtures button/basic, button/styles; pixels sampled from goldens)
    package static let buttonHeight: CGFloat = 24
    package static let buttonHorizontalPadding: CGFloat = 12
    package static let buttonLabelSize: CGFloat = 13              // label line is 16 pt: point-size metrics, not .body
    package static let buttonCornerRadius: CGFloat = 6
    package static let buttonFill = Color(red: 0, green: 0, blue: 0, opacity: 19.0 / 255)
    package static let buttonPressedFill = Color(red: 0, green: 0, blue: 0, opacity: 50.0 / 255)   // unverified
}
