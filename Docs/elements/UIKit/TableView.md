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
Rows with automatic heights and no estimate still build every cell (their height needs it);
an estimate is taken as the height, not corrected when the cell appears.

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

Open: editing (swipe to
delete, reordering), `UIListContentConfiguration` / `contentConfiguration`, section index titles,
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
