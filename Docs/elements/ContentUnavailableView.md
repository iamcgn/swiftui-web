# ContentUnavailableView

Apple docs: [ContentUnavailableView](https://developer.apple.com/documentation/swiftui/contentunavailableview).

## API surface

| API | Notes |
|---|---|
| `ContentUnavailableView(label:description:actions:)` (description and actions optional), `ContentUnavailableView(_ title, image:description:)`, `ContentUnavailableView(_ title, systemImage:description:)`, `.search`, `.search(text:)` | implemented |
| The symbol above the title | implemented 2026-10-11 (macOS 27 and iOS): a 36 pt symbol in the tertiary colour, 24 above the title; a catalog-image icon does not show (measured through the harness's `Label(_:image:)`) |

## Behaviour (macOS 27 / iOS, 2026-10-11)

A column: the label in `_UnavailableLabelStyle` (the symbol, then 24, then the title in the
bold `title3` style and the secondary colour), the description in `title3` and the secondary
colour 6 below, the actions in an `HStack` 18 below; 20 above and 26 below. On a Mac the column
sits at the top of the space the view fills, on an iPhone it is centred; inside a
`NavigationStack` the view keeps its own height and the stack centres it. The column keeps its
lines in a short cell (`fixedSize` vertically: the iOS `search` preset wraps to two lines).
`search` is "No Results" with "Check the spelling or try a new search."; `search(text:)` quotes
the text.

## Measured (macOS 27.0.1, `unavailable/basic`, `unavailable/corners`; iOS 27.0, `ios/unavailable/basic`; 2026-10-11)

| Property | Value | Probe |
|---|---|---|
| Frame | fills the space: a third of 400 (128) each in the basic fixture's stack; 190 in a 190 pt cell | `titled`, `custom`, `search`, `plain` |
| Symbol | the `tray` 50.5 × 36.5 (the runtime's 36 pt stand-in is 50 × 37.5), 20 below the top, centred; colour (189, 189, 189) | `plainIcon`, `listIcon`, `navIcon` |
| Title | `title3` bold (15 pt, a 23 line; "No Mail" 54.5 wide), secondary (128); 24 below the symbol | `plainTitle`, `listTitle`, `navTitle`, `customLabel` (23 tall: title only for a catalog image) |
| Description | `title3` (a 22 line; "Try again later." 100.5 wide), secondary; 6 below the title | `plainDescription`, `listDescription`, `description` |
| Actions | 18 below the description (a macOS 27 button is 20 tall and 48.5 wide, ignored: the control model is 26.2's) | `plainAction`, `action` |
| In a `List` | the row fills the list's content (328 × 169.5 in a 360 × 190 list, 14 above and 6.5 below: macOS 27 list insets, ignored) with the same column | `inList` |
| In a `NavigationStack` | 129.5 tall (20 + 36.5 + 24 + 23 + 26) centred in the 190 stack | `inNav` |
| iPhone | the column centred vertically in its space; the search preset's description wraps to two lines in a 158 pt cell; a list row 123.5 tall (iOS 27 list insets, ignored) | `titled`, `search`, `inList` |

The 26.2 look (a large-title text alone, top-aligned) is gone: macOS 27 draws the design iOS had.

## Verification (2026-10-11)

Tier A: `unavailable/basic`, `unavailable/corners` and `ios/unavailable/basic` exact (the
symbol-driven probes within 2 pt, the macOS 27 button and list-inset probes ignored). Tier B:
Chromium 3.5 % / 1.5 % / 5.3 % (the stand-in symbols; the fixtures are approximate). Tier C the
same. `TabViewAndFriendsTests.unavailableColumn` covers the column's metrics, the colours and the
search preset.

## Not yet covered

macOS 27's list insets and 20 pt buttons (the 26.2 control model), the SF Symbol glyphs
themselves (stand-ins).
