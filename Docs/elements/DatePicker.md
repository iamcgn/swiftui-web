# DatePicker

Apple docs: [DatePicker](https://developer.apple.com/documentation/swiftui/datepicker),
[DatePickerComponents](https://developer.apple.com/documentation/swiftui/datepickercomponents),
[DatePickerStyle](https://developer.apple.com/documentation/swiftui/datepickerstyle),
[datePickerStyle(_:)](https://developer.apple.com/documentation/swiftui/view/datepickerstyle(_:)),
[EnvironmentValues.timeZone](https://developer.apple.com/documentation/swiftui/environmentvalues/timezone).

## API surface

| API | Notes |
|---|---|
| `DatePicker(selection:displayedComponents:label:)`, `DatePicker(_ title, selection:displayedComponents:)` (key and string) | implemented |
| `in:` ranges (`ClosedRange`, `PartialRangeFrom`, `PartialRangeThrough`) on every form | implemented: stepping and the calendar clamp into the range (the calendar does not grey out days outside it) |
| `DatePickerComponents` (`.date`, `.hourAndMinute`) | implemented |
| `DatePickerStyle`: `.automatic`, `.compact`, `.stepperField` (all the field with a stepper on macOS), `.field`, `.graphical`; `datePickerStyle(_:)` | implemented; custom styles (`makeBody`) are not (the protocol exposes only the platform kind) |
| `EnvironmentValues.timeZone`, `EnvironmentValues.calendar` | implemented; dates are drawn in the environment's time zone through the Gregorian calendar, in en_US (M/d/yyyy, h:mm a, English month and weekday names) |
| `labelsHidden()`, `disabled` | implemented |
| Typing into the field, the compact popover calendar, dragging the clock's hands, `.wheel` (iOS), locales and other calendars, `.datePickerStyle(.graphical)` for both components on one row (side by side, unverified) | missing or approximate |

## Behaviour

The field (`DateFieldNode`) draws the shown components in fixed slots: two tabular 8 pt
digits for the month, day, hour and minute, four for the year, 17 pt for AM/PM, joined by
"/" (4), ", " (8), ":" (4) and a space (4); numbers are right-aligned in their slots and the
period starts a point before its slot. The stepper styles put a 72 pt bezel (for a date) a
point in, then a 9.5 pt gap and a 12.5 × 20 mini stepper with the standalone stepper's fill,
divider and chevron colours; the field style has no stepper and a 3 pt inset each side, and is
21 tall instead of 22. The bezel is the text field's: white with a 1 pt border of black 12/255
drawn outside. A press on a component selects it (highlighted in the accent colour while the
field is focused), a press on the stepper's halves and the Up/Down keys step the selected
component (the first when none is selected), Left/Right move the selection; `_Adjustable`
for assistive technology. The calendar (`CalendarNode`) is 138.5 × 148: the month and year in
13 pt bold, previous/today/next controls, the weekday row in 10 pt bold grey and six weeks of
18.5 × 18 cells with 11 pt day numbers right-aligned 2 pt from the cell's trailing edge, the
neighbouring months' days in grey and the selected day on a 16 pt rounded highlight; pressing a
day selects it (keeping the time), the arrows page the shown month, the dot returns to today.
The clock (`ClockNode`) is a 119 pt square holding a 120 pt dial: a 6 pt bezel ring with a
light-blue-to-grey vertical gradient over a faint inner shadow, 13 pt numerals at radius
48.5, the period in 13 pt medium grey under the centre, black hands; display only.

## Measured (macOS 26.2, `datepicker/basic`, `datepicker/styles`, `datepicker/graphical`, `datepicker/clock`, `datepicker/steps`, 2026-09-04)

| Property | Value | Probe |
|---|---|---|
| Row | label (body) + 8 + control; the date control 95 × 22 ("Date" 28.5 → 131.5), date and time 160 (203 with "When"), time 80 (118 with "Time"); the field style 78 × 21 and 143 × 21 | `date`, `dateTime`, `time`, `hidden`, `field`, `fieldBoth` |
| Slots | "3" right-aligned in a 16 pt month slot starting 2 in, "/" 4, day 16, "/" 4, year 32; ", " 8; hour 16, ":" 4, minute 16, space 4, period 17 (the "PM" glyphs start a point before it) | glyph columns of `hidden`, `dateTime`, `time` |
| Bezel | the stepper styles: outer 72 wide (date), 137 (date and time), 57 (time), from x + 1; the field style: content + 6 from x; 1 pt border of black 12/255 outside a white fill with 5 pt corners | pixels |
| Stepper | 12.5 × 20 at the trailing edge, centred vertically; fill black 20/255, divider 43/255 at the middle, chevrons 137/255 (3 in, rise 3, feet 6.5 and 13.5 from the top) | pixels of `hidden` |
| Text | 13 pt, centred in the 22 pt row (baseline 16); a point down in the 21 pt field style | pixels of `hidden`, `field` |
| Disabled | text at about 30 % (approximate), the bezel unchanged | `disabled` |
| Compact | identical to the stepper field on macOS 26 | `compact`, `compactTime` |
| In a row | the 22 pt field is centred with a 24 pt button (y + 1) and a text | `row`, `rowPicker` |
| Model changes | the field re-lays out its text; a longer date keeps the width (fixed slots) | `datepicker/steps` |
| Calendar | 138.5 × 148 after "Calendar" + 8 (241 × 188 with the padding); box 137.5 wide with a faint 1 pt border and 3 pt corners; header centre 10 down, 3 in, 13 pt bold; controls 5.5 × 7 triangles and a 7 pt dot 8 apart, 6 from the trailing edge, secondary; weekdays centre 30 down in 10 pt bold at black 66/255; day rows centred 47 + 18k down, cells 18.5 wide from 4 in, numbers 11 pt right-aligned 2 from the cell's end; the selection a 16 pt highlight of black 35/255 across the cell | pixels of `graphical` |
| Clock | 119 × 119 after "Clock" + 8; dial centre (60.25, 61.5), radius 60; ring 54…60 from (209, 231, 237) at the top to (118, 118, 118) at the bottom; inner shadow (185) at the top fading out; face (252, 253, 254); numerals 13 pt at radius 48.5; "PM" 13 pt medium at 170 grey 17.5 under the centre; hands to 52 (minute) and about 36 (hour), cap radius 4.5 | pixels of `clock` |

## Verification (2026-09-04)

Tier A: all 5 fixtures exact, `datepicker/steps` steps included. Tier B, frames exact in
Chromium, WebKit and Firefox; pixels `basic` ≤ 1.29 %, `styles` ≤ 1.29 %, `graphical` ≤ 1.76 %,
`clock` ≤ 1.67 %, `steps` ≤ 0.95 % (glyph-level differences of the browsers' fallback digits,
the calendar's sub-pixel text snapping, the clock's bezel and hands). Tier C: 1.18 / 1.07 /
1.72 / 1.63 / ≤ 0.82 %. `DatePickerTests` cover the slot and stepper geometry, the displayed
components, stepping and selection by press and keys, range clamping and the period, the
calendar's grid, paging and day selection, and the clock's commands.

## Not yet covered

Typing and editing components, the compact style's popover, dragging the clock's hands, the
calendar's range dimming, locales and calendars other than en_US Gregorian, the exact hand
widths and the stepper's corner radius (approximate), the graphical style with both components.
