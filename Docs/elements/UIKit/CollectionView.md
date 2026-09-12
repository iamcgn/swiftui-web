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
Applying a snapshot with `animatingDifferences` (2026-09-11) keeps the cells of the items both
snapshots hold and slides them to their new places over 0.3 s while removed items' cells fade
out and added items' cells fade in; reloaded, reconfigured and reloaded-section items get fresh
cells at once, and the completion runs when the animation ends. Without animation, or before the
view's first layout, the view reloads to match and the completion runs on the next frame. The
same animation serves `performBatchUpdates` with `insertItems` / `deleteItems` / `reloadItems` /
`moveItem` and the section calls (`Containers/BatchUpdates.swift`; the mapping rules are in
`Docs/elements/UIKit/TableView.md`). Open: the diffable data source's per-item move detection
when an item also changes section, `UICollectionViewLayout` animation hooks
(`initialLayoutAttributesForAppearingItem` and friends).

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
content insets. Pixels 0.4 % off the simulator. Open: estimated (self-sizing) dimensions, item
supplementary items.

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
simulator. Open: swipe actions, `UIListContentConfiguration` in table cells on these metrics.

## Plain lists (2026-09-11, `uikit/collection/plainlist`)

The plain appearance: full-width 56 pt rows on the system background with separators 16 in
from both edges under every row, the last of a section included; a supplementary header sits
22 below what precedes it (the first at 22), 44.5 tall with the same headline content as a
grouped one, and pins to the visible top while its section scrolls under it until the next
section's header pushes it away (the pinned header paints the ground under itself, a 16 pt
fade below, and the pocket's scrim: black at 15 % at its top easing to nothing 60 pt down, as
the plain table's pinned header does; UIKit blurs the rows passing under). Rows are measured
only as they appear: a row out of view is laid out at the estimate (56; headers 44.5, footers
35) and, when its cell appears with another height, the layout runs again with the measured
value (the fixture's rows below the fold have no cells, as on the simulator; a data source's
cell provider runs only for rows in view). Frames exact with a scroll step, pixels 1.9 % off
the simulator at worst. Open: the sidebar appearances, `headerTopPadding`, plain footers,
`UIListContentConfiguration.plainHeader()` (the grouped header for now).

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
header sits right under the footer. Pixels 1.6 % off the simulator. Open: `headerTopPadding`
with supplementary headers, plain appearance headers.

## First-item headers (2026-09-11, `uikit/collection/firstitem`)

`headerMode == .firstItemInSection` makes each section's first cell its header: the collection
view marks a list cell dequeued for item 0 so its `defaultContentConfiguration()` is the grouped
header, it draws no card and has no 44 pt floor, and the card starts at item 1. Measured: the
header is 44.5 tall at the section's top (no gap above the first section), the rows follow at
once, and 17.5 separates a section's last row from the next header. Pixels 1.2 % off the
simulator.

## Outlines (2026-09-11, `uikit/collection/outline`)

`NSDiffableDataSourceSectionSnapshot` (`append(_:to:)`, `insert(_:before:/after:)`, `delete`,
`deleteAll`, `expand` / `collapse`, `isExpanded`, `isVisible`, `contains`, `level(of:)`,
`parent(of:)`, `index(of:)`, `items`, `rootItems`, `visibleItems`, `snapshot(of:includingParent:)`)
and `UICollectionViewDiffableDataSource.apply(_:to:animatingDifferences:completion:)` /
`snapshot(for:)` / `sectionSnapshotHandlers` (should / will expand and collapse,
`snapshotForExpandingParent`). Applying an outline to a section shows its visible items
(children only under expanded parents) through the animated diff; the data source sets each
list cell's `indentationLevel` from the item's level and its disclosure open or closed; a tap
on a cell with `.outlineDisclosure()` expands or collapses the item instead of selecting it.
Measured (inset grouped): a child's content view starts 10 in for one level (the label with
it) and its separator with its content (42 in the card rather than 32); rows stay 56 in the
card, and an expanded parent's chevron points down. The fixture's steps collapse and expand
parents; only the roots are probed since a removed child's cell keeps reporting a stale
frame. Pixels 0.8 % off the simulator. Open: the sidebar appearance's outline (its header-style
parents), `UICellAccessory.OutlineDisclosureOptions` (`style`, `isHidden`), reordering
outline items, per-item expansion animation (the rows fade and slide as any batch update).

## Orthogonal scrolling (2026-09-11, `uikit/collection/orthogonal`)

A section with `orthogonalScrollingBehavior` other than `none` lays its groups out sideways in a
scroll view of its own, inset by the section's content insets (a 288 × 100 scroll view at
(16, 16) for 200 × 100 groups 12 apart), its content as wide as the groups and the trailing
inset; the items' layout attributes stay in the collection's coordinates (the third group at
x 440), and only the cells inside the scroll view's visible width exist, as UIKit makes them.
Horizontal drags on the section scroll it (the paging behaviours snap to pages); vertical ones
scroll the list: a scroll view leaves pans mostly along an axis it cannot scroll to the
enclosing one. Pixels 1.3 % off the simulator. Open: `groupPagingCentered` centring,
`visibleItemsInvalidationHandler`.

## Decoration items (2026-09-11, `uikit/collection/decoration`)

`NSCollectionLayoutDecorationItem.background(elementKind:)` (`contentInsets`, `zIndex`) in a
section's `decorationItems`, the view class registered on the layout with
`register(_:forDecorationViewOfKind:)`; the collection view makes the view itself (no data
source call), applies the attributes (`indexPath.section` says which section) and hosts it
behind the cells. Measured: a background spans its section from where the section starts to
where it ends, boundary items and content insets included (128 tall for two 44 pt rows 8 apart
in 16 pt insets), and its own content insets shrink it (8 sideways gives 304 wide at 8). Pixels
0.1 % off the simulator. Open: decorations in orthogonal sections.

## Pinned headers (2026-09-11, `uikit/collection/pinned`)

A top boundary item with `pinToVisibleBounds` holds at the visible top (the content offset plus
the adjusted top inset) while its section scrolls under it, until the next section's start
pushes it away; the collection view re-applies a pinned header's attributes on every layout and
keeps it above the cells. Measured on two scroll steps: at offset 100 the first header sits at 0
in the view and the second at its natural 334 (234 in view); at 320 the second header is pinned
at 14 and the first, pushed to 304, shows at -16 under the last row: iOS 26 draws a pushed
header beneath the content (a scroll pocket blurs the band, which UIKitWeb does not paint), so
its attributes carry a negative z-index and the view drops below the cells. Pixels 1.6 % off the
simulator at worst. Open: pinned footers, the scroll pocket blur.
