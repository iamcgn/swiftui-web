# UICollectionView and UICollectionViewFlowLayout

`Packages/UIKitWeb/Sources/UIKitWebCore/Containers/UICollectionView.swift` (decision 0014,
Phase 4): `UICollectionView`, `UICollectionViewCell`, `UICollectionReusableView`,
`UICollectionViewLayout`, `UICollectionViewLayoutAttributes`, `UICollectionViewFlowLayout`, the
data source, delegate and flow layout delegate protocols, `IndexPath.item`. Fixtures
`uikit/collection/grid`, `horizontal`, `sized`, exact in `UIKitGoldenFrameTests` and within
0.2 % in `UIKitPixelTests`, from the iPhone SE simulator on iOS 26.

## API

- `UICollectionView`: `init(frame:collectionViewLayout:)`, `collectionViewLayout`,
  `dataSource`, `delegate`, `register(_:forCellWithReuseIdentifier:)`,
  `dequeueReusableCell(withReuseIdentifier:for:)`, `reloadData` (and the item and section
  reload, insert and delete calls, which reload), `performBatchUpdates`, `visibleCells`,
  `indexPathsForVisibleItems`, `cellForItem(at:)`, `indexPath(for:)`, `indexPathForItem(at:)`,
  `layoutAttributesForItem(at:)`, `numberOfSections`, `numberOfItems(inSection:)`,
  `allowsSelection`, `allowsMultipleSelection`, `indexPathsForSelectedItems`,
  `selectItem(at:animated:scrollPosition:)`, `deselectItem`, `scrollToItem`. A tap selects an
  item through `shouldSelectItemAt` / `didSelectItemAt`.
- `UICollectionViewFlowLayout`: `itemSize`, `minimumLineSpacing`, `minimumInteritemSpacing`,
  `scrollDirection`, `sectionInset` (`estimatedItemSize`, header and footer sizes accepted).
  `UICollectionViewDelegateFlowLayout`: `sizeForItemAt`, `insetForSectionAt`,
  `minimumLineSpacingForSectionAt`, `minimumInteritemSpacingForSectionAt`.
- `UICollectionViewLayout`: `prepare`, `collectionViewContentSize`,
  `layoutAttributesForElements(in:)`, `layoutAttributesForItem(at:)`, `invalidateLayout`; a
  custom layout subclass places items itself.
- `UICollectionViewCell`: `contentView`, `backgroundView`, `isSelected`, `isHighlighted`,
  `prepareForReuse`; `UICollectionReusableView.apply(_:)`.

## Measured (iOS 26, iPhone SE simulator)

- Lines fill greedily along the cross axis with the minimum interitem spacing; a line whose next
  item does not fit is full, and its items spread evenly over the free space (`sized`: 60 and
  100 wide in 300 sit at 10 and 210). A section's last line keeps the minimum spacing when the
  items differ in size (`sized`: 140, 60, 60 at 10, 160, 230).
- Items of one size sit on the grid a full line makes, however many there are: three 90 pt
  items in 288 leave gaps of 9, and the two items of the second section sit at 16 and 115 too
  (`grid`); a single item in a line sits at the leading inset.
- Lines follow each other at the minimum line spacing (60 pt items 8 apart: 16, 84, 152);
  sections add their bottom and top insets (the second section starts at 244).
- Horizontal flow lays columns along the width (120 pt items 12 apart at 20, 152, 284) inside
  the insets.
- Cells exist only for items whose frames meet the bounds (the fourth 120 pt item of a
  320 pt horizontal collection has none until it scrolls in); the reuse pool hands them back.

Open: supplementary views (section headers and footers), decoration views, compositional
layouts (`UICollectionViewCompositionalLayout`), `UICollectionViewListCell` and content
configurations, self-sizing cells (`estimatedItemSize`), item animations, drag reordering.

## Supplementary views (2026-09-11, `uikit/collection/headers`)

`register(_:forSupplementaryViewOfKind:withReuseIdentifier:)`,
`dequeueReusableSupplementaryView(ofKind:withReuseIdentifier:for:)`,
`supplementaryView(forElementKind:at:)`, the data source's
`viewForSupplementaryElementOfKind`, the flow layout's `headerReferenceSize` /
`footerReferenceSize` and the delegate's `referenceSizeForHeaderInSection` / `Footer`. A header
spans the cross axis before its section's inset and a footer follows the inset, each the
reference size's extent along the scroll direction (none when zero); views for the ones in
view are made and pooled like cells. `UICollectionReusableView` has no `init?(coder:)` (wasm
has no `NSCoder`), so fixture subclasses add their subviews on first layout.

## Self-sizing cells (2026-09-11, `uikit/collection/selfsizing`)

With `estimatedItemSize` set (`UICollectionViewFlowLayout.automaticSize` or an estimate) the flow
layout asks each item's cell for `preferredLayoutAttributesFitting(_:)`: by default the
`contentView`'s compressed fitting size from its constraints (a 15 pt label 12 in and 8 down
gives 59 × 34 for "Swift"), and the cell returns to the reuse pool. The delegate's
`sizeForItemAt` still wins. The sized items then follow the flow rules: full lines spread
their free space (49.5 and 49 pt gaps in the fixture's first line), a short last line keeps the
minimum spacing. Cells built for measurement add their subviews on first configure, as
`TagCell` does, so both UIKits see the same constraints.

## Diffable data sources and registrations (2026-09-11)

`Containers/DiffableDataSource.swift`. `NSDiffableDataSourceSnapshot` (sections and items:
append, insert before / after, delete, move, reload, reconfigure, lookups),
`UICollectionViewDiffableDataSource` (`init(collectionView:cellProvider:)`, `apply(_:animatingDifferences:completion:)`,
`applySnapshotUsingReloadData`, `snapshot()`, `itemIdentifier(for:)`, `indexPath(for:)`,
`sectionIdentifier(for:)`, `supplementaryViewProvider`), `UITableViewDiffableDataSource` (the
same over a table, `defaultRowAnimation` stored, `titleForHeaderInSection` overridable),
`UICollectionView.CellRegistration` / `SupplementaryRegistration` with
`dequeueConfiguredReusableCell(using:for:item:)` / `dequeueConfiguredReusableSupplementary(using:for:)`.
Applying a snapshot reloads the view to match; the differences are not animated (open), and the
completion runs on the next frame.

## Compositional layouts (2026-09-11, `uikit/collection/compositional`)

`Containers/CompositionalLayout.swift`. `UICollectionViewCompositionalLayout(section:)` /
`(sectionProvider:)` with `UICollectionViewCompositionalLayoutConfiguration` (`scrollDirection`,
`interSectionSpacing`), `NSCollectionLayoutSection` (`contentInsets`, `interGroupSpacing`,
`boundarySupplementaryItems`; `orthogonalScrollingBehavior` stored), `NSCollectionLayoutGroup`
(`horizontal` / `vertical` with `subitems` repeating to fill the group, or `repeatingSubitem:count:`,
nested groups, `interItemSpacing`, `contentInsets`), `NSCollectionLayoutItem` (`contentInsets`),
`NSCollectionLayoutSize` and `NSCollectionLayoutDimension` (`fractionalWidth`, `fractionalHeight`,
`absolute`, `estimated` taken as given), `NSCollectionLayoutSpacing` (`fixed`, `flexible`),
`NSCollectionLayoutBoundarySupplementaryItem` (top and bottom alignments), the environment's
`container.contentSize`. Measured: a group's subitems fill its axis by their own sizes, then a
fixed inter-item spacing comes out of the fractional items' share, on the pixel grid (three
1/3-width items 8 apart in 288 are 90.5 wide at 16, 114.5 and 213); rows follow one another
`interGroupSpacing` apart; a section's top boundary item spans its container above the
content insets. Pixels 0.4 % off the simulator. Open: orthogonal scrolling, pinned boundary
items, estimated (self-sizing) dimensions, item supplementary items, `list(using:)` and
`UICollectionViewListCell`.

## Lists (2026-09-11, `uikit/collection/list`)

`Containers/ListLayout.swift`. `UICollectionViewCompositionalLayout.list(using:)` with
`UICollectionLayoutListConfiguration` (`appearance` plain / grouped / insetGrouped / sidebar,
`showsSeparators`, `backgroundColor`, `headerMode` and `footerMode` stored, `headerTopPadding`)
and `UICollectionViewListCell` (`defaultContentConfiguration()` on the list's metrics,
`accessories` of `UICellAccessory`: disclosure indicator, checkmark, detail, label, and the
editing ones stored; `indentationLevel`). Measured (inset grouped): the collection's background
is the grouped ground, cards 16 in with 26 pt corners on a section's first and last rows, 35
above each section; a row with body text alone is 56 tall (the 24.5 pt label 16 down), one with
a subheadline secondary text 79.5 (labels at 15 and 43.5); the content view ends 30 before the
trailing edge for a disclosure (the 10.5 × 14 chevron 16 in) and 40 for a checkmark (19 × 18,
18.5 in); a 1 pt separator between rows runs 16 in from both card edges. Pixels 0.8 % off the
simulator. Open: plain appearance metrics, swipe actions, `UIListContentConfiguration`
in table cells on these metrics.

## List headers and footers (2026-09-11, `uikit/collection/listheaders`)

`headerMode` and `footerMode` of `.supplementary` on the list configuration ask the data source
for a header and footer view per section (`elementKindSectionHeader` / `elementKindSectionFooter`,
`UICollectionViewListCell` registered for the kind), each sized through its preferred layout
attributes like a row but without the 44 pt floor, and a list cell dequeued for a supplementary
kind answers `defaultContentConfiguration()` with `UIListContentConfiguration.groupedHeader()` or
`groupedFooter()` (the plain variants are the same) and draws no card. Measured (inset grouped):
the header replaces the 35 pt gap above its section, 44.5 tall with the headline label 16 in and
10 down; the rows follow at once; the footer is 35 tall with the footnote label in the secondary
colour 16 in and 8 down, laid out 21 tall although the label fits in 19; the next section's
header sits right under the footer. Pixels 1.6 % off the simulator. Open: `.firstItemInSection`,
`headerTopPadding` with supplementary headers, plain appearance headers.

## Orthogonal scrolling (2026-09-11, `uikit/collection/orthogonal`)

A section with `orthogonalScrollingBehavior` other than `none` lays its groups out sideways in a
scroll view of its own, inset by the section's content insets (a 288 × 100 scroll view at
(16, 16) for 200 × 100 groups 12 apart), its content as wide as the groups and the trailing
inset; the items' layout attributes stay in the collection's coordinates (the third group at
x 440), and only the cells inside the scroll view's visible width exist, as UIKit makes them.
Horizontal drags on the section scroll it (the paging behaviours snap to pages); vertical ones
scroll the list: a scroll view leaves pans mostly along an axis it cannot scroll to the
enclosing one. Pixels 1.3 % off the simulator. Open: `groupPagingCentered` centring,
`visibleItemsInvalidationHandler`, decoration items.
