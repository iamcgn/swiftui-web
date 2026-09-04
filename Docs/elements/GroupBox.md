# GroupBox

Apple docs: [GroupBox](https://developer.apple.com/documentation/swiftui/groupbox),
[GroupBoxStyle](https://developer.apple.com/documentation/swiftui/groupboxstyle).

## API surface

| API | Notes |
|---|---|
| `GroupBox(content:)`, `GroupBox(_ title, content:)`, `GroupBox(content:label:)`, `GroupBox(_ configuration:)` | implemented |
| `GroupBoxStyle`, `GroupBoxStyleConfiguration` (`label`, `content`), `.automatic`, `groupBoxStyle(_:)` | implemented |
| The macOS 26 look (a rounded card, no border) | implemented from the golden; earlier macOS borders are not offered |

## Behaviour

`DefaultGroupBoxStyle` is a leading-aligned `VStack` with 3 pt spacing: the label (when there is
one) in the subheadline font 10 pt in from the leading edge, then the content padded 5 on every
side over a `RoundedRectangle` of radius 12 filled black at 8/255. The box is as wide as the
wider of the label plus its inset and the card, so a wide label sticks out to the right of a
narrow card and a wide card centres nothing.

A checkbox directly under a text inside the box sits 6 under it: the checkbox's spacing
replaces the text's 8.15 (declared in the text-to-text category, where the lower neighbour's
value applies, `Docs/elements/Toggle.md`); text fields keep the text's distance (form fixtures).

## Measured (macOS 26.2, `groupbox/basic`, 2026-09-04)

| Property | Value | Probe |
|---|---|---|
| Card | content + 5 on every side; radius 12 (from the corner ramp at 2×), fill black 8/255, no border | `plain` (89.5 × 26 around 79.5 × 16), pixels |
| Label | subheadline (11 pt, 16 line) at x 10, primary colour; 3 between it and the card (19 to the card's top) | `titled`, pixels |
| Width | max(label + 10, card): a 72.5 wide `Label` makes an 82.5 box over a 40.5 text; a 62 content makes a 72 box under a 52 label | `custom`, `customLabel`, `titled` |
| Stretching | `frame(maxWidth: .infinity)` content fills the window less 10 | `wide`, `wideContent` |
| Nesting | inner 53.5 × 45 inside outer 63.5 × 74 | `inner`, `outer` |
| Text over checkbox inside the box | 6 (the checkbox's), not the text's 8.15 | `content` (40.5 = 16 + 6 + 18.5) |

## Verification (2026-09-04)

Tier A: `groupbox/basic` exact. Tier B: Chromium 0.60 %, WebKit 0.32 %; Firefox 0.62 % with `inside`
0.5 narrower (its glyph-hinting class: "Inside" measures 36, not 36.5). Tier C: 0.32 %. `GroupBoxTests` cover the
card and label geometry, widths, nesting, a custom label and a custom style.

## Not yet covered

Dark appearance, the pre-macOS-26 bordered look, `GroupBox` inside `Form` (its insets there),
labels with accessory views.
