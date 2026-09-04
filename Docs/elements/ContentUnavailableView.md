# ContentUnavailableView

Apple docs: [ContentUnavailableView](https://developer.apple.com/documentation/swiftui/contentunavailableview).

## API surface

| API | Notes |
|---|---|
| `ContentUnavailableView(label:description:actions:)` (description and actions optional), `ContentUnavailableView(_ title, image:description:)`, `ContentUnavailableView(_ title, systemImage:description:)`, `.search`, `.search(text:)` | implemented |
| The large symbol above the title | not shown: the macOS 26 golden shows the label's title only (`labelStyle(.titleOnly)`), so the image is dropped here too |

## Behaviour

A `VStack` with 12 pt spacing: the label in the large title font, bold, the secondary colour and
the title-only label style; the description in the body font and the secondary colour; the
actions in an `HStack`. The column is padded 20 at the top and top-aligned in a frame that fills
whatever it is offered (so three of them in a 400 pt stack are 128 each). `search` is "No
Results" with "Check the spelling or try a new search."; `search(text:)` quotes the text.

## Measured (macOS 26.2, `unavailable/basic`, 2026-09-04)

| Property | Value | Probe |
|---|---|---|
| Frame | fills the space: 360 wide, a third of 400 (128) each in the fixture's stack | `titled`, `custom`, `search` |
| Title | large title bold (26 pt, 38 line, "No Mail" 90 wide), colour 128 = secondary; top at 20 | `customLabel` (130.5 × 38 at y + 20), pixels |
| Description | body (18.5 line), secondary; 12 under the title | `description` (y + 70) |
| Actions | a bordered button 12 under the description | `action` (24 tall at y + 100.5) |
| Icon | none (the `tray` symbol and the `icon` image do not appear) | pixels |

## Verification (2026-09-04)

Tier A: `unavailable/basic` exact. Tier B: Chromium 0.33 %, WebKit 0.32 %, Firefox with its
hinting-class shift of the "No Results" title (130 wide at 115 against 130.5 at 114.75). Tier C:
0.50 %.
`UnavailableAndShareTests` cover the column, the colours, the missing icon and the search preset.

## Not yet covered

The symbol above the title on other platforms, vertical centring on iOS, `ContentUnavailableView`
inside lists and navigation.
