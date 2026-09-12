# Dark appearance

Apple docs: [UIUserInterfaceStyle](https://developer.apple.com/documentation/uikit/uiuserinterfacestyle),
[UIColor system colors](https://developer.apple.com/documentation/uikit/uicolor/ui_element_colors).

## What is covered (2026-09-11, `uikit/dark/*`)

Six light fixtures rendered again with the window's `overrideUserInterfaceStyle` dark
(`Fixtures/UIKit/Dark/DarkFixtures.swift`: the fixture kit's `renamed(_:)` and `style(_:)`):
the inset grouped table (`uikit/dark/table`), the plain table (`plaintable`), the slider,
segmented control, stepper, progress view, activity indicators and page control (`controls`),
the navigation bar (`nav`), the alert with its presentation steps (`alert`) and the list
layout (`list`). Every frame matches its light twin (dark changes no geometry) and the pixels
are within tolerance in every tier (0.2–1.9 % on macOS), so the system colours' dark values in
`Values/UIColor.swift`, the bars' dark platters and the cards' dark grey stand.

## Measured

- The grouped ground is black, the cards (28, 28, 30): `secondarySystemGroupedBackground`.
  Grouped cells take that colour when they still have the default `systemBackground` (which is
  black in the dark, and was drawn as the card before this step).
- Grouped section headers and footers are in the secondary label colour in both appearances
  (133 grey over the light ground, 141 over black; the light header used to be drawn black),
  which is (60, 60, 67) at 60 % and (235, 235, 245) at 60 %, as UIKit has it — the light
  value was black at 50 % before.
- Plain tables are black with black rows and the separator at white 10 %.

- A view resolves its dynamic colours again when it joins a tree whose interface style differs
  from the traits it was made under (as UIKit does on moving to a window): a table cell built
  during layout, before it joins a dark window, drew its `systemBackground` white in the
  browser, where the page's scheme is applied to the hosted tree after it exists.

Tier B composites a `uikit/dark/` golden onto black, as it does `ios/dark/` (the captures are
transparent where UIKit draws materials).

A second round (the same day) added the text view, toolbar, search bar, tab bar, compact date
picker, buttons and the basic controls (`uikit/dark/textview`, `toolbar`, `search`, `tabs`,
`datepicker`, `buttons`, `basiccontrols`), all within tolerance without a colour change: the
dark values already measured for the light twins' materials hold.

Open: `overrideUserInterfaceStyle` on a view rather than the window; `UITraitCollection`
`userInterfaceStyle` observation; dark samples of the pickers' wheels and presentations other
than the alert.
