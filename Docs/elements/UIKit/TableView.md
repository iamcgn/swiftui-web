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

Open: row animations, editing (swipe to
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
