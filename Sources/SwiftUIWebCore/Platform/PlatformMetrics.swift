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

    // Bordered buttons (macOS 26.2: fixtures button/basic, button/styles; pixels sampled from goldens)
    package static let buttonHeight: CGFloat = 24
    package static let buttonHorizontalPadding: CGFloat = 12
    package static let buttonLabelSize: CGFloat = 13              // label line is 16 pt: point-size metrics, not .body
    package static let buttonCornerRadius: CGFloat = 6
    package static let buttonFill = Color(red: 0, green: 0, blue: 0, opacity: 19.0 / 255)
    package static let buttonPressedFill = Color(red: 0, green: 0, blue: 0, opacity: 50.0 / 255)   // unverified
    /// A bordered button is its label plus 4 pt above and below (32 for a 24 pt Label, label/basic).
    package static let buttonVerticalPadding: CGFloat = 4

    // Toggle (macOS 26.2: fixtures toggle/basic, toggle/styles; pixels sampled from goldens, Docs/elements/Toggle.md)
    package static let checkboxSize: CGFloat = 16
    package static let checkboxLabelSpacing: CGFloat = 5
    package static let checkboxCornerRadius: CGFloat = 5                // from the corner ramp at 2×, approximate
    package static let checkboxFillOn = 36.0 / 255
    package static let checkboxFillOff = 25.0 / 255
    package static let checkboxDisabledFillOn = 18.0 / 255              // approximate
    package static let checkboxDisabledFillOff = 13.0 / 255
    package static let checkMarkWidth: CGFloat = 2                       // approximate
    package static let checkMarkAlpha = 222.0 / 255
    package static let checkMarkDisabledAlpha = 66.0 / 255               // approximate
    package static let switchSize = CGSize(width: 54, height: 24)
    package static let switchKnobSize = CGSize(width: 32, height: 20)
    package static let switchKnobInset: CGFloat = 2
    package static let switchLabelSpacing: CGFloat = 8
    package static let switchTrackOn = 36.0 / 255
    package static let switchTrackOff = 25.0 / 255
    /// Disabled control labels keep 30 % of their alpha (66/216 for the primary label colour).
    package static let disabledLabelOpacity = 0.3

    // Label (macOS 26.2: fixture label/basic, Docs/elements/Label.md)
    package static let labelIconSpacing: CGFloat = 8

    // Scrolling (Docs/elements/ScrollView.md). Overlay scrollers only show while scrolling, so the
    // goldens cannot verify them; the values approximate macOS 26 overlay scrollers.
    package static let scrollerThickness: CGFloat = 7            // unverified
    package static let scrollerInset: CGFloat = 3                // unverified
    package static let scrollerMinimumKnobLength: CGFloat = 20   // unverified
    package static let scrollerKnob = RGBA(red: 0, green: 0, blue: 0, alpha: 0.5)   // unverified
    package static let scrollerHoldSeconds = 0.6                 // unverified
    package static let scrollerFadeSeconds = 0.25                // unverified
    /// Touch momentum: velocity multiplier per millisecond (UIScrollView's `normal` rate).
    package static let scrollDecelerationRate = 0.998
    /// Momentum stops below this speed (points per second).
    package static let scrollVelocityFloor: CGFloat = 5
    /// Distance a touch travels before it becomes a pan rather than a press.
    package static let panSlop: CGFloat = 10                     // unverified
    /// A finger resting this long before lifting leaves no momentum (seconds).
    package static let panRestInterval = 0.1                     // unverified
}
