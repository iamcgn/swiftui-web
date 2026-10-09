# UIDatePicker, UICalendarView and UIPickerView

`Packages/UIKitWeb/Sources/UIKitWebCore/Controls/UIDatePicker.swift`,
`Controls/UICalendarView.swift`, `Controls/UIPickerView.swift`. Fixtures (iPhone SE simulator,
iOS 26, en_US, 11 September 2026, 11:30): `uikit/datepicker/compact` (date, time, date-and-time
and a disabled picker, and a 200 pt one too narrow for the long date), `uikit/datepicker/wheels`
(frames only), `uikit/datepicker/inline` and `inline-time` (the inline style with and without the
time row), `uikit/datepicker/calendar` (a `UICalendarView` limited to 5–25 September with the 11th
selected), `uikit/datepicker/countdown` (frames only), `uikit/datepicker/locales` (en_GB, de_DE,
fr_FR, ja_JP and a picker clamped by `minimumDate`), `uikit/picker/basic` and `uikit/picker/custom`
(frames only).

## API

`UIDatePicker`: `date`, `setDate(_:animated:)`, `datePickerMode` (`time`, `date`, `dateAndTime`,
`countDownTimer`), `preferredDatePickerStyle` / `datePickerStyle` (`automatic` resolves to
`compact`, a count-down timer to `wheels`, an inline time-only picker to `compact`), `minimumDate`
and `maximumDate` (the date is clamped when either is set, as UIKit clamps it; the calendar greys
and refuses the days outside and stops paging past them), `minuteInterval`, `countDownDuration`,
`calendar`, `timeZone`, `locale`, `isEnabled`, `sizeThatFits`, `intrinsicContentSize`,
`valueChanged` through `addAction` / `addTarget`. The accessibility label is the formatted date
and time; the wheels are adjustable.

`UICalendarView`: `calendar`, `locale`, `timeZone`, `fontDesign` (stored), `availableDateRange`,
`visibleDateComponents` / `setVisibleDateComponents(_:animated:)`, `selectionBehavior`
(`UICalendarSelectionSingleDate` and `UICalendarSelectionMultiDate` with their delegates'
`didSelect` / `canSelect` callbacks), `delegate` (`decorationFor:` as a dot of the decoration's
colour and size — approximate, 5 pt 15 below the number; `didChangeVisibleDateComponentsFrom:`),
`wantsDateDecorations`, `reloadDecorations`, `sizeThatFits` (280 × 288).

`UIPickerView`: `dataSource` (`numberOfComponents(in:)`, `numberOfRowsInComponent`), `delegate`
(`titleForRow`, `attributedTitleForRow`, `viewForRow:forComponent:reusing:`, `didSelectRow`,
`rowHeightForComponent`, `widthForComponent`), `selectRow`, `selectedRow(inComponent:)`,
`reloadAllComponents`, `reloadComponent`, `view(forRow:forComponent:)`.

## Strings

`DatePickerStrings` (in UICalendarView.swift) resolves a locale to the capsule and calendar
text. Measured: en_US "Sep 11, 2026" and "11:30 AM" (a narrow no-break space before the period);
en_GB "11 Sep 2026" and "11:30"; de "11.09.2026"; fr "11 sept. 2026"; ja "2026/09/11"; all four
on the 24-hour clock. Other English regions take the day-month-year form (12-hour in AU, NZ, IN
and IE), zh and ko the numeric year-month-day form, every other language day-month-year with
English names (approximate). The numeric fallback is "9/11/26" (en_US), "11/09/2026",
"11.09.26" or "2026/09/11". The calendar's month title is "September 2026" ("2026年9月" in ja)
and its weekday initials SUN…SAT (DIM.…SAM., SO.…SA., 日…土). Calendars other than the
Gregorian draw the Gregorian grid.

## Measured: the compact style

- Each part is a capsule on the tertiary system fill with 8 pt corners: a 17 pt label 12 in and
  7 down, the capsule the label's width plus 24. "Sep 11, 2026" is 98 wide (a 122 pt capsule);
  "11:30 AM" is set in tabular figures (every digit as wide as a zero, measured with zeros:
  73.5, a 97.5 capsule). A date-only picker is 38.5 tall (its label 24.5); one with a time
  capsule is 40 (the time label is 26). A disabled picker draws its text without the fill.
- `sizeThatFits` is both capsules and the 4 pt gap between them (223.5 for this date), the
  capsules right-aligned in the frame. iOS 26 sizes the capsules for the *current* date and
  time rather than the picker's (a golden made at 3 PM measured 212.5, one at 10 PM 222.5, one
  in October 217), so the fixture pins every picker to 240 and UIKitWeb sizes from its own
  date.
- When the long date does not fit beside the time capsule the date capsule shows the numeric
  date: "9/11/26" is 55.5 wide (a 79.5 capsule) in the 200 pt `narrow` picker.
- A tap on the date capsule presents the inline calendar (320 × its height) in a popover
  anchored to the capsule, a tap on the time capsule the time wheels (320 × 216); the popover
  stays a popover on the iPhone and the editor's `valueChanged` sets the picker's date and sends
  its own (`DatePickerEditorController`). UIKit's editor panel has no arrow and a shadow
  (approximate: the popover's arrow is drawn).
- Pixels: `uikit/datepicker/compact` 1.6 % off the simulator, `locales` 1.9 %.

## Measured: the calendar (`uikit/datepicker/inline`, `uikit/datepicker/calendar`, and the
simulator's view trees of calendar views 250, 280, 320 and 360 wide)

- The header is 16 down and 38 tall: the month title in 17 pt semibold 20 in (its label the
  advance width rounded up to the half point, 135 for "September 2026"), a 7 × 12 disclosure
  chevron of the tint 4 after it (a 10.5 wide image); two 43.5 pt paging buttons ending 2 before
  the *layout width*, their 10.5 × 17.5 chevrons' ink 20.25 and 23.25 in. The ink is centred
  35 down. Chevrons that cannot page (no available day that way) are in the tertiary label colour.
- The weekday initials are 13 pt semibold in the tertiary label colour (60/60/67 at 30 %), seven
  labels as wide as the widest (31.5 for SUN…SAT) spread evenly from 16 in to 16 before the
  layout width, centred 79.5 down.
- The day numbers are 20 pt in rows from 90 down: columns ⌊(*grid width* − 56) / 6⌋ wide to the
  half point (42.5 for a 312 grid, 37 for 280, 44 for 320, 50.5 for 360), the first column
  centred under the first weekday label (so the grid starts 10.5 in at 312 and 13 at 280);
  each label centred in its cell on the pixel grid, the cap height centred on the row. The
  selected day is 20 pt semibold in the tint on a disc of the tint at 12 % as big as the
  cell's smaller side (42.5 in the inline picker, 36 in the calendar view); unavailable days
  are in the quaternary label colour (60/60/67 at 18 %).
- The inline picker is 320 wide; its calendar's grid is 8 narrower than the picker and its
  header as wide. Rows are 45.5 tall, the picker 90 + 45.5 × weeks + 10 tall (327.5 for a
  five-week month, 373 for six). With a time component a 46 pt row follows the grid 6 below
  it: "Time" in 17 pt semibold 16 in (its label 8 down, 24.5 tall) and the time capsule 16
  from the trailing edge (373.5 tall). Taps select a day (keeping the time of day, sending
  `valueChanged`), page the month with the chevrons, or present the time wheels from the
  capsule; the month-and-year wheels behind the title are not implemented.
- A `UICalendarView` lays its header and weekday row out 8 wider than its frame (the paging
  buttons overflow it by 6). Sized to fit it is 280 × 288 with 37 × 36 cells; at other sizes the
  rows are what the frame leaves for five of them above 18 at the bottom, at most the column
  width (42.5 at 320 × 320; approximate at 250 × 240 and 360 × 320, where UIKit's rows measured
  2 taller).
- Pixels: `inline` 1.8 %, `inline-time` 1.8 %, `calendar` 1.1 %.

## Measured: the wheels (frames only)

- A wheels picker is 320 × 216 (`sizeToFit`): columns of 21 pt rows on a 32 pt pitch over a
  selection band (the date's month at 96, day at 200, year at 272; the 12-hour time's hour at
  100, minute at 160 and period at 220; the count-down timer's hours at 99 with "hour" /
  "hours" 114 in and minutes at 177.5 with "min" 199 in, the labels 17 pt semibold). The drum's
  perspective is approximated (rows shrinking and fading away from the centre), so the pixel
  tiers skip `wheels`, `countdown`, `picker/basic` and `picker/custom`.
- A drag spins the column under the finger by the rows it covers (32 per row); a tap picks the
  row under the finger; either sends `valueChanged` (a date picker) or `didSelectRow` (a picker
  view). There is no momentum.
- `UIPickerView`: components share the width unless the delegate sizes them, and sized
  components sit centred as a group (180 + 80 from 30 in, `uikit/picker/custom`); the drum
  turns every component at the tallest row height the delegate gives (UIKit laid both of the
  custom fixture's components out on a 42 pt pitch though one asked for 32). Row views from
  `viewForRow:forComponent:reusing:` are laid out at the row's size and painted on the drum,
  scaled and faded with their row; the previous view of the component is offered for reuse.

## Open

The month-and-year wheels behind the calendar's title, custom decoration views, calendars
other than the Gregorian and locales beyond the measured five (the strings are tables), the
drum's real cylinder and momentum, UIKit's arrow-less editor panel for the compact popover.
