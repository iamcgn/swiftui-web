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
