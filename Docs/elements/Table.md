# Table

Apple docs: [Table](https://developer.apple.com/documentation/swiftui/table),
[TableColumn](https://developer.apple.com/documentation/swiftui/tablecolumn),
[TableColumnBuilder](https://developer.apple.com/documentation/swiftui/tablecolumnbuilder),
[KeyPathComparator](https://developer.apple.com/documentation/foundation/keypathcomparator).

## API surface

| API | Notes |
|---|---|
| `Table(_:columns:)`, `Table(_:selection:columns:)` (single and set), `Table(_:sortOrder:columns:)`, both combined | implemented for `RandomAccessCollection`s of `Identifiable` rows |
| `TableColumn(_:value:)` (string key path), `TableColumn(_:value:content:)`, `TableColumn(_:content:)`; `LocalizedStringKey` and `StringProtocol` titles | implemented; a column with a `value:` key path is sortable |
| `TableColumn.width(_:)`, `width(min:ideal:max:)` | implemented (the measured NSTableView distribution below) |
| `TableColumnBuilder` | blocks, optionals and either branches, `TableColumnForEach`, `Group` of columns |
| `KeyPathComparator`, `SortOrder`, `sorted(using:)` | Foundation's on Apple platforms; on wasm `SortOrder`, `SortComparator` and `sorted(using:)` are WebFoundation's (decision 0017) and `API/SortComparators.swift` defines `KeyPathComparator` (key path, `order`, the comparator form, `Hashable`) |
| Selection | a press toggles a row and focuses the table; Up/Down/Home/End move it, Shift extends a set selection from the anchor |
| Sorting | a press on a sortable header sets `sortOrder` to that column forward, again reverses; the app sorts its data (as with Apple's table) |
| `Table(of:columns:rows:)` with `TableRow` and `TableRowBuilder` (with and without a selection) | implemented: the rows are the ones built |
| `Table(_:children:columns:)` (outline rows, with and without a selection) | implemented: rows with children show a disclosure chevron; a press on the chevron (or the indent before it), Right and Left on the selected row expand and collapse; children follow at a level's indent |
| `tableStyle(.automatic / .inset / .bordered)`, `.inset(alternatesRowBackgrounds:)`, `.bordered(alternatesRowBackgrounds:)` | implemented: automatic and inset are the measured default; bordered measured below |
| `tableColumnHeaders(.hidden)` | implemented: no header, rows from 5 |
| `alternatingRowBackgrounds(.enabled / .disabled / .automatic)` | implemented: the bands on or off (automatic follows the style) |
| Row scrolling, horizontal scrolling | implemented: the wheel scrolls rows that do not fit and overflowing columns sideways (`_Scrollable`); the keyboard selection scrolls its row into view |
| Column resizing | implemented: the 8 pt zone around a header divider shows the column-resize pointer and drags the pitch (whole points, the column's minimum); the dragged column keeps it |
| `contextMenu(forSelectionType:)` on a table | implemented (`_ListRowIdentifying`): the row under a secondary press, or the selection when it is selected |
| Column customisation (`TableColumnCustomization`), the focused table's accent selection, `disclosureGroup`'s expansion binding, `tableColumnHeaders` on iOS | missing |

## Behaviour

`Table` is a composite: it evaluates every column's content for every row (an `AnyView` per
cell) and hands `_TableHost` the rows, column descriptors (title, width, sortable, current sort)
and a sort action; `TableNode` keeps one node per cell keyed by row identity and column. The node
fills its proposal (300 × 200 unproposed, unverified). It paints a white ground, the 28 pt header
(titles 10 pt into their columns in the 11 pt system font, bold for the sorted column, whose
chevron sits 8 pt before the header cell's end; 1 pt dividers at 26/255 from 6 to 22 down; a
1.5 pt bottom line from 27 — macOS 27; 26.2 drew 1 pt), then 24 pt rows from 33 down: every second row a 244-grey band with 6 pt
corners inset 10 pt from both sides (running to the bottom whether or not rows are there), the
selected rows a 220-grey band (the inactive window's selection; a focused table's accent
selection is not painted yet). Cells are placed 8 pt into their column and 4 pt into the row,
proposed the column's SwiftUI width.

### Column widths (NSTableView's layout)

Every column has an ideal *pitch*: its SwiftUI width plus the 8 pt leading and 6 pt trailing cell
insets and the 3 pt intercell spacing. Automatic columns are 100 wide (pitch 117); `width(80)` is
97; `width(min:ideal:max:)` uses `ideal` (100 without one) and clamps to `min`/`max` plus 17.
The columns start 8 pt in and fill the table's width less 15 (8 leading, 7 trailing):

- **Grow** (the ideals fit): the surplus is shared equally by the columns that can grow (fixed
  and maxed-out columns pass their share on), each share rounded to the nearest half point,
  ties up. Two automatic columns in 360 pt are 172.5 pitches; four in 600 are 146.5.
- **Shrink** (the ideals exceed the width less 15 but not the width): every non-fixed column
  loses 15 ÷ count (rounded the same way): three automatic columns in 360 pt are 112, two in
  235–248 pt are 109.5, four in 480 are 113. The last column then ends short of the trailing
  margin and shows a trailing divider.
- **Overflow** (the ideals exceed the width): the columns keep their ideals and run off the
  right edge (two automatic columns in 230 pt are still 117 apart).

A column's content frame is its pitch less the 3 pt spacing; the divider is the last point of the
gap. The last column's divider is drawn only when its gap ends before the trailing margin (three
columns in 380 pt: pitches 121.5 leave 0.5 pt and draw it; in 370 pt pitches 118.5 overshoot by
0.5 and do not).

## Measured (macOS 26.2, fixtures `table/*` and 46 throwaway width fixtures, 2026-09-04)

| Property | Value | Probe |
|---|---|---|
| Frame | fills its proposal (360 × 220; `frame(width: 240, height: 120)` honoured) | `table` |
| Header | 28 pt; titles' origin 10 pt into the column; dividers 229-grey, x = pitch end − 1, y 6…22; bottom line at 27 | pixels of `basic` |
| Sorted header | bold title; chevron 7 × 4 with 1.5 pt strokes ending 8 pt before the header cell's end (the next column for inner columns, the content end for the last); a sorted first column also draws a divider at x = 9 | pixels of `sorting`, `sorting/byCount` |
| Rows | 24 pt from y = 33; cells at column x + 8, y + 4 | `color1` (128, 37), `count3` (240, 85) |
| Bands | odd rows 244-grey, 6 pt corners (approximate), x 10…350 in 360, continuing below the data | pixels of `basic` |
| Selection | 220-grey band on the selected row (inactive window) | `selection/select1`, `select3`, `clear` |
| Automatic columns | pitch 117 ideal; 3 in 360 → 8, 120, 232 (shrink); 2 in 360 → 8, 180.5 (grow); 2 in 240 → 8, 117.5 (shrink); 2 in 200 → 8, 125 (overflow); 4 in 600 → 8, 154.5, 301, 447.5 | `basic`, `sorting`, `sized`, `regimes` |
| Fixed and flexible | `width(80)` + `width(min: 40, ideal: 60, max: 100)` + automatic in 360 → 8, 105, 209 (the fixed column keeps 97, the others grow 27 each); a flexible column grows to its `max`; `width(min: 150, ideal: 200)` + automatic → 8, 230.5 | `widths`, throwaway fixtures |
| Sorting | pressing "Count" sorts forward, again reverse; rows follow the re-sorted data | `sorting/byCount` (Apple's re-created cells report no probes: `name2`, `name3`, `count2`, `count3` are ignored) |

### The corners (sw-table, macOS 27, `table/corners` and `table/outline`, 2026-10-11)

The table's SwiftUI frame keeps its fractions (three in a 344 pt stack are 114.667 each) while
AppKit aligns the hosted scroll view inside it to the pixel: `TableNode.aligned` rounds the
frame's root edges to the display scale and everything is drawn from them (the middle of the
three tables is 115 tall from 122.5, the others 114.5).

| Property | Value | Probe |
|---|---|---|
| Hidden headers | no header; rows from y = 5 (cells at 9) | `hiddenName1` (16, 9) |
| Bordered style | a 1 pt 192-grey border; columns from 1 to 359 (margins 1), the surplus shared by all but the last column in whole points, the remainder to the first (three automatic columns in 360: pitches 121, 120, 117); the first column's title and cells 2 pt less in (9 and 7 from the edge); titles a point lower; the 1.5 pt header line from 28; rows from 29 with a 1 pt 230-grey separator at each row's last point; no bands | `count1` (250, 155.5), pixels |
| `TableRow` builders | the rows built, in order | `rowName1`, `rowName3`; no `rowName2` |
| Outline | the first column's title and cells 9 pt further in; a 5 × 8 chevron (1.5 pt strokes, half-black) 8.5 pt into the column pointing right while collapsed, down expanded; children 16 pt further per level (unmeasured: the harness cannot expand a row) | `id1`, `id2`, pixels |

## Verification (2026-09-04; macOS 27 goldens and the corners 2026-10-11)

2026-10-11: the twelve `table/` renders are pixel-exact in Tier C (the 0.5 % of 2026-09-04 was
the header drawn at 13 pt) and ≤ 0.42 % in Tier B (Chromium). `TableTests.hiddenHeadersBorderedAndRows`
and `outlineScrollingDragsAndContextRows` cover the corners, outline rows, the wheel and the
keyboard scrolling, header-divider drags and `contextSelection(at:)`.



Tier A: all 6 fixtures exact, the `selection` (3 steps) and `sorting` (1 step) steps included.
Tier B: frames exact in Chromium and WebKit; Firefox's hinting shifts "Above" in `table/sized`
(the known class). Pixels ≤ 0.80 % (Chromium), ≤ 0.57 % (WebKit), ≤ 0.87 % (Firefox). Tier C
≤ 0.57 %. `TableTests` cover the width regimes, the painted header, dividers and bands, selection
by press and keys, and sorting by header presses.

## Not yet covered

The focused (accent) selection, column customisation, the level indent of expanded outline
rows (16 assumed), the unverified ideal size and automatic minimum width (10 assumed).
