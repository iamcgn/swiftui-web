# redacted, privacySensitive, unredacted

Apple docs: [redacted(reason:)](https://developer.apple.com/documentation/swiftui/view/redacted(reason:)),
[RedactionReasons](https://developer.apple.com/documentation/swiftui/redactionreasons),
[privacySensitive(_:)](https://developer.apple.com/documentation/swiftui/view/privacysensitive(_:)),
[unredacted()](https://developer.apple.com/documentation/swiftui/view/unredacted()).

## API surface

| API | Notes |
|---|---|
| `redacted(reason:)`, `RedactionReasons` (`placeholder`, `privacy`, `invalidated`), `redactionReasons` environment | implemented; `invalidated` draws the content as it is, as SwiftUI does |
| `privacySensitive(_:)` | implemented |
| `unredacted()` | implemented |
| Placeholders for text and system symbols | implemented (measured) |
| Placeholders for catalog images | approximate: the image's frame filled with the placeholder ink (not measured) |
| Custom placeholder shapes, `RedactionReasons.invalidated` styling, shimmering | missing |

## Behaviour

`redacted(reason:)` adds the reasons to the environment's `redactionReasons`, `unredacted()`
clears them, `privacySensitive` sets a flag; nothing about the tree changes. Two environment
questions decide painting:

- `_usesPlaceholderLayout`: the placeholder reason on content that is not privacy-sensitive.
  A `Text` then lays out a placeholder string instead of itself: one non-breaking character per
  character of the text (spaces included) at the placeholder advance for the font's size, so
  lines wrap by character; a single line is `count × advance` rounded to the nearest half point.
  A system symbol takes the placeholder frame, the same for every symbol.
- `_drawsPlaceholders`: the placeholder layout, or the privacy reason on privacy-sensitive
  content, which keeps its plain layout under the bars.

Bars are `fillRRect`s in `_placeholderColor` (13.7 % ink: black in light, white in dark), one per
line, standing on the baseline, as tall as the font's cap height rounded up to the half point,
with corners a fifth of that height; a wrapped placeholder line's bar stretches to the frame and
the last line keeps its own width. Symbols paint a square of the point size centred in their
frame. Shapes, colours and control chrome are untouched: a button keeps its border around a bar,
a toggle keeps its checkbox. A privacy-sensitive text under the placeholder reason alone draws
as itself (measured), as does everything under `invalidated`.

## Measured (macOS 26.2, `redacted/placeholder`, `redacted/widths`, `redacted/privacy`, 2026-09-04)

| Property | Value |
|---|---|
| Placeholder advance per character (spaces included; letters, digits and weight irrelevant) | 11 pt: 5.45, 13 pt: 6.30, 17 pt: 7.90, 22 pt: 10.50, 26 pt: 12.95 (no fixed fraction of the size: SF's optical sizes); the line width rounds to the nearest half point ("a b c d e" 56.5, "x" 6.5) |
| Wrapping | by character: 40 characters in 100 pt make three lines of 15, 15 and 10; the first two bars span the full 100 pt, the last 62.5 |
| Bar | from the baseline up by the cap height rounded up to the half point (9.5 pt at 13 pt, 16 at the 22 pt title); ink 35/255 black; corners about a fifth of the height |
| Symbol placeholder | frame `round(1.18 × size)` × `round(1.145 × size)` (13 × 13 at 11 pt, 15 × 15 at 13, 20 × 19 at 17, 26 × 25 at 22, 31 × 30 at 26, 40 × 39 at 34) with a square of the point size centred; the same for `star`, `gear` and `chevron.right` |
| Privacy | `privacySensitive` text under `.privacy` keeps its plain width (85 for "Hidden secret") under a bar; other text is untouched |
| Placeholder + privacySensitive | draws as itself |
| Layout of everything else | unchanged |

Two harness lessons repeated here: the first placeholder fixture was too short for its stack and
SwiftUI dropped the wrapped paragraph to fewer lines (height pressure), and `star.fill` at the
title size is not in the symbol table (its fallback size differs), so the fixture uses `star`.

## Verification (2026-09-04)

Tier A: 3 fixtures exact. Tier C: 0.01 %, 0.10 %, 0.01 %. Tier B: Chromium and WebKit 3/3
exact frames; Firefox 2/3 (one plain word in its known hinting class). `RedactionTests` cover
the widths and rounding, the bar command, character wrapping with stretched bars, privacy on the
plain layout, the placeholder-and-sensitive exception, `unredacted`, `invalidated`, and symbol
frames and squares.

## Not yet covered

Catalog image placeholders (not measured), the exact corner radius, dark-mode ink (assumed the
inverse), `privacySensitive` on images and controls, and whether SwiftUI's placeholder advance
follows custom fonts.
