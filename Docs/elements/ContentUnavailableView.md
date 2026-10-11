# ContentUnavailableView

Apple docs: [ContentUnavailableView](https://developer.apple.com/documentation/swiftui/contentunavailableview).

## API surface

| API | Notes |
|---|---|
| `ContentUnavailableView(label:description:actions:)` (description and actions optional), `ContentUnavailableView(_ title, image:description:)`, `ContentUnavailableView(_ title, systemImage:description:)`, `.search`, `.search(text:)` | implemented |
| The icon above the title | implemented 2026-10-11 (macOS 27 and iOS): a 36 pt symbol (or a catalog image at its size) in the tertiary colour, 24 above the title; dropped when the column does not fit the height on offer |

## Behaviour (macOS 27 / iOS, 2026-10-11, corrected the same day under decision 0019)

A column of its own height: the label in `_UnavailableLabelStyle` (the icon, then 24, then the
title in the bold `title3` style and the secondary colour), the description in `title3` and the
secondary colour 6 below and 12 above what follows, the actions in an `HStack` 6 below; 20
above and 26 beneath (20 when there are actions). The view is as wide as its space and only as
tall as the column, so whatever holds it centres it (a fixed frame, a stack, a `NavigationStack`;
a `List` row is the column's height). When the column does not fit the height on offer the
title-only column takes its place, filling the space from the top (`ViewThatFits(in:
.vertical)`). The column keeps its lines in a short cell (`fixedSize` vertically: the iOS
`search` preset wraps to two lines). `search` is "No Results" with "Check the spelling or try a
new search."; `search(text:)` quotes the text.

## Measured (macOS 27.0.1, `unavailable/basic`, `unavailable/corners`; iOS 27.0, `ios/unavailable/basic`; 2026-10-11)

| Property | Value | Probe |
|---|---|---|
| Height | its own: a label 129.5 (20 + 83.5 + 26), with a description 169.5 (+ 6 + 22 + 12), with actions 153.5 (+ 6 + 24 + 20), all three 193.5; a stack of three (169.5, 199, 174) is centred in 640 | `titled`, `custom`, `search`, `stack`; probed in 700 pt frames |
| Centring | a 175 pt frame puts the tray at 22.75 (the 169.5 column centred); 169.5 fits, 169 does not | probed |
| Height pressure | below the column's height the icon goes and the title-only column sits 20 from the top (a 190 pt frame with description and actions: title at 20, description 49, action 89); at 128 per view the first `unavailable/basic` showed no icons at all | `plain*`, probed |
| Symbol | the `tray` 50.5 × 36.5 (the runtime's 36 pt stand-in is 50 × 37.5), 20 below the top, centred; colour (189, 189, 189) | `plainIcon`, `listIcon`, `navIcon` |
| Title | `title3` bold (15 pt, a 23 line; "No Mail" 54.5 wide), secondary (128); 24 below the icon | `plainTitle`, `listTitle`, `navTitle`, `customLabel` (71 tall with the 24 pt catalog `icon`) |
| Description | `title3` (a 22 line; "Try again later." 100.5 wide), secondary; 6 below the title | `plainDescription`, `listDescription`, `description` |
| Actions | 6 below the description's 12 (18 in all), 6 below a label without one; the bordered button 24.08 × 56.5 | `plainAction`, `action` |
| In a `List` | a row of the column's height (328 × 169.5 with a description) 14 below the list's top | `inList` |
| In a `NavigationStack` | 129.5 tall (20 + 36.5 + 24 + 23 + 26) centred in the 190 stack | `inNav` |
| iPhone | the column centred vertically in its space; the search preset's description wraps to two lines in a 158 pt cell; a list row 123.5 tall (iOS 27 list insets, ignored) | `titled`, `search`, `inList` |

The 26.2 look (a large-title text alone, top-aligned) is gone: macOS 27 draws the design iOS had.
The first measurement of 2026-10-11 came from a harness macOS 27 drew with its pre-26
behaviour (decision 0019): it showed 20 pt buttons, no icon for a catalog image and no icons in
the 400 pt `unavailable/basic` (height pressure, not the image kind), and the view filling its
space; the goldens were regenerated and the model corrected the same day.

## Verification (2026-10-11)

Tier A: `unavailable/basic`, `unavailable/corners` and `ios/unavailable/basic` exact (the
symbol-driven probes within 2 pt: the stand-in tray is a point taller). Tier C: 1.1 % / 1.0 %
(the stand-in symbols; the fixtures are approximate); Tier B in the same range.
`TabViewAndFriendsTests.unavailableColumn` covers the column's heights, the centring, the
height-pressure fallback, the colours and the search preset.

## Not yet covered

The SF Symbol glyphs themselves (stand-ins).
