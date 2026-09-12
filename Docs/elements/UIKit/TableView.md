# UITableView

`Packages/UIKitWeb/Sources/UIKitWebCore/Containers/UITableView.swift` (decision 0014, Phase 4):
`UITableView`, `UITableViewCell`, `UITableViewHeaderFooterView`, the data source and delegate
protocols, `IndexPath.row` / `section` on Foundation's index path (and an empty `NSObject`
stand-in on wasm, where data sources written for UIKit subclass it). Fixtures
`uikit/table/plain`, `subtitle`, `grouped`, `selection` (steps select and deselect), exact in
`UIKitGoldenFrameTests` and within 1.7 % in `UIKitPixelTests`, from the iPhone SE simulator on
iOS 26 (`scripts/gen-goldens-sim.sh uikit --dump uikit/table/` lists UIKit's cell internals).

## API

- `UITableView`: `init(frame:style:)` (`plain`, `grouped`, `insetGrouped`), `dataSource`,
  `delegate` (a `UITableViewDelegate`, which is a scroll view delegate), `rowHeight`,
  `sectionHeaderTopPadding`, `separatorStyle`, `separatorColor`, `separatorInset`,
  `allowsSelection`, `allowsMultipleSelection`, `tableHeaderView`, `tableFooterView`,
  `register(_:forCellReuseIdentifier:)`, `dequeueReusableCell(withIdentifier:)` (and the
  `for:` form), `reloadData` (and the row and section reload, insert and delete calls, which
  reload), `beginUpdates` / `endUpdates` / `performBatchUpdates`, `visibleCells`,
  `indexPathsForVisibleRows`, `cellForRow(at:)`, `indexPath(for:)`, `rectForRow(at:)`,
  `indexPathForRow(at:)`, `numberOfSections`, `numberOfRows(inSection:)`,
  `indexPathForSelectedRow(s)`, `selectRow(at:animated:scrollPosition:)`, `deselectRow`,
  `scrollToRow`. A tap selects a row through `willSelectRowAt` / `didSelectRowAt`.
- `UITableViewDataSource`: `numberOfSections`, `numberOfRowsInSection`, `cellForRowAt`,
  `titleForHeaderInSection`, `titleForFooterInSection` (editing calls accepted).
  `UITableViewDelegate`: `heightForRowAt`, header and footer heights and views,
  `willSelectRowAt`, `didSelectRowAt`, `didDeselectRowAt`, `willDisplay`.
- `UITableViewCell`: `init(style:reuseIdentifier:)` (`default`, `subtitle`, `value1`, `value2`
  as value1), `textLabel`, `detailTextLabel`, `imageView`, `contentView`, `accessoryType`
  (disclosure indicator, checkmark, detail buttons drawn as their glyphs), `accessoryView`,
  `selectionStyle`, `isSelected` / `setSelected`, `isHighlighted`, `prepareForReuse`.
  `UITableViewHeaderFooterView`: `textLabel`, `contentView`.

## Measured (iOS 26, iPhone SE simulator)

- Plain rows with a 17 pt title are 56 tall; the title label spans the row (16 in, the text
  centred). Subtitle rows are 73 tall: the title 24.5 tall at 11, the 15 pt detail 21 tall at
  38.5. Value1 rows are 56 tall with the title at (16, 16) and the detail right-aligned 16 from
  the row's right edge, or 8 before an accessory.
- Separators are 1 pt at the row's bottom, from 16 in to 16 before the right edge in the plain
  style (`(0, 0, 0, 25/255)`: (232, 232, 232) over white); an inset grouped section's last row
  has none, and a row with an accessory stops the line where the accessory starts.
- Accessories: the disclosure chevron 10.5 × 14, centred vertically, 16 from the right (the
  content view ends where it starts); the checkmark 19 × 18, 18.5 from the right.
- A plain section header is 28 tall with a 17 pt semibold title 16 in and 2 down, and the first
  header sits under 22 pt of padding (`sectionHeaderTopPadding`); rows without a header start
  at 0.
- Inset grouped: the ground is (242, 242, 247); cards 16 in (288 wide in 320) with 26 pt corners
  on a section's first and last rows; the first header is 55.5 tall (title 17 pt semibold at
  (32, 27)), later headers 38 (title at 9.5); a footer is a 13 pt secondary label 4.5 down,
  21 tall for one line (30 in all).
- Selection fills the row with `systemGray4` (209, 209, 214).

## Recycling

Rows whose height is known without their cell (the delegate's `heightForRowAt`, `rowHeight`,
or `estimatedRowHeight`) are laid out as frames alone; cells exist for the rows in view plus
half a viewport above and below, are returned to the reuse pool as they scroll out
(`dequeueReusableCell` hands them back), and `cellForRowAt` runs as rows appear
(`TableRecyclingTests`: a thousand 44 pt rows in a 400 pt table cost fewer than 30 cells).
Rows with automatic heights and no estimate still build every cell (their height needs it).

## Self-sizing rows (2026-09-11, `uikit/table/selfsizing`)

With `rowHeight` automatic and an `estimatedRowHeight`, a row is laid out at the estimate until
its cell appears; the cell then measures itself for the row's width and, when the height
differs, the table lays every row out again keeping the cells it has made (the estimate is
never trusted twice: measured heights stay until `reloadData`). A cell's automatic height is,
in order: its content configuration's fit (at least 56); constrained content's fitting size for
the row width required (`systemLayoutSizeFitting` with the width at the required priority, as
UIKit sizes cells: a 15 pt label 12 above and below gives 61 for two lines, 79 for three, 56.5
for two 13 pt lines); a default cell's wrapping `textLabel` plus 13.75 above and below (the
labels use the body and subheadline text styles as UIKit's do, so the lines are 26 apart: three
lines are 76.5 tall in a 104 pt row, one line stays at the 56 minimum); else the style's 56 or
73. Measured on the simulator; frames exact, pixels within the text-heavy tolerance. See the
wrapping-label rules in `Docs/elements/UIKit/AutoLayout.md`.

## Batch updates (2026-09-11)

`Containers/BatchUpdates.swift`. `insertRows` / `deleteRows` / `reloadRows` / `moveRow`,
`insertSections` / `deleteSections` / `reloadSections` / `moveSection`, `beginUpdates` /
`endUpdates` and `performBatchUpdates(_:completion:)` record an update (deletes and reloads
name old index paths, inserts new ones, as UIKit's batch semantics have it; a call outside a
batch is its own update). Committing it maps every surviving row to its new place: the rows a
section keeps take the new indices its inserts and moved-in rows leave free, in order. The
table then lays out for the new data keeping the surviving rows' cells, which slide from their
old frames to the new ones over 0.3 s, while deleted rows' cells fade out on top and inserted
rows' cells fade in; reloaded rows get a fresh cell at once. The completion runs when the
animation ends. A table off screen or before its first layout just reloads (`RowAnimation` is
accepted; every animation is the fade and slide). `BatchUpdateTests` drive the scene's clock
through an update.

## Editing and swipe actions (2026-09-11, `uikit/table/editing`)

`Containers/SwipeActions.swift`. `isEditing` / `setEditing(_:animated:)` (animated over 0.3 s),
`allowsSelectionDuringEditing`; the data source's `canEditRowAt` (true by default, as UIKit),
`canMoveRowAt`, `moveRowAt`, `commit editingStyle`; the delegate's `editingStyleForRowAt`
(delete by default), `titleForDeleteConfirmationButtonForRowAt`, `shouldIndentWhileEditingRowAt`,
`trailingSwipeActionsConfigurationForRowAt` / `leadingSwipeActionsConfigurationForRowAt`,
`willBeginEditingRowAt` / `didEndEditingRowAt`; the cell's `editingStyle`, `showsReorderControl`,
`setEditing`, `isEditing`; `UISwipeActionsConfiguration` (`performsFirstActionWithFullSwipe`)
and `UIContextualAction` (style, title, `backgroundColor`, handler with its completion).

Measured in editing mode: an editable row's content view starts 40 in (the accessory hidden)
behind a 22 pt circle centred at (28, 22), red with a white minus for a delete row, green with
a plus for an insert row; a movable row with `showsReorderControl` ends its content 43 from the
right behind a 27 pt grip of three grey lines, and its title ends 8 before the content's edge
(as it does before an accessory) rather than 16; a row that cannot be edited stays put. Swipes:
a horizontal pan on a row with actions on that side (a plain editable row offers "Delete")
slides the content sideways and reveals the buttons from the edge (17 pt white titles on the
action colour, at least 74 wide, rubber-banding past their width); the row settles open past
half the buttons' width or on a flick, else closed; a swipe past the row's midpoint performs
the first action when the configuration allows; a tap on a button runs its handler and closes
the row; a tap elsewhere closes it; vertical pans scroll. The delete control reveals the Delete
button, the insert control commits an insert. `EditingTests` drive the scene's pointer through
all of it. Reordering: a pan that starts on a movable row's grip lifts the row (it follows
the finger within its section, above the others), the rows whose middles it crosses make way
over 0.2 s, and on release the data source's `moveRowAt` runs and the rows settle into the new
order through the batch-update path. Not measured: the buttons' widths and font (UIKit's are
approximated), the leading side's look, the lifted row's shadow (none is drawn).

Open: `UIListContentConfiguration` / `contentConfiguration`, section index titles,
`UICollectionView`, the grouped (non-inset) style's exact geometry, dark appearance.

## Content configurations (2026-09-11)

`Containers/ContentConfiguration.swift`. `UITableViewCell.contentConfiguration` and
`UICollectionViewCell.contentConfiguration` (`UIContentConfiguration`, `UIContentView`,
`UIViewConfigurationState`, `UICellConfigurationState`) make a content view that fills the cell's
content view and sizes automatic rows; `backgroundConfiguration` applies its colour.
`UIListContentConfiguration` (`cell()`, `subtitleCell()`, `valueCell()`, the header and footer
variants; `text`, `secondaryText`, `image`, `textProperties`, `secondaryTextProperties`,
`directionalLayoutMargins`, `imageToTextPadding`) draws a `UIListContentView` laid out like the
cell styles (approximate: no golden yet; the margins are UIKit's documented 11 / 20).
`UIHostingConfiguration` (SwiftUIWebUIKit) hosts SwiftUI the same way
(`Docs/elements/Representable.md`).

## Pinned headers (2026-09-11, `uikit/table/pinned`)

A plain-style section header sticks to the top of the visible bounds while its section scrolls
under it and is pushed up as its section's last row leaves (its bottom never passes the
section's end: at offset 260 the first header sits at -14 with its rows ending at 14, the
second header at 36); `headerView(forSection:)` / `footerView(forSection:)` return the views on
show. Grouped styles do not pin. Every titled plain header, not only the first, sits 22 below
what precedes it (the second section's header at 296 after rows ending at 274). A pinned header
draws a scrim over the rows passing under it: black at 15 % at its top easing to nothing 60 pt
down (the golden's grey 217, 230, 238, 247, 254 at 0, 20, 30, 45 and 60 pt; `(1 - t)^1.2`),
and the scrim rides with a header being pushed away. Pixels: 0.8 % at rest, 1.2 % scrolled,
1.0 % pushed.
