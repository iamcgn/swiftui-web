# LazyVStack, LazyHStack, LazyVGrid, LazyHGrid, GridItem

Apple docs: [LazyVStack](https://developer.apple.com/documentation/swiftui/lazyvstack),
[LazyVGrid](https://developer.apple.com/documentation/swiftui/lazyvgrid),
[GridItem](https://developer.apple.com/documentation/swiftui/griditem).

## API surface

| API | Notes |
|---|---|
| `LazyVStack(alignment:spacing:pinnedViews:content:)`, `LazyHStack(…)`, `PinnedScrollableViews` (`sectionHeaders`, `sectionFooters`) | implemented: stacks that fill the axis across them; inside a scroll view a `ForEach` creates its elements as they come within a viewport of the visible region; `pinnedViews` pins the sections' headers and footers to the scroll view's edges (2026-09-19) |
| `LazyVGrid(columns:alignment:spacing:pinnedViews:content:)`, `LazyHGrid(rows:…)`, `GridItem(_:spacing:alignment:)`, `GridItem.Size` (`.fixed`, `.flexible(minimum:maximum:)`, `.adaptive(minimum:maximum:)`) | implemented, eager |
| `Section` headers and footers inside lazy grids | implemented: a line of their own spanning the grid, aligned by the grid's alignment (`lazy/grid-sections`) |
| Laziness | implemented for `ForEach` inside a lazy stack or grid inside a scroll view: elements beyond the first are placeholders sized by the created ones' average until they come within a viewport of the visible region; `scrollTo` and `scrollPosition` to an element not created yet create it where its placeholder sits. Static children and `ForEach` outside scroll views are eager. Created elements are kept (Apple releases the ones scrolled away) |

## Behaviour

**Stacks.** A `LazyVStack` is a `VStack` of its alignment and spacing stretched to the proposed
width (`frame(maxWidth: .infinity)` aligned by the stack's alignment at the top) inside a
`_LazyContainer` (`Runtime/LazyNodes.swift`); a `LazyHStack` an `HStack` stretched to the
proposed height. Two lazy stacks in an `HStack` therefore share the
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
the item's alignment, else the grid's (`lazy/grid-alignment`: a `.trailing` grid puts its tracks
at the trailing end and its default cells at the trailing edge of their track; an item's
`.leading` or `.bottomTrailing` overrides that for its track; vertically cells centre in the
line unless the item says otherwise). A section header or footer takes a line of its own across
the whole grid (the proposal's extent, 240 for 196 pt of tracks), its content aligned by the
grid's alignment; the next cell starts a fresh line.

**Laziness.** `_LazyContainer` sets `_lazyContainerAxis` for its content; a `ForEach` under it
inside a scroll view (scroll views and lists reset the key for their content) creates its first
element and stands a `LazyPlaceholderNode` in for each other one: a layout node sized along the
axis by the created elements' average (their layout children summed) and across it by the
proposal, painting nothing. After placing its content the scroll view asks each lazy `ForEach`
to create the elements whose placeholders fall within the visible region grown by one viewport
along each scroll axis, forgets the memoised sizes and places the content again (up to three
rounds, and again after a `scrollTo`). A frame that only scrolled moves the content unless a
placeholder has entered the window, in which case it lays out. `scrollTo` to an element not yet
created (its `ForEach` identity, or the `id(_:)` at the top of its content, read from the view
value without a node) creates it where its placeholder sits. Elements are never released.

**Pinning.** With `pinnedViews`, the container lays out on every scroll frame (`readsGeometry`)
and, after placing the stack, walks the sections among the layout container's content: a
header whose natural position is above the visible start while its section still reaches below
it is placed again at the visible start, but no further than the section's end (or the next
header, which pushes it off); a footer whose natural position is below the visible end while its
section starts above it sits at the visible end, no higher than its header's bottom. Pinned
nodes are painted after everything else by the container (`paintsDeferred`).

## Measured (macOS 26.2, `lazy/stacks`, `lazy/grids`, 2026-09-04)

| Property | Value | Probe |
|---|---|---|
| Lazy stacks fill the cross axis | two `LazyVStack`s in a 320 `HStack(spacing: 20)` with a 37 wide `LazyHStack` are 121.5 each; the `LazyHStack` is 240 tall | `vstack`, `sections`, `hstack` |
| Alignment | leading children at x 0; `.bottom` puts a 30 pt box at y 210 in 240 | `alpha`, `red`, `orange`, `hi` |
| Sections | the header lays out as a plain view above the content (16 + 20 with spacing 0) | `header`, `green` |
| Fixed + flexible columns | 60 / 102 / 80 (capped) in 280 with 8 between, the 258 total centred (x 31) | `cell0…cell5`, `columns` |
| Adaptive columns | `.adaptive(minimum: 50)` with 10 spacing in 240: four 52.5 tracks; rows 24 + 8 apart | `adaptive0…adaptive4` |
| Horizontal grid | two 30 pt rows 8 apart, columns 40 + 6, the grid 132 wide and its 68 content centred in 70 | `hcell0…hcell4`, `rows` |

## Measured (macOS 26.6, `lazy/pinned-*`, `lazy/laziness`, `lazy/grid-*`, 2026-09-19)

Three sections of a 24 pt header, eight 20 pt rows and a 16 pt footer (200 pt each) in a
300 × 200 scroll view; the steps scroll row b3 to the top (offset 284).

| Behaviour | Value | Fixture |
|---|---|---|
| Pinned header | `bH` at y 0 with its natural place at −84; `cH` at its natural 116; the push by the next header is unmeasured | `lazy/pinned-headers/b3` |
| Pinned footer | `cF` at y 184 (natural 300) while section c starts at 116; `bF` at its natural 100 | `lazy/pinned-footers/b3` |
| Pinned footer of a section entering from below | `bF` at 184 (natural 340) with `bH` at 156, `aF` natural at 140 | `lazy/pinned-footers/b0-bottom` |
| Both | the same positions at once | `lazy/pinned-both/b3` |
| Rows created | 0–9 for a 200 pt viewport at rest; 100–109 after `scrollTo("r100", anchor: .top)`: only the rows in view (ours keeps a viewport ahead, and the rows created earlier) | `lazy/laziness` |
| Grid section header | 240 wide (the grid's proposal) and 24 tall at the top; cells start 4 below; the footer likewise; a `Text` header centres in its line | `lazy/grid-sections` |
| Duplicate ids | cells whose `ForEach` id another section already used are not created by Apple's grid (the fixture uses 10..<14) | `lazy/grid-sections` |
| Grid alignment | `.trailing`: tracks end at the grid's trailing edge (x 44 of 240 for 196 pt), default cells at the trailing edge of their track, a `.leading` item at the leading edge, `.bottomTrailing` at the bottom of a 40 pt line; `.leading`: tracks at 0 | `lazy/grid-alignment` |

## Verification (2026-09-04, laziness and pinning 2026-09-19)

Tier A: all eight fixtures exact (the lazy ones report the rows in view as a subset of ours).
Tier B: `grids` 0 % and `stacks` ≤ 0.11 % in Chromium, WebKit and Firefox; the pinned steps
≤ 0.73 % in Chromium; Tier C ≤ 0.73 %. `LazyLayoutTests` cover track resolution (fixed,
flexible clamping, adaptive counts, no proposal), flow order in both axes, and the stacks'
cross-axis filling; `LazyTests` cover rows created a viewport ahead, the scroll reaching
placeholders, `scrollTo` creating a row, pinned header and footer positions and paint order,
and a grid section's lines.

## Not yet covered

Releasing elements scrolled far away (Apple keeps only the rows in view); the push of a pinned
header by the next and a pinned footer meeting its header (implemented, unmeasured); hit testing
under a pinned header reaches the rows it covers; `ForEach` elements with several layout
children estimate as their sum; grids inside `ScrollView` with unbounded proposals (flexible
tracks fall back to their minimum); duplicate ids across sections (Apple drops the cells, ours
shows them).
