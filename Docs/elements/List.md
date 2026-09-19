# List

Apple docs: [List](https://developer.apple.com/documentation/swiftui/list),
[ListStyle](https://developer.apple.com/documentation/swiftui/liststyle),
[listStyle(_:)](https://developer.apple.com/documentation/swiftui/view/liststyle(_:)),
[listRowInsets(_:)](https://developer.apple.com/documentation/swiftui/view/listrowinsets(_:)),
[listRowBackground(_:)](https://developer.apple.com/documentation/swiftui/view/listrowbackground(_:)),
[listRowSeparator(_:edges:)](https://developer.apple.com/documentation/swiftui/view/listrowseparator(_:edges:)),
[listRowSeparatorTint(_:edges:)](https://developer.apple.com/documentation/swiftui/view/listrowseparatortint(_:edges:)).

## API surface

| API | Notes |
|---|---|
| `List { }` (content builder), `List(selection: Binding<V?>)`, `List(selection: Binding<Set<V>>)` | implemented |
| `List(data)`, `List(data, id:)`, `List(Range<Int>)`, each with an optional single or multiple `selection:` | implemented (rows are a `ForEach`) |
| `List(data, children:)` (outline), `List(Binding<C>)` and `editActions:` forms | missing |
| `ListStyle`: `.automatic` (= inset on macOS), `.inset`, `.plain`, `.bordered`, `.sidebar`; `listStyle(_:)` | implemented; `.inset(alternatesRowBackgrounds:)` / `.bordered(alternatesRowBackgrounds:)` missing; custom styles are not (Apple's protocol is closed) |
| `listRowInsets(_:)`, `listRowBackground(_:)` | implemented |
| `listRowSeparator(_:edges:)`, `listRowSeparatorTint(_:edges:)` | implemented for the bottom edge (macOS draws one separator per row); the top edge is ignored |
| `listSectionSeparator(_:edges:)`, `listSectionSeparatorTint(_:edges:)`, `listItemTint(_:)` | `listSectionSeparator(.hidden)` hides the header's line (2026-09-19, `list/separators`); the tint is stored (macOS draws the standard grey); `listItemTint` tints a row's label icons (`list/tint`) |
| `Visibility`, `VerticalEdge`, `VerticalEdge.Set` | implemented |
| Selection by press: single (press again deselects), multiple (accumulates) | implemented; keyboard navigation with Shift ranges and an accent selection when focused since 2026-09-04 (`Docs/elements/Keyboard.md`); Cmd ranges and the real focused look missing |
| `Section` inside a list: header and footer styling, spacing, pinned first header | implemented (`Docs/elements/ForEach.md` for `Section` itself) |
| `Label` inside a list: fixed icon slot and accent tint | implemented (`Docs/elements/Label.md`) |
| `listRowSpacing`, `listSectionSpacing` (iOS API), `alternatingRowBackgrounds`, `.inset(alternatesRowBackgrounds:)`, `scrollContentBackground`, `headerProminence` | implemented 2026-09-19 (the looks section below) |
| `List(_:children:)`, `OutlineGroup`, `DisclosureGroup` in a list | implemented 2026-09-19: outline rows with a chevron column, children a level deeper while expanded (`list/outline`) |
| `swipeActions`, `onDelete`/`onMove`, `deleteDisabled`/`moveDisabled`, `editMode`, `refreshable` | implemented 2026-09-18 (the editing section below) |
| `listRowHoverEffect` | missing |

## Behaviour

`List` is a composite: its body reads the `ListStyle` environment and wraps a `_ListContent`
primitive in a vertical `ScrollView`, paints the style's background behind it, the first section's
header pinned at the top over it, and the bordered style's border around it. `ListContentNode`
walks the content once per layout: a `Section` contributes its header, rows and footer, a `ForEach`
its rows with their identity (the selection key), a unary modifier on a section or `ForEach`
(`probe`, `padding`, `listRowInsets`…) applies to each element (the modifier's proxies stand in
for them, see `LayoutModifierProxy`), other containers are transparent. Every element is a
full-width cell; row content is inset by the style's margin plus the row insets, at least the
minimum row height tall and centred vertically. Painting order: separators, then per row its
`listRowBackground` layers, the selection highlight and the row itself. A press that ends inside
the list picks the row under the pointer (`_Interactive.pressEnded(inside:at:)`, new; the default
forwards to `pressEnded(inside:)`) and toggles it in the binding; the binding is read in the body
so observation re-renders when the model changes it.

## Measured (macOS 26.2, `list/basic`, `list/sections`, `list/styles`, `list/modifiers`, `list/steps`, 2026-09-02)

| Property | Value | Probe |
|---|---|---|
| Inset list (default) | opaque white, fills its proposal; content starts 10 pt down; rows are their content plus 4 pt above and below, at least 24 pt; row content 16 pt in from both edges (288 wide in 320) | `list`, `row1` (16, 14), `row2` (16, 38), `tall` (16, 62, 288 × 40), `wide` |
| Taller rows | a 40 pt row is 48 tall, a 24 pt label row 32 (`label` at 134 in 130…162), an 18.5 pt toggle row 26.5 (`toggle` at 166); content is centred vertically | `tall`, `wide` (110), `label`, `toggle` |
| Separators | 1 pt at black 25/255 at the bottom of every element but the last, from the content's leading edge (16 plus the leading row inset) to 16 pt before the trailing edge; hidden by `listRowSeparator(.hidden)`; a `listRowBackground` covers its own; `listRowSeparatorTint` draws the colour at full opacity (`Color.red` = 255, 56, 60) | pixels of `basic` at 33, 57, 105, 129, 161; `modifiers` at 33, (57 covered), 105 red, 129, 153 |
| `listRowInsets(2, 30, 2, 10)` | content at x = 46, 258 wide, the row stays 24 (16 + 4 < 24) | `inset` |
| `listRowBackground` | fills the whole cell edge to edge (0…320 × the row) | pixels of `modifiers` rows 34…58 |
| Section header, footer | the 11 pt subheadline semibold in the secondary colour (black at 50 %) on a 16 pt line, 6 pt above and below (28 pt cell) with a separator below; sections are 20 pt apart; a section without a header starts 20 pt after the previous separator | `vegHeader` (16, 112), `carrot` (138), `vegFooter` (164), `cherry` (210) |
| First header pinned | drawn once, in a 27 pt strip at the top of the list (baseline 17.5) over the background, with a 1 pt line at 27 (black 48/255) under a faint shadow (Apple's is a 4 pt gradient 254…248, ours a 1 pt line at 7/255); its in-flow slot stays blank with no separator, so the first row is at 10 + 28 + 4 | `apple` (16, 42), pixels of `sections` rows 0…28 |
| `.plain` | margin 8, no top inset: the first row's text at (8, 4) | `plainRow1`, `plainRow2` (8, 28) |
| `.bordered` | margin 7, a 1 pt border of black at 63/255 inside the frame, rows start below it: text at (7, 5) | `borderedRow1`, `borderedRow2` (7, 29) |
| `.sidebar` | margin 16, top inset 10, 32 pt rows in the body font (18.5 pt line) at black 70 % on a 240/255 grey background, no separators | `sidebarRow1` (16, 258.75 in a frame at 242), `sidebarRow2` (+32) |
| Selection | a rounded rectangle 10 pt in from each edge (300 wide) over the row's height, black at 35/255, corner radius 7 (approximate); the separators above and below it disappear; the hosted golden window is not focused, so the accent-blue focused look is not modelled | `list/steps` step 1 pixels rows 34…58 |
| Removing a row | the rows below close up in place | `list/steps` step 2: `item2` (16, 14) |
| `Label` in a row | 48.5 × 24: a 16 pt icon slot the 24 pt icon is centred in (overflowing 4 pt each side), 6 pt to the title, icon tinted with the accent colour (0, 122, 255) | `label` |
| `Toggle` in a row | unchanged: 70 × 18.5 | `toggle` |
| Ideal width | 200 pt (assumed; no golden) | — |

## Verification (2026-09-02)

Tier A: 5 fixtures exact (`list/steps` steps included). Tier B, frames exact: Chromium
≤ 0.73 % pixels, WebKit ≤ 0.56 %, Firefox ≤ 0.74 % (the pinned header's shadow gradient is the
largest difference, `list/sections`). wasm js tests pass.

## iOS selection (iPhone SE simulator, `ios/list/selection`, 2026-09-18)

A selected row fills its row across the card with (209, 209, 214) (`listSelectionFill`), the
separators beside it hidden. Rows outside a `ForEach` take their identity from `tag`, so a
`selection` binding matches them as on Apple's platforms.

## Editing (2026-09-18, `ListEditingTests`, `ios/list/editing`)

`ForEach.onDelete` and `onMove` (and the binding-backed `ForEach(_:editActions:)` and
`List(_:editActions:)`, which delete and move through the collection with
`remove(atOffsets:)` and `move(fromOffsets:toOffset:)`), `deleteDisabled`, `moveDisabled`,
`EditMode`, the environment's `editMode` binding and `EditButton`. A list deletes its selected
rows on the Delete key through their `ForEach` and reorders a row dragged along the list
(macOS: any press on a movable row; iOS: a press on the grip in edit mode), landing before the
row whose middle the drop passed. In edit mode on iOS the rows of a `ForEach` with `onDelete`
show a 22 pt red (255, 58, 62) disc with a white minus 17 in from the card's edge and move
their content 40 in; rows with `onMove` show three grey (197, 197, 199) 21.5 × 1 lines 5 apart,
18 from the card's trailing edge; other rows keep their place (measured on the simulator,
Tier A exact, Tier C 0.9 %). A press on the disc deletes the row at once (iOS reveals a Delete
button first: `sw-list-editing-rest`).

`swipeActions(edge:allowsFullSwipe:content:)` (iOS): a sideways drag on a row shifts its content
and reveals the edge's buttons, laid out outermost first, as full-height cells (74 pt minimum,
16 pt of padding, red for the destructive role, else the tint or grey (142, 142, 147), white
labels); past half the strip the row rests open, a press on a cell runs its button and closes
the row, a press anywhere else closes it, and a drag past 60 % of the row runs the outermost
action when `allowsFullSwipe`. A row of a `ForEach` with `onDelete` and no trailing actions gets
a trailing Delete. The geometry and colours are approximate: no golden can hold a swipe.

`refreshable(action:)` (iOS, touch): a pull past the top of a scroll view moves the content down
half the finger's distance; released past 60 pt it runs the action, the content held 60 down
behind a circular spinner until the action returns. Approximate: the rubber band and the
spinner's growth are not measured.

## Looks (macOS 26.6, `list/alternating`, `list/prominence`, `list/outline`, `list/tint`, `list/separators`, `list/background`, `list/pinning`; iPhone SE simulator `ios/list/spacing`; 2026-09-19)

| Property | Value | Probe |
|---|---|---|
| Alternating rows (`.inset(alternatesRowBackgrounds: true)`, `alternatingRowBackgrounds(.enabled)`) | every other row filled (244, 245, 245) edge to edge, no separators; the rows keep their places | `altRow1…4`, `enabledRow1…3` |
| `headerProminence(.increased)` | no change on macOS: the header keeps the subheadline look; the first header is pinned as always, its line 6 down in the 27 pt strip (the probe reads the pinned place) | `increasedHeader` (16, 6), `standardHeader` (16, 88) |
| Outline (`List(_:children:)`, `OutlineGroup`, `DisclosureGroup`) | every row moves 9 in for the chevron column; a row with children shows a 1 pt grey (128) chevron 5 × 5.5 centred 18.5 in, pointing down while expanded; children rows sit 13 further in per level; a press on the chevron column discloses (SwiftUI toggles on the chevron; the whole column here) | `Fruits` (25, 30), `dgApple` (38, 192) |
| `listItemTint` | the row's label icons take the tint (fixed and preferred alike); pixels frames-only (the symbols are stand-ins) | `green`, `orange`, `plain` |
| `listSectionSeparator(.hidden)` | the section's header line disappears; `listSectionSeparatorTint` draws the standard grey (macOS ignores the tint); `listRowSeparator(.hidden, edges: .top)` hides the line above the row | `list/separators` pixels |
| `scrollContentBackground(.hidden)` | the list's white is gone: what is behind it shows (yellow), the separators stay | `list/background` pixels |
| Pinned header while scrolling | only the first header pins and it stays as the content scrolls under it; the second section's header scrolls up beneath the strip. The content keeps the 10 pt inset below its last row, so `scrollTo` at the end leaves it 10 above the bottom | `list/pinning` `scroll` |
| iOS `listRowSpacing(12)`, `listSectionSpacing(30)` | rows become cards of their own, 12 apart, no separators; a section header sits the spacing plus its own 10 below the previous card (the default spacing is 17.5); a header-less card the spacing plus 17.5 (derived) | `a2` (32, 128.25), `b1` (32, 258.75) |

The focused accent selection stays by eye (the golden window is never key) and every row is laid
out (no laziness). `ListSectionSpacing.compact` is accepted as the default.

## Not yet covered

Focused (accent) selection, keyboard navigation and Shift/Cmd ranges, hover highlight, the
pinned header's gradient shadow, the section separator tint (macOS draws grey), lazy rows
(every row is laid out), `listRowHoverEffect`, `ListSectionSpacing.compact`.
