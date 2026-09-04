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

    // TextField (macOS 26.2: fixtures textfield/basic, textfield/styles; pixels sampled, Docs/elements/TextField.md)
    package static let textFieldHeight: CGFloat = 24
    package static let textFieldHorizontalPadding: CGFloat = 6
    package static let textFieldVerticalPadding: CGFloat = 4
    package static let textFieldCornerRadius: CGFloat = 5                // approximate: the border ramp reads 5–6 pt
    package static let textFieldBorderWidth: CGFloat = 1                 // drawn outside the frame
    package static let textFieldBorderAlpha = 23.0 / 255
    package static let textFieldDisabledFillAlpha = 192.0 / 255
    package static let secureBulletDiameter: CGFloat = 5.5
    package static let secureBulletPitch: CGFloat = 8
    package static let secureBulletInset: CGFloat = 1.5                  // first bullet's ink starts 7.5 pt in
    package static let secureBulletBaselineOffset: CGFloat = 5           // centre 5 pt above the baseline
    package static let focusRingWidth: CGFloat = 3                       // unverified (no focused golden)
    package static let focusRingOpacity = 0.5                            // unverified
    package static let focusRingCornerRadius: CGFloat = 6                // unverified: buttons and focusable views
    package static let listFocusedSelectionAlpha = 0.25                  // unverified: the accent selection of a focused list
    package static let menuHighlightAlpha = 0.1                          // unverified: the keyboard-highlighted menu row
    package static let menuHighlightInset: CGFloat = 5
    package static let menuHighlightCornerRadius: CGFloat = 4

    // List (macOS 26.2: fixtures list/*, pixels sampled, Docs/elements/List.md)
    package static let listInsetMargin: CGFloat = 16
    package static let listPlainMargin: CGFloat = 8
    package static let listBorderedMargin: CGFloat = 7
    package static let listBorderWidth: CGFloat = 1
    package static let listBorderColor = Color(red: 0, green: 0, blue: 0, opacity: 63.0 / 255)
    package static let listTopInset: CGFloat = 10
    package static let listRowVerticalInset: CGFloat = 4
    package static let listRowMinimumHeight: CGFloat = 24
    package static let listSidebarRowHeight: CGFloat = 32
    package static let listSidebarBackground = Color(red: 240.0 / 255, green: 240.0 / 255, blue: 240.0 / 255)
    package static let listSidebarForeground = Color(red: 0, green: 0, blue: 0, opacity: 0.7)
    package static let listSectionHeaderPadding: CGFloat = 6
    package static let listSectionSpacing: CGFloat = 20
    package static let listSeparatorThickness: CGFloat = 1
    package static let listSeparatorAlpha = 25.0 / 255
    package static let listSelectionInset: CGFloat = 10
    package static let listSelectionCornerRadius: CGFloat = 7                 // approximate
    package static let listSelectionAlpha = 35.0 / 255
    package static let listPinnedHeaderHeight: CGFloat = 27
    package static let listPinnedHeaderLine: CGFloat = 1
    package static let listPinnedHeaderShadowAlpha = 7.0 / 255
    package static let listPinnedHeaderLineAlpha = 48.0 / 255
    package static let listLabelIconWidth: CGFloat = 16                        // 13 pt font; list/basic `label`
    package static let listLabelIconSpacing: CGFloat = 6
    package static let listIdealWidth: CGFloat = 200                           // unverified

    // Controls with labels (Picker, Slider, Stepper; macOS 26.2, Docs/elements/{Picker,Slider,Stepper}.md)
    package static let controlLabelSpacing: CGFloat = 8

    // Picker: pop-up button (fixtures picker/*)
    package static let popUpHeight: CGFloat = 24
    package static let popUpTextInset: CGFloat = 12
    package static let popUpChevronGap: CGFloat = 18                           // widest option to chevron
    package static let popUpChevronWidth: CGFloat = 7
    package static let popUpChevronTrailing: CGFloat = 10.5
    package static let popUpChevronHalfHeight: CGFloat = 3.5                    // one chevron's rise
    package static let popUpChevronOffset: CGFloat = 2.5                        // centre line to chevron base
    package static let popUpChevronStroke: CGFloat = 1.5
    package static let popUpCornerRadius: CGFloat = 6
    package static let popUpFill = 20.0 / 255
    package static let popUpDisabledFill = 10.0 / 255
    package static let popUpDisabledTextAlpha = 73.0 / 255
    // Picker: segmented control
    package static let segmentPadding: CGFloat = 21                             // segment = widest option + 21
    package static let segmentedHeight: CGFloat = 24
    package static let segmentedFill = 20.0 / 255
    package static let segmentedSelectedFill = 50.0 / 255
    package static let segmentedCornerRadius: CGFloat = 6
    package static let segmentedTextAlpha = 137.0 / 255
    package static let segmentedSelectedTextAlpha = 152.0 / 255
    package static let segmentedDividerAlpha = 43.0 / 255
    package static let segmentedDividerInset: CGFloat = 6                       // approximate
    // Picker: radio group
    package static let radioSize: CGFloat = 16
    package static let radioLabelSpacing: CGFloat = 5
    package static let radioRowSpacing: CGFloat = 6
    package static let radioFillOff = 25.0 / 255
    package static let radioFillOn = 36.0 / 255
    package static let radioDotSize: CGFloat = 5
    package static let radioDotAlpha = 216.0 / 255

    // Slider (fixtures slider/*)
    package static let sliderHeight: CGFloat = 16
    package static let sliderTrackHeight: CGFloat = 5
    package static let sliderKnobSize = CGSize(width: 22, height: 16)
    package static let sliderKnobInset: CGFloat = 11                            // knob centre travel, each end
    package static let sliderFilledAlpha = 58.0 / 255
    package static let sliderTrackAlpha = 25.0 / 255
    package static let sliderDisabledFilledAlpha = 42.0 / 255
    package static let sliderKnobShadowAlpha = 12.0 / 255                       // approximate (Apple's is a blur)
    package static let sliderTickSize: CGFloat = 2
    package static let sliderTickTop: CGFloat = 14
    package static let sliderIdealWidth: CGFloat = 100                          // unverified

    // Stepper (fixtures stepper/*)
    package static let stepperSize = CGSize(width: 20, height: 26)
    package static let stepperCornerRadius: CGFloat = 5
    package static let stepperFill = 20.0 / 255
    package static let stepperDisabledFill = 10.0 / 255
    package static let stepperChevronAlpha = 137.0 / 255
    package static let stepperDisabledChevronAlpha = 132.0 / 255
    package static let stepperChevronInset: CGFloat = 4.5                       // x, each side
    package static let stepperChevronRise: CGFloat = 5                          // chevron height
    package static let stepperChevronStroke: CGFloat = 1.5
    package static let stepperUpChevronBase: CGFloat = 9.25                     // y of the up chevron's feet
    package static let stepperDownChevronBase: CGFloat = 17.25                  // y of the down chevron's feet
    package static let stepperDividerAlpha = 43.0 / 255
    package static let stepperDividerInset: CGFloat = 3

    // Default stack spacing of controls (macOS 26.2: form/basic, form/sections row gaps; the 13 pt
    // text spacings 4.7421875 above / 8.15087890625 below, Docs/elements/Form.md)
    package static let controlSpacingAbove: CGFloat = 4.7421875
    package static let controlSpacingBelow: CGFloat = 8.15087890625
    package static let checkboxSpacing: CGFloat = 6
    package static let textFieldSpacing: CGFloat = 6

    // Form (macOS 26.2: fixtures form/*, Docs/elements/Form.md)
    package static let formSliderRowHeight: CGFloat = 23
    package static let formSliderLabelTop: CGFloat = 7
    package static let formSliderTrackTop: CGFloat = 1
    package static let formGroupedInset: CGFloat = 20
    package static let formGroupedRowPadding: CGFloat = 10
    package static let formGroupedRowMinimumHeight: CGFloat = 38.5
    package static let formGroupedCardCornerRadius: CGFloat = 10                  // approximate
    package static let formGroupedCardFill = 8.0 / 255
    package static let formGroupedSeparatorAlpha = 20.0 / 255
    package static let formGroupedSeparatorHeight: CGFloat = 1                     // between rows, not overlapping
    package static let formGroupedSwitchSize = CGSize(width: 36, height: 16)        // approximate (form/styles pixels)
    package static let formGroupedSwitchKnobSize = CGSize(width: 22, height: 14)    // approximate
    package static let formGroupedSectionSpacing: CGFloat = 20                     // unverified
    package static let formGroupedHeaderSpacing: CGFloat = 8                       // unverified

    // Presentations (approximate: separate windows on macOS, Docs/elements/Presentation.md)
    package static let presentationPadding: CGFloat = 20
    package static let presentationCornerRadius: CGFloat = 10
    package static let presentationDimAlpha = 0.2
    package static let presentationShadowAlpha = 0.12
    package static let presentationBorderAlpha = 0.15
    package static let sheetMargin: CGFloat = 20
    package static let alertWidth: CGFloat = 260
    package static let popoverArrowHeight: CGFloat = 10
    package static let popoverArrowWidth: CGFloat = 24
    package static let menuGap: CGFloat = 2
    package static let menuCornerRadius: CGFloat = 6
    package static let menuRowHeight: CGFloat = 22
    package static let menuCheckWidth: CGFloat = 22
    package static let menuTrailingPadding: CGFloat = 16
    package static let menuMinimumWidth: CGFloat = 92.5
    package static let menuVerticalPadding: CGFloat = 4
    package static let menuSeparatorHeight: CGFloat = 11                       // 5 above and below the line
    package static let menuSeparatorInset: CGFloat = 8
    package static let menuSeparatorAlpha = 0.1
    package static let menuSubmenuChevronGap: CGFloat = 12
    package static let menuSubmenuChevronSize = CGSize(width: 4, height: 8)
    package static let menuSubmenuChevronStroke: CGFloat = 1.5

    // Menu pull-down button (macOS 26.2: fixture menu/basic, Docs/elements/Menu.md). Shares the
    // pop-up's box, insets and chevron gap; one chevron centred 12 pt before the trailing edge.
    package static let pullDownChevronTrailing: CGFloat = 12
    package static let pullDownChevronHalfHeight: CGFloat = 1.75
    package static let menuSplitGap: CGFloat = 8                               // label to divider
    package static let menuSplitDividerWidth: CGFloat = 1
    package static let menuSplitDividerInset: CGFloat = 5
    package static let menuSplitDividerAlpha = 0.12
    package static let menuSplitTrailing: CGFloat = 24                         // divider to trailing edge
    package static let menuSplitChevronTrailing: CGFloat = 11.25
    package static let menuSplitChevronStroke: CGFloat = 1

    // ProgressView (macOS 26.2: fixtures progress/*, Docs/elements/ProgressView.md; the greys of
    // the inactive golden window)
    package static let progressRowHeight: CGFloat = 20
    package static let progressBarHeight: CGFloat = 8
    package static let progressBarIdealWidth: CGFloat = 100                  // unverified: no fixture proposes nothing
    package static let progressTrackAlpha = 15.0 / 255
    package static let progressFillAlpha = 85.0 / 255
    package static let progressIndeterminateSegment: CGFloat = 8
    package static let progressRingStroke: CGFloat = 5
    package static let progressRingTrackAlpha = 13.0 / 255
    package static let progressRingFillAlpha = 70.0 / 255
    package static func progressRingDiameter(_ size: ControlSize) -> CGFloat {
        switch size {
        case .mini: return 12          // unverified
        case .small: return 16
        case .regular: return 32
        case .large, .extraLarge: return 32   // unverified
        }
    }
    package static let spinnerSpokes = 8
    package static let spinnerInnerRadius: CGFloat = 6.5                     // approximate: the spinner animates
    package static let spinnerOuterRadius: CGFloat = 14
    package static let spinnerSpokeWidth: CGFloat = 3
    package static let spinnerMaxAlpha = 53.0 / 255
    package static let spinnerMinAlpha = 17.0 / 255

    // Link (macOS 26.2: fixture link/basic, Docs/elements/Link.md)
    package static let linkDisabledOpacity = 0.5

    // GroupBox (macOS 26.2: fixture groupbox/basic, Docs/elements/GroupBox.md)
    package static let groupBoxPadding: CGFloat = 5
    package static let groupBoxCornerRadius: CGFloat = 12
    package static let groupBoxFillAlpha = 8.0 / 255
    package static let groupBoxLabelInset: CGFloat = 10
    package static let groupBoxLabelSpacing: CGFloat = 3

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
