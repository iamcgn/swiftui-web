# UIDatePicker and UIPickerView

`Packages/UIKitWeb/Sources/UIKitWebCore/Controls/UIDatePicker.swift`. Fixtures
`uikit/datepicker/compact` (date, time, date-and-time and a disabled picker at 11 September 2026,
11:30) and `uikit/datepicker/wheels` (frame only), measured on the iPhone SE simulator (iOS 26,
en_US).

## API

`date`, `setDate(_:animated:)`, `datePickerMode` (`time`, `date`, `dateAndTime`,
`countDownTimer`), `preferredDatePickerStyle` / `datePickerStyle` (`automatic` resolves to
`compact`; `wheels`; `inline` draws the wheels for now), `minimumDate`, `maximumDate`,
`minuteInterval`, `calendar`, `timeZone`, `locale` (stored; the strings are en_US), `isEnabled`,
`sizeThatFits`, `intrinsicContentSize`. The accessibility label is the formatted date and time.

## Measured

- The compact style draws each part as a capsule on the tertiary system fill with 8 pt corners:
  a 17 pt label 12 in and 7 down, the capsule the label's width plus 24. The date reads
  "Sep 11, 2026" (98 wide, so a 122 pt capsule); the time "11:30 AM" with a narrow no-break
  space before the period (73.5 wide, 97.5). A date-only picker is 38.5 tall (its label 24.5
  tall); one with a time capsule is 40 (the time label is 26 tall). The time label uses
  monospaced digits (every digit as wide as a zero), measured with zeros in place of the digits.
- `sizeThatFits` of a date-and-time picker is both capsules and the 4 pt gap between them
  (223.5 for this date), and the capsules right-align in the frame. iOS 26 sizes a date-only or
  time-only picker's hidden capsule for the *current* time rather than the picker's (a golden
  made at 3 PM measured 212.5, one made at 10 PM 222.5 with the old 2:30 PM fixture time), so
  the fixture pins those pickers to 240 wide and UIKitWeb sizes them from their own time (a
  point or ten off UIKit by the clock). A disabled picker draws its text without the fill.
- The wheels style is 320 × 216 (`sizeToFit`): three columns (month, day, year) of 21 pt rows on
  a 32 pt pitch over a selection band. The frame is pinned; the drum's perspective is drawn
  approximately (rows shrinking and fading away from the centre), so the pixel tiers skip it.
- Pixels: `uikit/datepicker/compact` 1.7 % off the simulator.

## UIPickerView

`Controls/UIPickerView.swift`, fixture `uikit/picker/basic` (two components, a row selected in
each). `dataSource` (`numberOfComponents(in:)`, `numberOfRowsInComponent`), `delegate`
(`titleForRow`, `didSelectRow`, `rowHeightForComponent`, `widthForComponent`), `selectRow`,
`selectedRow(inComponent:)`, `reloadAllComponents`. A picker sized to fit is 320 × 216; the
components share the width unless the delegate sizes them, and the drum is the date picker's
(approximate, so the fixture is frames-only). The semantics node is adjustable and steps the
first component.

## Open

Tapping a compact picker (UIKit presents a calendar or time popover), the inline calendar,
the count-down timer, other locales and calendars, `minimumDate` / `maximumDate` enforcement,
`valueChanged` from the wheels, spinning a picker by touch, custom row views.
