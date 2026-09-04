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
| `listSectionSeparator(_:edges:)`, `listSectionSeparatorTint(_:edges:)`, `listItemTint(_:)` | stored only |
| `Visibility`, `VerticalEdge`, `VerticalEdge.Set` | implemented |
| Selection by press: single (press again deselects), multiple (accumulates) | implemented; keyboard navigation with Shift ranges and an accent selection when focused since 2026-09-04 (`Docs/elements/Keyboard.md`); Cmd ranges and the real focused look missing |
| `Section` inside a list: header and footer styling, spacing, pinned first header | implemented (`Docs/elements/ForEach.md` for `Section` itself) |
| `Label` inside a list: fixed icon slot and accent tint | implemented (`Docs/elements/Label.md`) |
| `listRowSpacing`, `listSectionSpacing`, `alternatingRowBackgrounds`, `listRowHoverEffect`, `swipeActions`, `onDelete`/`onMove`, `deleteDisabled`/`moveDisabled`, `editMode`, `refreshable`, `scrollContentBackground`, `headerProminence` | missing |

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

## Not yet covered

Focused (accent) selection, keyboard navigation and Shift/Cmd ranges, hover highlight,
alternating row backgrounds, `listRowSpacing`/`listSectionSpacing`, `listItemTint` (stored) and
section separator modifiers (stored), outline lists (`children:`), edit actions (`onDelete`,
`onMove`, `swipeActions`), binding collection forms, the pinned header's gradient shadow and
sticky behaviour for later sections while scrolling (only the first header pins, and it stays
while scrolling), `scrollContentBackground`, `refreshable`, lazy rows (every row is laid out).
