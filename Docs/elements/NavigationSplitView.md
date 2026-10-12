# NavigationSplitView

Apple docs: [NavigationSplitView](https://developer.apple.com/documentation/swiftui/navigationsplitview),
[NavigationSplitViewVisibility](https://developer.apple.com/documentation/swiftui/navigationsplitviewvisibility),
[navigationSplitViewColumnWidth(_:)](https://developer.apple.com/documentation/swiftui/view/navigationsplitviewcolumnwidth(_:)),
[navigationSplitViewColumnWidth(min:ideal:max:)](https://developer.apple.com/documentation/swiftui/view/navigationsplitviewcolumnwidth(min:ideal:max:)),
[navigationSplitViewStyle(_:)](https://developer.apple.com/documentation/swiftui/view/navigationsplitviewstyle(_:)).

## API surface

| API | Notes |
|---|---|
| `NavigationSplitView(sidebar:detail:)`, `NavigationSplitView(sidebar:content:detail:)` | implemented: the macOS two- and three-column split |
| `NavigationSplitView(columnVisibility:…)` (both column counts) | implemented; `.detailOnly` hides the leading columns, `.doubleColumn` hides the sidebar of a three-column split, `.automatic` shows everything; without a binding the view keeps its own visibility |
| `NavigationSplitView(preferredCompactColumn:…)` (with and without `columnVisibility`) | implemented 2026-10-11 for a compact width (the iOS profile): one column fills the view — the preferred one — a link in a leading column shows the detail (its stack pushed; the binding moves to `.detail`) and the stack's pop to its root returns to the column |
| `NavigationSplitViewVisibility` (`.all`, `.doubleColumn`, `.detailOnly`, `.automatic`), `NavigationSplitViewColumn` | implemented |
| `navigationSplitViewColumnWidth(_:)`, `navigationSplitViewColumnWidth(min:ideal:max:)` | implemented on the sidebar and content columns (the ideal, clamped to the range; a fixed width is all three); on the detail column ignored (it takes the rest, as on macOS) |
| `NavigationSplitViewStyle` (`.automatic`, `.balanced`, `.prominentDetail`), `navigationSplitViewStyle(_:)` | accepted; every style is the macOS look (macOS draws the two alike at a window's width) |
| Sidebar toggle | `Runtime.toggleSidebar()` for hosts and ⌃⌘S in `Runtime.keyDown`; a host painting window chrome gets the `sidebar.leading` button leading the toolbar (2026-10-11), as macOS puts it |
| Drag-resizing and collapsing | implemented 2026-10-11: the 8 pt zone on either side of the sidebar's edge and of the content divider shows the column-resize pointer and drags the column within its range (`navigationSplitViewColumnWidth`'s bounds); a sidebar dragged narrower than half its minimum (half the 144 default without one) collapses to `.detailOnly` on release and comes back at its default width |
| Links in the leading columns | a `NavigationLink` (destination or value form) in the sidebar or content column shows its destination in the detail column, which is an implicit navigation stack (`navigationDestination(for:)` registered in a leading column resolves value links; `Runtime.navigateBack()` and `dismiss` pop) |
| `NavigationView` (deprecated), `navigationViewStyle` | missing |
| The sidebar's material | the column is the opaque (251) fill the macOS 27 golden shows in a window; the translucent material over the desktop is not drawn |

## Behaviour

`NavigationSplitView` is a composite: its body reads the visibility (binding or private `@State`)
so observation tracks it and hands `_NavigationSplitViewHost` the three columns. The node lays
the columns out left to right (`NavigationSplitViewNode`): the sidebar column is 8 pt wider
than its panel, the white panel (corner radius 7.5) being inset 8 pt on every side; a `List` in
it fills the panel and any other content is centred in it; the next column starts at the panel's
trailing edge, so the leading 8 pt of the content or detail column sits under the sidebar's
trailing inset. A content column is a plain full-height column of its width followed by a 1 pt
divider. The detail takes the rest of the width, its content centred; it is an implicit
`NavigationStackNode` so links in the leading columns push there. Lists in the sidebar column
default to the sidebar style, drawn without the style's grey background (the panel is the
background). The split view fills what it is proposed.

## Measured (macOS 27, regenerated 2026-10-11; the 26.2 values of 2026-09-04 in brackets)

macOS 27 draws the classic split: the sidebar is a column from the window's edge, full height,
filled (251, 251, 251) with a half-point (201) line along its trailing edge; the detail starts
at the column's edge. (26.2 floated a white 140 pt panel inset 8 on every side with 7.5 pt
corners.) Column widths are the defaults clamped to a `navigationSplitViewColumnWidth` range —
the ideal is not taken — so a `min: 100, ideal: 120, max: 200` sidebar is 144 and a
`min: 120, ideal: 160, max: 220` content column 200; a fixed width is itself.

| Property | Value (macOS 27) | Probe |
|---|---|---|
| Sidebar column | 144 wide at the origin, full height; `navigationSplitViewColumnWidth(150)` makes it 150 | `sidebar` |
| Sidebar content | a list's first row at (16, 16.75) (margin 16, top inset 16.75, 32 pt body rows); a `VStack` centred in the column | `row1`, `menu`, `sidebar` in `widths` |
| Detail | from the column's edge (144; 150 for a 150 column): "Detail" centred in 144…480 at 294.5 | `detail` |
| Content column | 200 wide at 144 (its range's bounds only), full height; "Cherry" at (160, 14); a 1 pt divider at black 25/255 follows, the detail after it | `content`, `contentRow`, `detail` in `three` |
| Selection | `List(selection:)` in the sidebar drives the detail: "Number 1" centred at 312 | `splitview/selection` steps |

Tier A exact on every fixture and step; Tier C and B within 0.3 % (the selection steps 2.8 %:
the selected row's look), so the fixtures left the approximate list.

## Measured (macOS 26.2, kept for the record, 2026-09-04)

| Property | Value | Probe |
|---|---|---|
| Frame | fills the window (480 × 300) or its frame (320 × 200 at (80, 50)) | `split` |
| Sidebar panel | 140 wide by default, at (8, 8), 284 tall in a 300 pt window: inset 8 on every side; corner radius ≈ 7.5 (the ramp along the edge crosses 4.7 pt from the corner, the diagonal 2.2 pt); white, no border | `sidebar`, pixels |
| Sidebar width | `navigationSplitViewColumnWidth(150)` makes the panel 150 (8…158), `min: 100, ideal: 120, max: 200` makes it 120 | `sidebar` in `widths`, `columns` |
| Sidebar content | a list fills the panel: "Apple" 35 × 18.5 at (24, 24.75) (margin 16, top inset 10, 32 pt body rows); a `VStack` is centred in the panel (40 × 44 at (63, 128) in a 150 panel) | `row1`, `row2`, `sidebar`, `menu` |
| Detail | starts at the panel's trailing edge (148 by default, 158 for a 150 panel): "Detail" 35 × 16 at (296.5, 142) is centred in 148…480; a `VStack` likewise (40 × 44 at (299, 128) in 158…480) | `detail`, `detailStack` |
| Content column | 200 wide by default (128…328 after a 120 panel), 160 with `ideal: 160`; full height from y = 0; an inset list: "Cherry" 41.5 × 16 at (164, 14); a 1 pt divider follows (308…309), then the detail (centred at 474.5 in 309…640) | `content`, `contentRow`, `detail` in `three`, `columns` |
| Selection | `List(selection:)` in the sidebar with tagged rows drives the detail: "Number 1" 58 × 16 at (285, 142) | `splitview/selection` steps |
| Visibility | Apple's offscreen window hides a collapsed sidebar's pixels but keeps its frame and the detail's place; the runtime collapses for real (the detail fills the width), so those probes are ignored in the collapsed states (`ignoredProbes`) and only the `showAll` step is compared in full | `splitview/visibility` |
| Capture limits | the sidebar's material and its list's rows and selection are not captured (the sidebar column is a separate hosting view); a black-to-clear gradient fills the 8 pt bands beside the panel in the goldens (a rendering artefact, not reproduced) | pixels |

## Verification (2026-09-04)

Tier A: all 7 fixtures exact, the `selection` steps included; in `visibility` the initial and
`detailOnly` states compare only `split` (Apple's offscreen window leaves the collapsed sidebar's
frame and the detail's place stale, `ignoredProbes`), the `showAll` step everything. Tier B,
frames exact in Chromium and WebKit for every fixture and step; Firefox exact but for
`selection/select1`, where "Number 1" is its usual 0.5 pt wider (284.75 / 58.5 against 285 / 58).
Pixels, Tier B and C alike: 0.0 % for the collapsed `visibility` states, 2.2–3.9 % elsewhere
(Chromium ≤ 3.88 %, WebKit ≤ 3.87 %, Firefox ≤ 3.88 %, native ≤ 3.87 %), all of it the goldens'
gradient artefact in the 8 pt bands beside the panel plus the sidebar rows Apple's capture
drops, so the `splitview/` fixtures are listed as approximate (a 9 % bound).
`NavigationSplitViewTests` cover the column geometry, widths, visibility (binding, own state,
toggle, ⌃⌘S), the three-column double-column case and links driving the detail.

## Not yet covered

The sidebar's toolbar button and glass material, drag-resizing and collapsing by drag, the
`.balanced`/`.prominentDetail` distinction, `NavigationView`, the detail column's own width
preferences, the collapse animation, keyboard focus between columns.
