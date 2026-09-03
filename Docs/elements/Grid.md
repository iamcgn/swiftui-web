# Grid, GridRow

Apple docs: [Grid](https://developer.apple.com/documentation/swiftui/grid),
[GridRow](https://developer.apple.com/documentation/swiftui/gridrow),
[gridCellColumns(_:)](https://developer.apple.com/documentation/swiftui/view/gridcellcolumns(_:)),
[gridColumnAlignment(_:)](https://developer.apple.com/documentation/swiftui/view/gridcolumnalignment(_:)),
[gridCellAnchor(_:)](https://developer.apple.com/documentation/swiftui/view/gridcellanchor(_:)),
[gridCellUnsizedAxes(_:)](https://developer.apple.com/documentation/swiftui/view/gridcellunsizedaxes(_:)).

## API surface

| API | Notes |
|---|---|
| `Grid(alignment:horizontalSpacing:verticalSpacing:content:)`, `GridRow(alignment:content:)` | implemented |
| `gridCellColumns`, `gridColumnAlignment`, `gridCellAnchor`, `gridCellUnsizedAxes` | implemented |
| Views outside a `GridRow` | implemented: a row spanning every column |
| `GridLayout` as a `Layout` value, `LazyVGrid`/`LazyHGrid`/`GridItem` | missing |

## Behaviour

`GridNode` walks its content: a `GridRowNode` (transparent, `_GridRowProviding`) contributes its
layout children as cells, a lone layout child becomes a row spanning all columns, and a unary
modifier on a row applies to each cell through the modifier's proxies. `plan` sizes columns
(rigid widths, flexibility, spans), resolves the proposal, then rows: each cell's `dimensions`
for its column width, the row's guide (`GridRow(alignment:)` or the grid's vertical alignment)
and height, the vertical gap from the cells' spacing preferences; cells are placed by anchor or
by the column's horizontal alignment through their alignment guides. `paintedChildren` are the
cells, so transitions and ghosts work as in stacks.

## Measured (macOS 26.2, `grid/basic`, `spacing`, `modifiers`, `alignment`, `flexible`, 2026-09-03)

| Rule | Value | Probe |
|---|---|---|
| Column width | the widest rigid cell in the column ("A"/red/"G" → 30; "BB"/"E"/"H" → 17; "CCC"/blue → 50), columns 8 pt apart: 113 wide | `grid`, `red`, `bb`, `blue` |
| Row height and spacing | the tallest cell (16, 40, 16); gaps are the widest spacing distance between stacked cells: 8.15 under a text row, 4.74 above one (84.89 tall) | `a` (57.55), `blue` (81.70), `g` (126.45) |
| Cell alignment | the grid alignment: `.center` centres "A" in its 30 pt column and "E" in the 40 pt row; `.topLeading` puts cells at their cell's origin; `.bottomTrailing` at its far corner | `a` (114), `e` (93.70); `grid/spacing`; `grid/alignment` |
| Explicit spacing | `horizontalSpacing: 20, verticalSpacing: 4`: 60 + 20 + 30 wide, 30 + 4 + 20 tall | `grid/spacing` |
| `gridCellColumns(2)` | "Header" spans columns 1–2 at the grid's alignment; a spanning cell ignores column alignments | `header` (0, 67.85) |
| `gridColumnAlignment(.trailing)` | "A" trails in its 78 pt column (x = 69) | `a` |
| `gridCellAnchor(.bottomTrailing)` | "E" at the far corner of its cell | `e` (312, 116) |
| A flexible view outside rows | the 4 pt green fills the 320 proposal and the extra 207 spreads equally: columns 9 + 69, 60 + 69, 28 + 69 | `divider`, `red` (86), `ccc` (223) |
| `gridCellUnsizedAxes(.horizontal)` | the blue fills its 78 pt column but did not size it | `blue` (0, 152.15, 78) |
| Flexible columns | three columns each holding a flexible colour share `frame(width: 280)` equally: 88 each | `grid/flexible` |
| A row's `.probe` | reports the last cell (the modifier applies per cell) | `row1` = `ccc` |

## Verification (2026-09-03)

Tier A: 5 fixtures exact. Tier B 5/5 in Chromium, WebKit and Firefox. `GridTests` cover
rigid columns and spans, anchors, column alignment, flexible sharing and the flexible spanning
row. wasm js tests pass.

## Not yet covered

`GridLayout` as a `Layout` value (and `AnyLayout(GridLayout())`), lazy grids, rows with more
cells than the widest earlier row combined with spans in later rows (columns are counted from
the widest row), right-to-left, animating cell changes.
