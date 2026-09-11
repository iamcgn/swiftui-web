# UIDatePicker

`Packages/UIKitWeb/Sources/UIKitWebCore/Controls/UIDatePicker.swift`. Fixtures
`uikit/datepicker/compact` (date, time, date-and-time and a disabled picker at 11 September 2026,
14:30) and `uikit/datepicker/wheels` (frame only), measured on the iPhone SE simulator (iOS 26,
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
  "Sep 11, 2026" (98 wide, so a 122 pt capsule); the time "2:30 PM" with a narrow no-break
  space before the period (62.5 wide, 86.5). A date-only picker is 38.5 tall (its label 24.5
  tall); one with a time capsule is 40 (the time label is 26 tall). The time label uses
  monospaced digits (every digit as wide as a zero; a plain label gives 62): the text stack has
  no tabular figures yet, so the capsule is measured with zeros in place of the digits.
- `sizeThatFits` is the same for every compact mode: both capsules and the 4 pt gap between
  them (212.5 for this date), and the capsules right-align in the frame (the date capsule at
  x 90.5 in a date-only picker, the time capsule at 126). A disabled picker draws its text
  without the fill.
- The wheels style is 320 × 216 (`sizeToFit`): three columns (month, day, year) of 21 pt rows on
  a 32 pt pitch over a selection band. The frame is pinned; the drum's perspective is drawn
  approximately (rows shrinking and fading away from the centre), so the pixel tiers skip it.
- Pixels: `uikit/datepicker/compact` 1.7 % off the simulator.

## Open

Tapping a compact picker (UIKit presents a calendar or time popover), the inline calendar,
the count-down timer, other locales and calendars, `minimumDate` / `maximumDate` enforcement,
`valueChanged` from the wheels.
