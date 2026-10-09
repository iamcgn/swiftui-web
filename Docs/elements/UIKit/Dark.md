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

## Trait overrides and observation (2026-10-09, `uikit/view/traits`, nine more `uikit/dark/*`)

- `overrideUserInterfaceStyle` on a view (and on a view controller, which sets its view's)
  turns its subtree dark or light whatever lies above; `traitOverrides.userInterfaceStyle`
  does the same; the nearest override wins (a light island inside a dark one). The system
  colours, labels, cards (`secondarySystemBackground`), fills (`systemGray5`) and a switch
  resolve per island: `uikit/view/traits` 1.2 % off the simulator.
- A change of either override, of the window's `overrideUserInterfaceStyle`, of the host's
  colour scheme or of the host's size reaches `traitCollectionDidChange` on every view in the
  affected subtree and on the view controllers whose views changed, re-resolving their
  dynamic background colours.
- `registerForTraitChanges(_:handler:)` / `(_:target:action:)` (iOS 17) on views and view
  controllers, with `UITraitUserInterfaceStyle`, `…HorizontalSizeClass`, `…VerticalSizeClass`,
  `…UserInterfaceIdiom`, `…DisplayScale`, `…LayoutDirection`, `…PreferredContentSizeCategory`;
  the handler runs when one of its traits differs from before; `unregisterForTraitChanges`.
- Size classes from the host: narrower than 500 is a phone and compact wide, shorter than
  400 compact tall (an iPhone in portrait is compact × regular, in landscape compact × compact;
  the 400 pt fixtures stay regular tall as the simulator's harness holds them); a host resize
  updates them and tells the trees.
- Dark samples added: the inline calendar with its time row (`uikit/dark/inline` 0.1 %) and
  the calendar view (`calendar` 0.1 %: the tint disc, weekday and unavailable colours hold),
  the wheels (`wheels`), the page sheet (`sheet` 0.1 %, its `present` step 0.4 %), the popover
  (`popover` 0.1 % / 0.3 %), the refresh control (`refresh` 0.6 %, refreshing 1.3 %), image
  tints (`imagetints` 0.7 %), the layer looks (`looks` 0.3 %) and the materials (`materials`
  1.6 %, the dark tints fitted: see UIView.md's table; the chrome material saturates its
  ground by 1.3 in the dark).

Open: `traitCollectionDidChange` for `preferredContentSizeCategory` from the host, the
`UITraitCollection(traitsFrom:)` composition of overrides on view controllers.

`traitOverrides` (2026-09-12, `UITraitOverrides`): a view's set values replace the inherited
`userInterfaceStyle`, size classes, `layoutDirection`, `preferredContentSizeCategory`
(`UIContentSizeCategory`, new) and `displayScale` for its subtree, with `traitCollectionDidChange`
down the tree on a change; `effectiveUserInterfaceLayoutDirection` follows
`semanticContentAttribute`, else the trait. SwiftUI's environment reaches a hosted tree this way
(Docs/elements/Representable.md, `ios/representable/traits`).
