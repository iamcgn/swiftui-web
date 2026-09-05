/// iOS overrides of the platform metrics, measured on the `ios/…` goldens (Mac Catalyst,
/// decision 0013; `Docs/elements/iOS.md`). Everything not set here keeps macOS's value until an
/// iOS fixture measures it. Two controls deliberately differ from the Catalyst pixels, whose
/// switch and slider knob are Mac-shaped: their frames follow the goldens, their paint iOS.
extension PlatformMetricsTable {
    package static let iOS: PlatformMetricsTable = {
        let t = PlatformMetricsTable()
        t.disabledLabelOpacity = 0.24                                   // ios/toggle/basic `disabled`: 52 over the label's 215
        // Buttons (ios/button/basic): body labels, 12 pt sideways and 7 pt vertical padding in a capsule.
        t.buttonHorizontalPadding = 12
        t.buttonVerticalPadding = 7
        t.buttonHeight = 38.5
        t.buttonFill = Color(storage: .system(.controlInk), opacityMultiplier: 41.0 / 255)
        t.destructiveColor = RGBA(r: 255, g: 57, b: 59)
        // Toggle (ios/toggle/basic): a 61 × 28 frame at the row's trailing edge; painted as the iOS switch.
        t.switchFrameSize = CGSize(width: 61, height: 28)
        t.switchSize = CGSize(width: 51, height: 31)
        t.switchKnobSize = CGSize(width: 27, height: 27)
        t.switchKnobInset = 2
        t.switchLabelSpacing = 8
        // Slider (ios/slider/basic): 31 pt rows, the accent fill; painted with the iOS round knob.
        t.sliderHeight = 31
        t.sliderTrackHeight = 4
        t.sliderKnobSize = CGSize(width: 27, height: 27)
        t.sliderKnobInset = 13.5
        t.sliderTrackAlpha = 26.0 / 255
        t.sliderFillsWithAccent = true
        t.sliderKnobShadowAlpha = 0.15
        // Stepper (ios/stepper/basic): a 94 × 32 frame holding a 93 × 28 pill, − | + glyphs.
        t.stepperSize = CGSize(width: 94, height: 32)
        t.stepperPillInset = CGSize(width: 0.5, height: 2)
        t.stepperCornerRadius = 14
        t.stepperFill = 11.0 / 255
        t.stepperDisabledFill = 12.0 / 255
        t.stepperDividerAlpha = 75.0 / 255
        // TextField (ios/textfield/basic): 34 pt rounded border 0.5 pt inside, 4 pt corners; 26 pt plain.
        t.textFieldHeight = 34
        t.textFieldHorizontalPadding = 7.5
        t.textFieldVerticalPadding = 4.75
        t.textFieldCornerRadius = 4
        t.textFieldBorderWidth = 0.5
        t.textFieldBorderAlpha = 0.2
        t.textFieldBorderInside = true
        t.textFieldTextOffset = 0.75                                    // the row label's baseline: 23.5 down, not 22.75
        t.textFieldPlainExtraHeight = 1.5
        t.textFieldPlainEmptyExtraHeight = 0.5                          // ios/dark/controls `emptyField`: 25 with only the placeholder
        t.textFieldPlainTextOffset = -0.75
        t.textFieldPlaceholder = RGBA(r: 189, g: 189, b: 190)
        t.textFieldPlaceholderDark = RGBA(r: 235, g: 235, b: 245, a: 0.3)   // placeholderText; ios/dark/controls reads white at 25 %
        t.secureBulletDiameter = 7
        t.secureBulletPitch = 10.5
        t.secureBulletInset = 1.5
        t.secureBulletBaselineOffset = 6.75
        // Picker (ios/picker/basic): the menu is a borderless value + chevrons; the segmented control fills its width.
        t.popUpHeight = 40.5
        t.popUpTextInset = 13.5
        t.popUpChevronGap = 4
        t.popUpChevronWidth = 9
        t.popUpChevronTrailing = 13.5
        t.popUpChevronRise = 4.25
        t.popUpChevronStroke = 2
        t.segmentedHeight = 31
        t.segmentedFill = 31.0 / 255
        t.segmentedCornerRadius = 15.5
        t.segmentedSelectedInset = CGSize(width: 7, height: 2)
        t.segmentedSelectedIsWhite = true
        t.segmentedTextAlpha = 221.0 / 255
        t.segmentedSelectedTextAlpha = 216.0 / 255
        t.segmentedFontWeight = 500
        t.segmentedSelectedFontWeight = 600
        t.segmentedTextTop = 7
        // Lists and forms: inset grouped cards on a grey ground, 56 pt rows (ios/list/basic, ios/form/basic).
        t.listRowMinimumHeight = 56
        t.controlsUsePlainSpacing = true                                // ios/layout/controls
        // ProgressView (ios/progress/basic): a 4 pt accent bar on a (120, 120, 125) 20 % track, no
        // indeterminate segment, the label 4 above; the circular style is the 20 pt spinner even
        // with a value, its label below in the secondary colour.
        t.progressRowHeight = 4
        t.progressBarHeight = 4
        t.progressTrackColor = RGBA(r: 120, g: 120, b: 125, a: 51.0 / 255)
        t.progressFillsWithAccent = true
        t.progressIndeterminateSegment = 0
        t.progressLabelSpacing = 4
        t.progressCircularIsSpinner = true
        t.progressRingRegularDiameter = 20
        t.spinnerMaxAlpha = 98.0 / 255
        t.spinnerMinAlpha = 30.0 / 255
        t.listSeparatorAlpha = 25.0 / 255
        return t
    }()
}
