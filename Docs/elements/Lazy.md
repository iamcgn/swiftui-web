# LazyVStack, LazyHStack, LazyVGrid, LazyHGrid, GridItem

Apple docs: [LazyVStack](https://developer.apple.com/documentation/swiftui/lazyvstack),
[LazyVGrid](https://developer.apple.com/documentation/swiftui/lazyvgrid),
[GridItem](https://developer.apple.com/documentation/swiftui/griditem).

## API surface

| API | Notes |
|---|---|
| `LazyVStack(alignment:spacing:pinnedViews:content:)`, `LazyHStack(…)`, `PinnedScrollableViews` | implemented: eager stacks that fill the axis across them; `pinnedViews` accepted, nothing pins |
| `LazyVGrid(columns:alignment:spacing:pinnedViews:content:)`, `LazyHGrid(rows:…)`, `GridItem(_:spacing:alignment:)`, `GridItem.Size` (`.fixed`, `.flexible(minimum:maximum:)`, `.adaptive(minimum:maximum:)`) | implemented, eager |
| Laziness (creating cells on demand), `Section` headers/footers inside grids, pinned headers while scrolling | missing: every cell is laid out; `Section` inside a lazy stack lays out as its header and content |

## Behaviour

**Stacks.** A `LazyVStack` is a `VStack` of its alignment and spacing stretched to the proposed
width (`frame(maxWidth: .infinity)` aligned by the stack's alignment at the top); a `LazyHStack`
an `HStack` stretched to the proposed height. Two lazy stacks in an `HStack` therefore share the
width equally, and a lazy horizontal stack bottom-aligns its children at the bottom of the
available height.

**Grids.** `_LazyGridLayout` is a `Layout`: the `GridItem`s are the tracks across the minor axis
(columns of a vertical grid); cells flow line by line, one per track, in order (a horizontal
grid flows column by column). Fixed tracks take their size; the remaining space (the proposal
less fixed tracks and the item spacings, 8 by default) is shared equally by the flexible tracks,
each clamped to its bounds with the remainder not redistributed (a 280 grid with 60 fixed and
two flexible tracks capped at 80 gets 102 and 80, not 102 and 122); an adaptive track becomes
`floor((room + spacing) / (minimum + spacing))` tracks of the shared width. A line is as tall as
its tallest cell (each cell proposed its track's width), lines are `spacing` (8) apart. The grid
takes the proposed size across the minor axis and places its tracks in it by its alignment
(centred by default, so a grid narrower than its frame is centred); cells align in their cell by
the item's alignment, else the grid's.

## Measured (macOS 26.2, `lazy/stacks`, `lazy/grids`, 2026-09-04)

| Property | Value | Probe |
|---|---|---|
| Lazy stacks fill the cross axis | two `LazyVStack`s in a 320 `HStack(spacing: 20)` with a 37 wide `LazyHStack` are 121.5 each; the `LazyHStack` is 240 tall | `vstack`, `sections`, `hstack` |
| Alignment | leading children at x 0; `.bottom` puts a 30 pt box at y 210 in 240 | `alpha`, `red`, `orange`, `hi` |
| Sections | the header lays out as a plain view above the content (16 + 20 with spacing 0) | `header`, `green` |
| Fixed + flexible columns | 60 / 102 / 80 (capped) in 280 with 8 between, the 258 total centred (x 31) | `cell0…cell5`, `columns` |
| Adaptive columns | `.adaptive(minimum: 50)` with 10 spacing in 240: four 52.5 tracks; rows 24 + 8 apart | `adaptive0…adaptive4` |
| Horizontal grid | two 30 pt rows 8 apart, columns 40 + 6, the grid 132 wide and its 68 content centred in 70 | `hcell0…hcell4`, `rows` |

## Verification (2026-09-04)

Tier A: both fixtures exact. Tier B: `grids` 0 % and `stacks` ≤ 0.11 % in Chromium, WebKit and Firefox; Tier C 0 %. `LazyLayoutTests` cover
track resolution (fixed, flexible clamping, adaptive counts, no proposal), flow order in both
axes, and the stacks' cross-axis filling.

## Not yet covered

Laziness and scrolling performance, pinned headers, sections in grids, `GridItem` alignment
against the grid's when they differ (unmeasured), grids inside `ScrollView` with unbounded
proposals (flexible tracks fall back to their minimum).
