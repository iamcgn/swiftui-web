/// Platform constants that SwiftUI does not document. Every value here must be backed by a
/// fixture in `Fixtures/Sources` and recorded in `Docs/elements/`; until measured, a value is
/// marked `// unverified`. The values below are macOS's (the reference profile); `iOS` in
/// PlatformMetricsIOS.swift overrides the ones measured on iOS goldens. Nodes read them through
/// `PlatformMetrics.<name>` (PlatformMetricsAccessors.swift, generated), which resolves against
/// the table of the profile currently laying out: `ViewNode` selects it from its environment's
/// `platformProfile` on every layout and paint entry, so a subtree can render in another
/// platform's look (`.environment(\.platformProfile, .iOS)`).
package final class PlatformMetricsTable: @unchecked Sendable {
    package init() {}

    /// `.padding()` with no length.
    package var defaultPadding: CGFloat = 16          // macOS 26.2: fixture layout/padding-default
    /// Default stack spacing and `Spacer` minimum length.
    package var defaultSpacing: CGFloat = 8           // macOS 26.2: fixtures layout/spacing-default, layout/spacer-min-length
    /// `Divider` thickness.
    package var dividerThickness: CGFloat = 1         // macOS 26.2: fixture layout/divider

    // Bordered buttons (macOS 26.2: fixtures button/basic, button/styles; pixels sampled from goldens)
    package var buttonHeight: CGFloat = 24
    package var buttonHorizontalPadding: CGFloat = 12
    package var buttonLabelSize: CGFloat = 13              // label line is 16 pt: point-size metrics, not .body
    package var buttonCornerRadius: CGFloat = 6
    package var buttonFill = Color(storage: .system(.controlInk), opacityMultiplier: 19.0 / 255)
    package var buttonPressedFill = Color(storage: .system(.controlInk), opacityMultiplier: 50.0 / 255)   // unverified
    /// A bordered button is its label plus 4 pt above and below (32 for a 24 pt Label, label/basic).
    package var buttonVerticalPadding: CGFloat = 4

    // Toggle (macOS 26.2: fixtures toggle/basic, toggle/styles; pixels sampled from goldens, Docs/elements/Toggle.md)
    package var checkboxSize: CGFloat = 16
    package var checkboxLabelSpacing: CGFloat = 5
    package var checkboxCornerRadius: CGFloat = 5                // from the corner ramp at 2×, approximate
    package var checkboxFillOn = 36.0 / 255
    package var checkboxFillOff = 25.0 / 255
    package var checkboxDisabledFillOn = 18.0 / 255              // approximate
    package var checkboxDisabledFillOff = 13.0 / 255
    package var checkMarkWidth: CGFloat = 2                       // approximate
    package var checkMarkAlpha = 222.0 / 255
    package var checkMarkDisabledAlpha = 66.0 / 255               // approximate
    package var switchSize = CGSize(width: 54, height: 24)
    package var switchKnobSize = CGSize(width: 32, height: 20)
    package var switchKnobInset: CGFloat = 2
    package var switchLabelSpacing: CGFloat = 8
    package var switchTrackOn = 36.0 / 255
    package var switchTrackOff = 25.0 / 255
    /// Disabled control labels keep 30 % of their alpha (66/216 for the primary label colour).
    package var disabledLabelOpacity = 0.3

    // TextField (macOS 26.2: fixtures textfield/basic, textfield/styles; pixels sampled, Docs/elements/TextField.md)
    package var textFieldHeight: CGFloat = 24
    package var textFieldHorizontalPadding: CGFloat = 6
    package var textFieldVerticalPadding: CGFloat = 4
    package var textFieldCornerRadius: CGFloat = 5                // approximate: the border ramp reads 5–6 pt
    package var textFieldBorderWidth: CGFloat = 1                 // drawn outside the frame
    package var textFieldBorderAlpha = 23.0 / 255
    package var textFieldDisabledFillAlpha = 192.0 / 255
    package var secureBulletDiameter: CGFloat = 5.5
    package var secureBulletPitch: CGFloat = 8
    package var secureBulletInset: CGFloat = 1.5                  // first bullet's ink starts 7.5 pt in
    package var secureBulletBaselineOffset: CGFloat = 5           // centre 5 pt above the baseline
    package var focusRingWidth: CGFloat = 3                       // unverified (no focused golden)
    package var focusRingOpacity = 0.5                            // unverified
    package var focusRingCornerRadius: CGFloat = 6                // unverified: buttons and focusable views
    package var listFocusedSelectionAlpha = 0.25                  // unverified: the accent selection of a focused list
    package var menuHighlightAlpha = 0.1                          // unverified: the keyboard-highlighted menu row
    package var menuHighlightInset: CGFloat = 5
    package var menuHighlightCornerRadius: CGFloat = 4

    // List (macOS 26.2: fixtures list/*, pixels sampled, Docs/elements/List.md)
    package var listInsetMargin: CGFloat = 16
    package var listPlainMargin: CGFloat = 8
    package var listBorderedMargin: CGFloat = 7
    package var listBorderWidth: CGFloat = 1
    package var listBorderColor = Color(storage: .system(.controlInk), opacityMultiplier: 63.0 / 255)
    package var listTopInset: CGFloat = 10
    package var listRowVerticalInset: CGFloat = 4
    package var listRowMinimumHeight: CGFloat = 24
    package var listSidebarRowHeight: CGFloat = 32
    package var listSidebarBackground = Color(red: 240.0 / 255, green: 240.0 / 255, blue: 240.0 / 255)
    package var listSidebarForeground = Color(red: 0, green: 0, blue: 0, opacity: 0.7)
    package var listSectionHeaderPadding: CGFloat = 6
    package var listSectionSpacing: CGFloat = 20
    package var listSeparatorThickness: CGFloat = 1
    package var listSeparatorAlpha = 25.0 / 255
    package var listSelectionInset: CGFloat = 10
    package var listSelectionCornerRadius: CGFloat = 7                 // approximate
    package var listSelectionAlpha = 35.0 / 255
    package var listPinnedHeaderHeight: CGFloat = 27
    package var listPinnedHeaderLine: CGFloat = 1
    package var listPinnedHeaderShadowAlpha = 7.0 / 255
    package var listPinnedHeaderLineAlpha = 48.0 / 255
    package var listLabelIconWidth: CGFloat = 16                        // 13 pt font; list/basic `label`
    package var listLabelIconSpacing: CGFloat = 6
    package var listIdealWidth: CGFloat = 200                           // unverified

    // Controls with labels (Picker, Slider, Stepper; macOS 26.2, Docs/elements/{Picker,Slider,Stepper}.md)
    package var controlLabelSpacing: CGFloat = 8

    // Picker: pop-up button (fixtures picker/*)
    package var popUpHeight: CGFloat = 24
    package var popUpTextInset: CGFloat = 12
    package var popUpChevronGap: CGFloat = 18                           // widest option to chevron
    package var popUpChevronWidth: CGFloat = 7
    package var popUpChevronTrailing: CGFloat = 10.5
    package var popUpChevronHalfHeight: CGFloat = 3.5                    // one chevron's rise
    package var popUpChevronOffset: CGFloat = 2.5                        // centre line to chevron base
    package var popUpChevronStroke: CGFloat = 1.5
    package var popUpCornerRadius: CGFloat = 6
    package var popUpFill = 20.0 / 255
    package var popUpDisabledFill = 10.0 / 255
    package var popUpDisabledTextAlpha = 73.0 / 255
    // Picker: segmented control
    package var segmentPadding: CGFloat = 21                             // segment = widest option + 21
    package var segmentedHeight: CGFloat = 24
    package var segmentedFill = 20.0 / 255
    package var segmentedSelectedFill = 50.0 / 255
    package var segmentedCornerRadius: CGFloat = 6
    package var segmentedTextAlpha = 137.0 / 255
    package var segmentedSelectedTextAlpha = 152.0 / 255
    package var segmentedDividerAlpha = 43.0 / 255
    package var segmentedDividerInset: CGFloat = 6                       // approximate
    // Picker: radio group
    package var radioSize: CGFloat = 16
    package var radioLabelSpacing: CGFloat = 5
    package var radioRowSpacing: CGFloat = 6
    package var radioFillOff = 25.0 / 255
    package var radioFillOn = 36.0 / 255
    package var radioDotSize: CGFloat = 5
    package var radioDotAlpha = 216.0 / 255

    // Slider (fixtures slider/*)
    package var sliderHeight: CGFloat = 16
    package var sliderTrackHeight: CGFloat = 5
    package var sliderKnobSize = CGSize(width: 22, height: 16)
    package var sliderKnobInset: CGFloat = 11                            // knob centre travel, each end
    package var sliderFilledAlpha = 58.0 / 255
    package var sliderTrackAlpha = 25.0 / 255
    package var sliderDisabledFilledAlpha = 42.0 / 255
    package var sliderKnobShadowAlpha = 12.0 / 255                       // approximate (Apple's is a blur)
    package var sliderTickSize: CGFloat = 2
    package var sliderTickTop: CGFloat = 14
    package var sliderIdealWidth: CGFloat = 100                          // unverified

    // Stepper (fixtures stepper/*)
    package var stepperSize = CGSize(width: 20, height: 26)
    package var stepperCornerRadius: CGFloat = 5
    package var stepperFill = 20.0 / 255
    package var stepperDisabledFill = 10.0 / 255
    package var stepperChevronAlpha = 137.0 / 255
    package var stepperDisabledChevronAlpha = 132.0 / 255
    package var stepperChevronInset: CGFloat = 4.5                       // x, each side
    package var stepperChevronRise: CGFloat = 5                          // chevron height
    package var stepperChevronStroke: CGFloat = 1.5
    package var stepperUpChevronBase: CGFloat = 9.25                     // y of the up chevron's feet
    package var stepperDownChevronBase: CGFloat = 17.25                  // y of the down chevron's feet
    package var stepperDividerAlpha = 43.0 / 255
    package var stepperDividerInset: CGFloat = 3

    // Default stack spacing of controls (macOS 26.2: form/basic, form/sections row gaps; the 13 pt
    // text spacings 4.7421875 above / 8.15087890625 below, Docs/elements/Form.md)
    package var controlSpacingAbove: CGFloat = 4.7421875
    package var controlSpacingBelow: CGFloat = 8.15087890625
    package var checkboxSpacing: CGFloat = 6
    package var textFieldSpacing: CGFloat = 6

    // Form (macOS 26.2: fixtures form/*, Docs/elements/Form.md)
    package var formSliderRowHeight: CGFloat = 23
    package var formSliderLabelTop: CGFloat = 7
    package var formSliderTrackTop: CGFloat = 1
    package var formGroupedInset: CGFloat = 20
    package var formGroupedRowPadding: CGFloat = 10
    package var formGroupedRowMinimumHeight: CGFloat = 38.5
    package var formGroupedCardCornerRadius: CGFloat = 10                  // approximate
    package var formGroupedCardFill = 8.0 / 255
    package var formGroupedSeparatorAlpha = 20.0 / 255
    package var formGroupedSeparatorHeight: CGFloat = 1                     // between rows, not overlapping
    package var formGroupedSwitchSize = CGSize(width: 36, height: 16)        // approximate (form/styles pixels)
    package var formGroupedSwitchKnobSize = CGSize(width: 22, height: 14)    // approximate
    package var formGroupedSectionSpacing: CGFloat = 20                     // unverified
    package var formGroupedHeaderSpacing: CGFloat = 8                       // unverified

    // Presentations (approximate: separate windows on macOS, Docs/elements/Presentation.md)
    package var presentationPadding: CGFloat = 20
    package var presentationCornerRadius: CGFloat = 10
    package var presentationDimAlpha = 0.2
    package var presentationShadowAlpha = 0.12
    package var presentationBorderAlpha = 0.15
    package var sheetMargin: CGFloat = 20
    package var alertWidth: CGFloat = 260
    package var popoverArrowHeight: CGFloat = 10
    package var popoverArrowWidth: CGFloat = 24
    package var menuGap: CGFloat = 2
    package var menuCornerRadius: CGFloat = 6
    package var menuRowHeight: CGFloat = 22
    package var menuCheckWidth: CGFloat = 22
    package var menuTrailingPadding: CGFloat = 16
    package var menuMinimumWidth: CGFloat = 92.5
    package var menuVerticalPadding: CGFloat = 4
    package var menuSeparatorHeight: CGFloat = 11                       // 5 above and below the line
    package var menuSeparatorInset: CGFloat = 8
    package var menuSeparatorAlpha = 0.1
    package var menuSubmenuChevronGap: CGFloat = 12
    package var menuSubmenuChevronSize = CGSize(width: 4, height: 8)
    package var menuSubmenuChevronStroke: CGFloat = 1.5

    // Menu pull-down button (macOS 26.2: fixture menu/basic, Docs/elements/Menu.md). Shares the
    // pop-up's box, insets and chevron gap; one chevron centred 12 pt before the trailing edge.
    package var pullDownChevronTrailing: CGFloat = 12
    package var pullDownChevronHalfHeight: CGFloat = 1.75
    package var menuSplitGap: CGFloat = 8                               // label to divider
    package var menuSplitDividerWidth: CGFloat = 1
    package var menuSplitDividerInset: CGFloat = 5
    package var menuSplitDividerAlpha = 0.12
    package var menuSplitTrailing: CGFloat = 24                         // divider to trailing edge
    package var menuSplitChevronTrailing: CGFloat = 11.25
    package var menuSplitChevronStroke: CGFloat = 1

    // ProgressView (macOS 26.2: fixtures progress/*, Docs/elements/ProgressView.md; the greys of
    // the inactive golden window)
    package var progressRowHeight: CGFloat = 20
    package var progressBarHeight: CGFloat = 8
    package var progressBarIdealWidth: CGFloat = 100                  // unverified: no fixture proposes nothing
    package var progressTrackAlpha = 15.0 / 255
    package var progressFillAlpha = 85.0 / 255
    package var progressFillDark = RGBA(r: 170, g: 170, b: 170)                          // opaque in the dark appearance (dark/controls)
    package var progressIndeterminateSegment: CGFloat = 8
    package var progressRingStroke: CGFloat = 5
    package var progressRingTrackAlpha = 13.0 / 255
    package var progressRingFillAlpha = 70.0 / 255
    package func progressRingDiameter(_ size: ControlSize) -> CGFloat {
        switch size {
        case .mini: return 12          // unverified
        case .small: return 16
        case .regular: return 32
        case .large, .extraLarge: return 32   // unverified
        }
    }
    package var spinnerSpokes = 8
    package var spinnerInnerRadius: CGFloat = 6.5                     // approximate: the spinner animates
    package var spinnerOuterRadius: CGFloat = 14
    package var spinnerSpokeWidth: CGFloat = 3
    package var spinnerMaxAlpha = 53.0 / 255
    package var spinnerMinAlpha = 17.0 / 255

    // TabView (macOS 26.2: fixtures tabview/*, Docs/elements/TabView.md)
    package var tabBarHeight: CGFloat = 24
    package var tabBarCornerRadius: CGFloat = 6
    package var tabSegmentPadding: CGFloat = 12                   // each side of a title
    package var tabDividerWidth: CGFloat = 1
    package var tabSelectedInset: CGFloat = 0.5
    package var tabBoxTop: CGFloat = 10
    package var tabBoxCornerRadius: CGFloat = 4.5
    package var tabBoxFillAlpha = 8.0 / 255
    package var tabBoxBorderAlpha = 10.0 / 255                    // approximate: the 245 edge on the 247 fill

    // Gauge (macOS 26.2: fixtures gauge/basic, gauge/accessory, Docs/elements/Gauge.md)
    package var gaugeBarHeight: CGFloat = 16
    package var gaugeBarCornerRadius: CGFloat = 1.5                  // from the corner ramp at 2×
    package var gaugeTrackAlpha = 18.0 / 255
    package var gaugeBoundsSpacing: CGFloat = 8                      // bounds labels to the bar
    package var gaugeAccessoryBarHeight: CGFloat = 8
    package var gaugeAccessorySpacing: CGFloat = 6                   // label, capsule and value in the accessory capacity style
    package var gaugeAccessoryValueSize: CGFloat = 17                // semibold, the accessory linear labels
    package var gaugeAccessoryCapacityValueSize: CGFloat = 12        // the secondary value under the capsule
    package var gaugeAccessoryValueExtraGap: CGFloat = 1             // that value sits 7 under the capsule, not 6
    package var gaugePrimaryAlpha = 216.0 / 255                      // the primary label black (39 over white)
    package var gaugeKnobRadius: CGFloat = 4
    package var gaugeKnobHaloRadius: CGFloat = 8
    package var gaugeRingDiameter: CGFloat = 58
    package var gaugeRingRadius: CGFloat = 26
    package var gaugeRingStroke: CGFloat = 6
    package var gaugeRingTrackAlpha = 76.0 / 255                     // 179 over white
    package var gaugeRingTrimDegrees: Double = 14                    // each end, with bounds labels
    package var gaugeMarkerRadius: CGFloat = 2.5
    package var gaugeMarkerHaloRadius: CGFloat = 4.5                 // approximate
    package var gaugeRingValueSize: CGFloat = 24                     // medium, the centre value
    package var gaugeRingLabelSize: CGFloat = 11
    package var gaugeRingValueLift: CGFloat = 1                      // the centre value sits 1 pt above the centre
    package var gaugeRingEndOffset: CGFloat = 18.385                 // 26 / √2: the arc ends' x and y from the centre

    // DatePicker (macOS 26.2: fixtures datepicker/*, Docs/elements/DatePicker.md)
    package var dateFieldHeight: CGFloat = 22                        // the field style is 21
    package var dateFieldBorderAlpha = 12.0 / 255                    // 243 over white, drawn outside like a text field's
    package var dateDigitWidth: CGFloat = 8                          // tabular digits at 13 pt
    package var dateSeparatorWidth: CGFloat = 4                      // "/", ":" and the space
    package var dateCommaWidth: CGFloat = 8                          // ", " between the date and the time
    package var datePeriodWidth: CGFloat = 17                        // the AM/PM slot
    package var datePeriodLead: CGFloat = 1                          // the period's text starts a point before its slot
    package var dateFieldInset: CGFloat = 3                          // the field style's content insets
    package var dateFieldTextTop: CGFloat = 1                        // the field style's text line sits 1 pt down, not centred
    package var dateStepperBezelInset: CGFloat = 1                   // the stepper styles' bezel starts a point in
    package var dateStepperGap: CGFloat = 9.5
    package var dateStepperSize = CGSize(width: 12.5, height: 20)
    package var dateStepperCornerRadius: CGFloat = 4.5               // approximate
    package var dateStepperDividerInset: CGFloat = 2.5               // approximate
    package var dateStepperChevronInset: CGFloat = 3
    package var dateStepperChevronRise: CGFloat = 3
    package var dateStepperUpChevronBase: CGFloat = 6.5              // y of the up chevron's feet
    package var dateStepperDownChevronBase: CGFloat = 13.5           // y of the down chevron's feet
    package var dateSelectionCornerRadius: CGFloat = 2               // unverified: the focused component's highlight
    package var calendarSize = CGSize(width: 138.5, height: 148)
    package var calendarBoxInset = CGSize(width: 0.5, height: 0)
    package var calendarBoxSize = CGSize(width: 137.5, height: 148)
    package var calendarBoxCornerRadius: CGFloat = 3                 // approximate
    package var calendarBoxBorderAlpha = 5.0 / 255                   // approximate: the border is barely there
    package var calendarHeaderLeading: CGFloat = 3
    package var calendarHeaderCenter: CGFloat = 10                   // the header line's centre below the box's top
    package var calendarWeekdayCenter: CGFloat = 30
    package var calendarFirstRowCenter: CGFloat = 47
    package var calendarCellMargin: CGFloat = 4
    package var calendarCellSize = CGSize(width: 18.5, height: 18)
    package var calendarDayTrailing: CGFloat = 2
    package var calendarWeekdaySize: CGFloat = 10                    // bold
    package var calendarDaySize: CGFloat = 11
    package var calendarMutedAlpha = 66.0 / 255                      // weekday names and the neighbouring months' days (189)
    package var calendarHighlightAlpha = 35.0 / 255                  // 220
    package var calendarHighlightInset: CGFloat = 1
    package var calendarHighlightCornerRadius: CGFloat = 3           // approximate
    package var calendarArrowSize = CGSize(width: 5.5, height: 7)
    package var calendarDotDiameter: CGFloat = 7
    package var calendarControlGap: CGFloat = 8
    package var calendarControlTrailing: CGFloat = 6
    package var clockSize = CGSize(width: 119, height: 119)
    package var clockCenter = CGPoint(x: 60.25, y: 61.5)             // the dial overflows the view a little
    package var clockRadius: CGFloat = 60
    package var clockRingWidth: CGFloat = 6
    package var clockRingTop = RGBA(red: 209.0 / 255, green: 231.0 / 255, blue: 237.0 / 255, alpha: 1)
    package var clockRingBottom = RGBA(red: 118.0 / 255, green: 118.0 / 255, blue: 118.0 / 255, alpha: 1)
    package var clockInnerShadowWidth: CGFloat = 1.5                 // approximate
    package var clockInnerShadowAlpha = 70.0 / 255                   // 185 at the top, fading out at the bottom
    package var clockFaceColor = RGBA(red: 252.0 / 255, green: 253.0 / 255, blue: 254.0 / 255, alpha: 1)
    package var clockNumeralRadius: CGFloat = 48.5
    package var clockPeriodOffset: CGFloat = 17.5
    package var clockPeriodAlpha = 85.0 / 255                        // 170
    package var clockHourHandLength: CGFloat = 36                    // approximate
    package var clockMinuteHandLength: CGFloat = 52
    package var clockHourHandWidth: CGFloat = 3.5                    // approximate
    package var clockMinuteHandWidth: CGFloat = 2.5                  // approximate
    package var clockCapRadius: CGFloat = 4.5

    // TextEditor (macOS 26.2: fixtures texteditor/*, Docs/elements/TextEditor.md)
    package var textEditorInset: CGFloat = 5                          // the text view's line fragment padding
    package var textEditorLineFactor: CGFloat = 0.955                 // 13 pt → a 12 pt pitch, 22 pt → 21 (unverified)
    package var textEditorBaseSize: CGFloat = 13
    package var textEditorTopGrowth: CGFloat = 0.944                  // the 22 pt title's cap top sits 8.5 down; 13 pt's at the top
    package var textEditorTextColor = RGBA(red: 0, green: 0, blue: 0, alpha: 1)   // pure black, unlike SwiftUI text
    package var textEditorIdealSize = CGSize(width: 100, height: 100)  // unverified

    // Table (macOS 26.2: fixtures table/*, Docs/elements/Table.md)
    package var tableHeaderHeight: CGFloat = 28
    package var tableHeaderTitleInset: CGFloat = 10
    package var tableLineAlpha = 26.0 / 255                          // the header's bottom line and dividers (229)
    package var tableDividerInset: CGFloat = 6                       // the dividers run from 6 to 22
    package var tableRowsTop: CGFloat = 5                            // rows start 33 down
    package var tableRowHeight: CGFloat = 24
    package var tableCellInset: CGFloat = 8                          // a cell's leading inset in its column
    package var tableCellTrailingInset: CGFloat = 6                  // NSTableColumn.width = the SwiftUI width + 14
    package var tableIntercellSpacing: CGFloat = 3                   // between columns; the divider is its last point
    package var tableCellTop: CGFloat = 4
    package var tableLeadingMargin: CGFloat = 8
    package var tableTrailingMargin: CGFloat = 7                     // columns fill the width less 15
    package var tableColumnIdealWidth: CGFloat = 100                 // automatic columns: pitch 117
    package var tableColumnMinWidth: CGFloat = 10                    // unverified (NSTableColumn's default)
    package var tableBandInset: CGFloat = 10
    package var tableBandCornerRadius: CGFloat = 6                   // approximate
    package var tableBandAlpha = 11.0 / 255                          // 244
    package var tableSelectionAlpha = 35.0 / 255                     // 220, the inactive window's selection
    package var tableChevronSize = CGSize(width: 7, height: 4)
    package var tableChevronTrailing: CGFloat = 8                    // from the header cell's end (the next column, or the last column's content end)
    package var tableChevronStroke: CGFloat = 1.5
    package var tableIdealSize = CGSize(width: 300, height: 200)     // unverified

    // Painting: a scroll view skips subtrees further than this outside its viewport.
    package var scrollCullMargin: CGFloat = 256

    // ColorPicker (macOS 26.2: fixtures colorpicker/*, Docs/elements/ColorPicker.md)
    package var colorWellSize = CGSize(width: 48, height: 24)
    package var colorWellCornerRadius: CGFloat = 11
    package var colorWellAlpha = 25.0 / 255                          // the well's grey (230)
    package var colorWellSwatchInset: CGFloat = 3                    // 42 × 18, concentric corners
    package var colorWellStrokeAlpha = 0.1                           // the 0.5 pt inner stroke
    package var colorWellTopShadeAlpha = 0.15                        // the extra shade along the swatch's top
    package var colorWellDisabledOpacity = 0.5
    package var colorWellBaseline: CGFloat = 22.5                    // the label sits 1.5 pt above the well's bottom in a form
    package var colorPanelSwatchSize: CGFloat = 22                   // unverified: the popover cannot be captured
    package var colorPanelSwatchSpacing: CGFloat = 6

    // NavigationSplitView (macOS 26.2: fixtures splitview/*, Docs/elements/NavigationSplitView.md)
    package var sidebarDefaultWidth: CGFloat = 140                // the panel; the column is 8 wider
    package var splitContentDefaultWidth: CGFloat = 200
    package var sidebarInset: CGFloat = 8
    package var sidebarCornerRadius: CGFloat = 7.5                // from the corner ramp at 2×, approximate
    package var sidebarPanelColor = RGBA(red: 1, green: 1, blue: 1, alpha: 1)
    package var splitDividerAlpha = 25.0 / 255                    // the divider's alpha in the golden; black, unverified hue

    // ContentUnavailableView (macOS 26.2: fixture unavailable/basic, Docs/elements/ContentUnavailableView.md)
    package var unavailableSpacing: CGFloat = 12
    package var unavailableTopPadding: CGFloat = 20

    // Lazy grids (macOS 26.2: fixture lazy/grids, Docs/elements/Lazy.md)
    package var gridItemSpacing: CGFloat = 8

    // DisclosureGroup (macOS 26.2: fixture disclosure/basic, Docs/elements/DisclosureGroup.md)
    package var disclosureRowPadding: CGFloat = 4
    package var disclosureChevronWidth: CGFloat = 6.5              // the chevron's slot before the 5 pt gap
    package var disclosureChevronHeight: CGFloat = 8
    package var disclosureChevronSpacing: CGFloat = 5
    package var disclosureChevronSpan: CGFloat = 5.5               // approximate: the chevron's width across its arms
    package var disclosureChevronRise: CGFloat = 3
    package var disclosureChevronStroke: CGFloat = 1.5
    package var disclosureChevronAlpha = 64.0 / 255                // 191 over white

    // Link (macOS 26.2: fixture link/basic, Docs/elements/Link.md)
    package var linkDisabledOpacity = 0.5

    // GroupBox (macOS 26.2: fixture groupbox/basic, Docs/elements/GroupBox.md)
    package var groupBoxPadding: CGFloat = 5
    package var groupBoxCornerRadius: CGFloat = 12
    package var groupBoxFillAlpha = 8.0 / 255
    package var groupBoxLabelInset: CGFloat = 10
    package var groupBoxLabelSpacing: CGFloat = 3

    // Label (macOS 26.2: fixture label/basic, Docs/elements/Label.md)
    package var labelIconSpacing: CGFloat = 8

    // Scrolling (Docs/elements/ScrollView.md). Overlay scrollers only show while scrolling, so the
    // goldens cannot verify them; the values approximate macOS 26 overlay scrollers.
    package var scrollerThickness: CGFloat = 7            // unverified
    package var scrollerInset: CGFloat = 3                // unverified
    package var scrollerMinimumKnobLength: CGFloat = 20   // unverified
    package var scrollerKnob = RGBA(red: 0, green: 0, blue: 0, alpha: 0.5)   // unverified
    package var scrollerHoldSeconds = 0.6                 // unverified
    package var scrollerFadeSeconds = 0.25                // unverified
    /// Touch momentum: velocity multiplier per millisecond (UIScrollView's `normal` rate).
    package var scrollDecelerationRate = 0.998
    /// Momentum stops below this speed (points per second).
    package var scrollVelocityFloor: CGFloat = 5
    /// Distance a touch travels before it becomes a pan rather than a press.
    package var panSlop: CGFloat = 10                     // unverified
    /// A finger resting this long before lifting leaves no momentum (seconds).
    package var panRestInterval = 0.1                     // unverified
    /// A finger resting this long on a drag-tracking control (a slider) before moving keeps
    /// the touch from the scroll view around it (UIScrollView's content-touch delay, seconds).
    package var touchHoldInterval = 0.15

    // Geometry and colours only the iOS code paths read (PlatformMetricsIOS.swift sets them from
    // the ios/ goldens); macOS keeps its look through the values above.
    package var switchFrameSize = CGSize(width: 54, height: 24)     // the switch's layout frame; the painted capsule is switchSize
    package var switchOnColor = RGBA(r: 52, g: 199, b: 89)          // iOS systemGreen
    package var switchOffAlpha = 0.09
    package var switchKnobShadowAlpha = 0.15
    package var sliderFillsWithAccent = false
    package var sliderDisabledAccentAlpha = 0.5
    package var stepperPillInset = CGSize(width: 0, height: 0)
    package var stepperDividerVerticalInset: CGFloat = 4.5
    package var stepperGlyphSize: CGFloat = 13
    package var stepperGlyphStroke: CGFloat = 2
    package var stepperGlyphAlpha = 218.0 / 255
    package var stepperMinusCenterX: CGFloat = 23.5
    package var stepperPlusCenterX: CGFloat = 70
    package var textFieldTextOffset: CGFloat = 0
    package var textFieldPlainExtraHeight: CGFloat = 0
    package var textFieldPlainTextOffset: CGFloat = 0
    package var textFieldBorderInside = false
    package var textFieldPlaceholder: RGBA? = nil
    package var segmentedSelectedInset = CGSize(width: 0, height: 0)
    package var segmentedSelectedIsWhite = false
    package var segmentedFontSize: CGFloat = 13
    package var segmentedFontWeight = 400
    package var segmentedSelectedFontWeight = 400
    package var segmentedTextTop: CGFloat = 0                        // 0: centred in the segment
    package var popUpChevronRise: CGFloat = 0                        // 0: the macOS chevron pair
    package var destructiveColor = RGBA(r: 255, g: 57, b: 59)
}

/// The metrics of the profile currently laying out or painting (see `PlatformMetricsTable`).
package enum PlatformMetrics {
    nonisolated(unsafe) package static var current: PlatformMetricsTable = .macOS

    /// Makes `profile`'s table current; returns the previous one for `restore`.
    @inline(__always)
    package static func select(_ profile: PlatformProfile) -> PlatformMetricsTable {
        let previous = current
        if previous !== profile.metrics { current = profile.metrics }
        return previous
    }
}

extension PlatformMetricsTable {
    package static let macOS = PlatformMetricsTable()
}
