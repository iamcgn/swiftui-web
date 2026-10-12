// uk-collection-rest (Containers/CompositionalLayout.swift, UICollectionView.swift,
// DiffableDataSource.swift): estimated items, anchored supplementary items, pinned footers,
// group paging and the invalidation handler, interactive movement, the layout's animation
// hooks, reordering handlers and outline disclosure options.
import Testing
@testable import UIKitWebCore
import UIKit

@Suite @MainActor struct CollectionRestTests {
    /// A cell whose height follows a wrapping 15 pt label (12 sideways, 8 above and below).
    final class NoteCell: UICollectionViewCell {
        let label = UILabel()
        private var constrained = false
        func configure(_ text: String) {
            label.text = text
            label.font = .systemFont(ofSize: 15)
            label.numberOfLines = 0
            guard !constrained else { return }
            constrained = true
            label.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
                label.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
                label.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
                label.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),
            ])
        }
    }

    final class Source: NSObject, UICollectionViewDataSource {
        var counts = [4]
        var notes: [String] = []
        var canMove = true
        var moves: [(IndexPath, IndexPath)] = []
        func numberOfSections(in collectionView: UICollectionView) -> Int { counts.count }
        func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { counts[section] }
        func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
            if !notes.isEmpty, indexPath.section == 0 {
                let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "note", for: indexPath) as! NoteCell
                cell.configure(notes[indexPath.item])
                return cell
            }
            return collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath)
        }
        func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> UICollectionReusableView {
            collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: "extra", for: indexPath)
        }
        func collectionView(_ collectionView: UICollectionView, canMoveItemAt indexPath: IndexPath) -> Bool { canMove }
        func collectionView(_ collectionView: UICollectionView, moveItemAt sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath) { moves.append((sourceIndexPath, destinationIndexPath)) }
    }

    private func host(_ layout: UICollectionViewLayout, source: Source, height: CGFloat = 400) -> UICollectionView {
        let scene = UIKitScene.shared
        scene.removeAllWindows()
        scene.configureScreen(size: CGSize(width: 320, height: height), scale: 2)
        let collection = UICollectionView(frame: CGRect(x: 0, y: 0, width: 320, height: height), collectionViewLayout: layout)
        collection.register(UICollectionViewCell.self, forCellWithReuseIdentifier: "cell")
        collection.register(NoteCell.self, forCellWithReuseIdentifier: "note")
        collection.register(UICollectionReusableView.self, forSupplementaryViewOfKind: "badge", withReuseIdentifier: "extra")
        collection.register(UICollectionReusableView.self, forSupplementaryViewOfKind: UICollectionView.elementKindSectionFooter, withReuseIdentifier: "extra")
        collection.dataSource = source
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: height))
        window.addSubview(collection)
        window.makeKeyAndVisible()
        scene.layout(in: CGSize(width: 320, height: height))
        return collection
    }

    private func fullWidthSection(height: NSCollectionLayoutDimension, spacing: CGFloat = 8) -> NSCollectionLayoutSection {
        let item = NSCollectionLayoutItem(layoutSize: NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: height))
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: height), subitems: [item])
        let section = NSCollectionLayoutSection(group: group)
        section.interGroupSpacing = spacing
        return section
    }

    @Test func estimatedItemsMeasureTheirCells() throws {
        UIKitScene.shared.textEngine = try Goldens.textEngine()
        let source = Source()
        source.counts = [2]
        source.notes = ["A short note.", "A longer note that runs past the width of the collection view and wraps onto a second line."]
        let section = fullWidthSection(height: .estimated(44))
        section.contentInsets = NSDirectionalEdgeInsets(top: 16, leading: 16, bottom: 8, trailing: 16)
        let collection = host(UICollectionViewCompositionalLayout(section: section), source: source)
        // One line is 34 (18 + 16), three lines 70 (uikit/collection/rest).
        #expect(collection.layoutAttributesForItem(at: IndexPath(item: 0, section: 0))?.frame == CGRect(x: 16, y: 16, width: 288, height: 34))
        #expect(collection.layoutAttributesForItem(at: IndexPath(item: 1, section: 0))?.frame == CGRect(x: 16, y: 58, width: 288, height: 70))
        #expect(collection.contentSize.height == 136)
        withExtendedLifetime(source) {}
    }

    @Test func anchoredSupplementaryItemsAndPinnedFooters() {
        let source = Source()
        source.counts = [3, 6]
        let layout = UICollectionViewCompositionalLayout { section, _ in
            if section == 0 {
                // A 20 pt badge past the top trailing corner by 0.3 of itself (uikit/collection/rest).
                let anchor = NSCollectionLayoutAnchor(edges: [.top, .trailing], fractionalOffset: CGPoint(x: 0.3, y: -0.3))
                let badge = NSCollectionLayoutSupplementaryItem(layoutSize: NSCollectionLayoutSize(widthDimension: .absolute(20), heightDimension: .absolute(20)), elementKind: "badge", containerAnchor: anchor)
                let item = NSCollectionLayoutItem(layoutSize: NSCollectionLayoutSize(widthDimension: .absolute(90), heightDimension: .absolute(90)), supplementaryItems: [badge])
                let group = NSCollectionLayoutGroup.horizontal(layoutSize: NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .absolute(90)), subitems: [item])
                group.interItemSpacing = .fixed(9)
                let layoutSection = NSCollectionLayoutSection(group: group)
                layoutSection.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 16, bottom: 8, trailing: 16)
                return layoutSection
            }
            let item = NSCollectionLayoutItem(layoutSize: NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .absolute(44)))
            let group = NSCollectionLayoutGroup.horizontal(layoutSize: NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .absolute(44)), subitems: [item])
            let layoutSection = NSCollectionLayoutSection(group: group)
            layoutSection.interGroupSpacing = 8
            layoutSection.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 16, bottom: 0, trailing: 16)
            let footer = NSCollectionLayoutBoundarySupplementaryItem(layoutSize: NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .absolute(30)), elementKind: UICollectionView.elementKindSectionFooter, alignment: .bottom)
            footer.pinToVisibleBounds = true
            layoutSection.boundarySupplementaryItems = [footer]
            return layoutSection
        }
        let collection = host(layout, source: source)
        let badge = collection.layoutAttributesForItem(at: IndexPath(item: 1, section: 0))
        #expect(badge?.frame == CGRect(x: 115, y: 12, width: 90, height: 90))
        #expect(collection.collectionViewLayout.layoutAttributesForSupplementaryView(ofKind: "badge", at: IndexPath(item: 1, section: 0))?.frame == CGRect(x: 191, y: 6, width: 20, height: 20))
        #expect(collection.supplementaryView(forElementKind: "badge", at: IndexPath(item: 2, section: 0))?.frame == CGRect(x: 290, y: 6, width: 20, height: 20))
        // The item anchor puts a corner of the badge on the item's: bottom leading at top trailing.
        let outside = NSCollectionLayoutSupplementaryItem(layoutSize: NSCollectionLayoutSize(widthDimension: .absolute(20), heightDimension: .absolute(20)), elementKind: "x",
                                                          containerAnchor: NSCollectionLayoutAnchor(edges: [.top, .trailing]), itemAnchor: NSCollectionLayoutAnchor(edges: [.bottom, .leading]))
        #expect(outside.frame(on: CGRect(x: 0, y: 100, width: 90, height: 90)) == CGRect(x: 90, y: 80, width: 20, height: 20))
        // The footer: 6 rows from 118 end at 422 where the footer belongs; it pins to the
        // visible bottom (370) until the end scrolls into view.
        let footerPath = IndexPath(item: 0, section: 1)
        let kind = UICollectionView.elementKindSectionFooter
        #expect(collection.layoutAttributesForSupplementaryElement(ofKind: kind, at: footerPath)?.frame.minY == 370)
        #expect(collection.supplementaryView(forElementKind: kind, at: footerPath)?.frame.minY == 370)
        collection.contentOffset = CGPoint(x: 0, y: 52)
        UIKitScene.shared.layout(in: CGSize(width: 320, height: 400))
        #expect(collection.supplementaryView(forElementKind: kind, at: footerPath)?.frame.minY == 422)
        #expect(collection.contentSize.height == 452)
        withExtendedLifetime(source) {}
    }

    @Test func groupPagingCentresAndSnaps() {
        let source = Source()
        source.counts = [4]
        var handled: [(IndexPath, CGFloat)] = []
        let layout = UICollectionViewCompositionalLayout { _, _ in
            let item = NSCollectionLayoutItem(layoutSize: NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .fractionalHeight(1)))
            let group = NSCollectionLayoutGroup.horizontal(layoutSize: NSCollectionLayoutSize(widthDimension: .absolute(240), heightDimension: .absolute(120)), subitems: [item])
            let section = NSCollectionLayoutSection(group: group)
            section.orthogonalScrollingBehavior = .groupPagingCentered
            section.interGroupSpacing = 12
            section.contentInsets = NSDirectionalEdgeInsets(top: 16, leading: 0, bottom: 16, trailing: 0)
            section.visibleItemsInvalidationHandler = { items, offset, environment in
                let centre = environment.container.contentSize.width / 2
                for item in items {
                    let distance = abs(item.frame.midX - offset.x - centre)
                    let scale = max(0.85, 1 - distance / 800)
                    item.transform = CGAffineTransform(scaleX: scale, y: scale)
                    handled.append((item.indexPath, scale))
                }
            }
            return section
        }
        let collection = host(layout, source: source, height: 300)
        let carousel = try! #require(collection.subviews.first { $0 is UIScrollView } as? UIScrollView)
        // The first group centred: the carousel starts 40 before its content (uikit/collection/paging).
        #expect(carousel.contentOffset.x == -40)
        let first = try! #require(collection.cellForItem(at: IndexPath(item: 0, section: 0)))
        let second = try! #require(collection.cellForItem(at: IndexPath(item: 1, section: 0)))
        #expect(first.frame == CGRect(x: 0, y: 0, width: 240, height: 120) && first.transform == .identity)
        #expect(second.transform.a == 0.85 && second.frame == CGRect(x: 270, y: 9, width: 204, height: 102), "\(second.frame)")
        #expect(handled.contains { $0.0 == IndexPath(item: 1, section: 0) && $0.1 == 0.85 })
        // A short flick snaps to the next group, centred: 252 - 40.
        let scene = UIKitScene.shared
        scene.pointerDown(at: CGPoint(x: 200, y: 80), type: .touch, time: 0)
        scene.pointerMoved(to: CGPoint(x: 150, y: 80), time: 0.05)
        scene.pointerMoved(to: CGPoint(x: 100, y: 80), time: 0.1)
        scene.pointerUp(at: CGPoint(x: 100, y: 80), time: 0.12)
        _ = scene.advanceFrame(elapsed: 1)
        #expect(carousel.contentOffset.x == 212, "\(carousel.contentOffset)")
        scene.layout(in: CGSize(width: 320, height: 300))
        #expect(second.transform == .identity && first.transform.a == 0.85)
        withExtendedLifetime(source) {}
    }

    @Test func interactiveMovementShiftsNeighboursAndTellsTheDataSource() {
        let source = Source()
        source.counts = [4]
        let layout = UICollectionViewCompositionalLayout(section: fullWidthSection(height: .absolute(44)))
        let collection = host(layout, source: source)
        let moving = try! #require(collection.cellForItem(at: IndexPath(item: 0, section: 0)))
        let third = try! #require(collection.cellForItem(at: IndexPath(item: 2, section: 0)))
        #expect(collection.beginInteractiveMovementForItem(at: IndexPath(item: 0, section: 0)))
        #expect(collection.hasActiveDrag && collection.subviews.last === moving)
        // Dragged over the third item: the first and second shift up, the dragged cell follows the finger.
        collection.updateInteractiveMovementTargetPosition(CGPoint(x: 160, y: 126))
        _ = UIKitScene.shared.advanceFrame(elapsed: 0.5)
        #expect(moving.center == CGPoint(x: 160, y: 126))
        #expect(third.frame.minY == 52, "\(third.frame)")
        #expect(collection.indexPath(for: moving) == IndexPath(item: 2, section: 0))
        collection.endInteractiveMovement()
        #expect(source.moves.count == 1 && source.moves[0].0 == IndexPath(item: 0, section: 0) && source.moves[0].1 == IndexPath(item: 2, section: 0))
        #expect(!collection.hasActiveDrag)
        // A data source that refuses: nothing lifts.
        source.canMove = false
        UIKitScene.shared.layout(in: CGSize(width: 320, height: 400))
        #expect(!collection.beginInteractiveMovementForItem(at: IndexPath(item: 1, section: 0)))
        withExtendedLifetime(source) {}
    }

    /// A layout whose inserted items drop in from above and deleted ones shrink away.
    final class HookedLayout: UICollectionViewCompositionalLayout {
        var updates: [UICollectionViewUpdateItem] = []
        var finalized = 0
        override func prepare(forCollectionViewUpdates updateItems: [UICollectionViewUpdateItem]) { updates = updateItems }
        override func finalizeCollectionViewUpdates() { finalized += 1 }
        override func initialLayoutAttributesForAppearingItem(at itemIndexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
            guard let attributes = layoutAttributesForItem(at: itemIndexPath)?.copy() else { return nil }
            attributes.frame.origin.y -= 100
            attributes.alpha = 0.5
            return attributes
        }
        override func finalLayoutAttributesForDisappearingItem(at itemIndexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
            let attributes = UICollectionViewLayoutAttributes(forCellWith: itemIndexPath)
            attributes.frame = CGRect(x: 160, y: 22, width: 0, height: 0)
            attributes.transform = CGAffineTransform(scaleX: 0.1, y: 0.1)
            return attributes
        }
    }

    @Test func layoutAnimationHooks() {
        let source = Source()
        source.counts = [3]
        let layout = HookedLayout(section: fullWidthSection(height: .absolute(44)))
        let collection = host(layout, source: source)
        let first = try! #require(collection.cellForItem(at: IndexPath(item: 0, section: 0)))
        collection.performBatchUpdates {
            source.counts = [3]
            collection.deleteItems(at: [IndexPath(item: 0, section: 0)])
            collection.insertItems(at: [IndexPath(item: 2, section: 0)])
        }
        #expect(layout.updates.count == 3, "a delete and two moves: \(layout.updates.map(\.updateAction))")
        #expect(layout.updates.contains { $0.updateAction == .delete && $0.indexPathBeforeUpdate == IndexPath(item: 0, section: 0) })
        #expect(layout.finalized == 1)
        let inserted = try! #require(collection.cellForItem(at: IndexPath(item: 2, section: 0)))
        // Presented at the start: the inserted cell 100 above its place at half alpha, the
        // deleted one still there and shrinking.
        let startCentre = inserted.layer.presented(.position, model: .point(inserted.layer.position)).point
        #expect(startCentre.y == 26, "\(startCentre)")
        #expect(first.superview === collection)
        _ = UIKitScene.shared.advanceFrame(elapsed: 0.5)
        #expect(inserted.frame.minY == 104 && inserted.alpha == 1)
        #expect(first.superview == nil && first.transform == .identity)
        withExtendedLifetime(source) {}
    }

    @Test func diffableReorderingAndCrossSectionMoves() {
        let scene = UIKitScene.shared
        scene.removeAllWindows()
        scene.configureScreen(size: CGSize(width: 320, height: 400), scale: 2)
        let layout = UICollectionViewCompositionalLayout(section: fullWidthSection(height: .absolute(44)))
        let collection = UICollectionView(frame: CGRect(x: 0, y: 0, width: 320, height: 400), collectionViewLayout: layout)
        let registration = UICollectionView.CellRegistration<UICollectionViewCell, String> { _, _, _ in }
        let source = UICollectionViewDiffableDataSource<Int, String>(collectionView: collection) { collection, path, item in
            collection.dequeueConfiguredReusableCell(using: registration, for: path, item: item)
        }
        var snapshot = NSDiffableDataSourceSnapshot<Int, String>()
        snapshot.appendSections([0, 1])
        snapshot.appendItems(["a", "b", "c"], toSection: 0)
        snapshot.appendItems(["d"], toSection: 1)
        source.apply(snapshot, animatingDifferences: false)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 400))
        window.addSubview(collection)
        window.makeKeyAndVisible()
        scene.layout(in: CGSize(width: 320, height: 400))
        // Without handlers nothing moves; with them the drop rewrites the snapshot.
        #expect(!collection.beginInteractiveMovementForItem(at: IndexPath(item: 0, section: 0)))
        var transactions: [String] = []
        source.reorderingHandlers.canReorderItem = { $0 != "c" }
        source.reorderingHandlers.willReorder = { transactions.append("will " + $0.finalSnapshot.itemIdentifiers.joined()) }
        source.reorderingHandlers.didReorder = { transactions.append("did " + $0.difference.count.description) }
        #expect(!collection.beginInteractiveMovementForItem(at: IndexPath(item: 2, section: 0)))
        #expect(collection.beginInteractiveMovementForItem(at: IndexPath(item: 0, section: 0)))
        collection.updateInteractiveMovementTargetPosition(CGPoint(x: 160, y: 74))
        collection.endInteractiveMovement()
        #expect(source.snapshot().itemIdentifiers(inSection: 0) == ["b", "a", "c"])
        #expect(transactions == ["will bacd", "did 2"], "\(transactions)")
        // An item that changes section keeps its cell and slides to its new place.
        scene.layout(in: CGSize(width: 320, height: 400))
        let cell = try! #require(collection.cellForItem(at: IndexPath(item: 2, section: 0)))
        var moved = source.snapshot()
        moved.deleteItems(["c"])
        moved.appendItems(["c"], toSection: 1)
        source.apply(moved, animatingDifferences: true)
        #expect(collection.cellForItem(at: IndexPath(item: 1, section: 1)) === cell)
        _ = scene.advanceFrame(elapsed: 0.5)
        // Two rows in the first section (96), then "d" and "c": 96 + 52.
        #expect(cell.frame.minY == 148, "\(cell.frame)")
        withExtendedLifetime(source) {}
    }

    @Test func outlineDisclosureOptions() {
        let scene = UIKitScene.shared
        scene.removeAllWindows()
        scene.configureScreen(size: CGSize(width: 320, height: 400), scale: 2)
        scene.textEngine = try! Goldens.textEngine()
        var configuration = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
        configuration.headerMode = .none
        let collection = UICollectionView(frame: CGRect(x: 0, y: 0, width: 320, height: 400), collectionViewLayout: UICollectionViewCompositionalLayout.list(using: configuration))
        @MainActor final class Counter { var toggled = 0 }
        let counter = Counter()
        let registration = UICollectionView.CellRegistration<UICollectionViewListCell, String> { cell, _, item in
            var content = cell.defaultContentConfiguration()
            content.text = item
            cell.contentConfiguration = content
            switch item {
            case "Fruit": cell.accessories = [.outlineDisclosure(options: .init(style: .cell), actionHandler: { MainActor.assumeIsolated { counter.toggled += 1 } })]
            case "Vegetables": cell.accessories = [.outlineDisclosure(options: .init(style: .header, isHidden: true))]
            default: cell.accessories = []
            }
        }
        final class Selections: NSObject, UICollectionViewDelegate {
            var selected: [IndexPath] = []
            func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) { selected.append(indexPath) }
        }
        let selections = Selections()
        collection.delegate = selections
        let source = UICollectionViewDiffableDataSource<Int, String>(collectionView: collection) { collection, path, item in
            collection.dequeueConfiguredReusableCell(using: registration, for: path, item: item)
        }
        var sections = NSDiffableDataSourceSnapshot<Int, String>()
        sections.appendSections([0])
        source.apply(sections, animatingDifferences: false)
        var outline = NSDiffableDataSourceSectionSnapshot<String>()
        outline.append(["Fruit", "Vegetables"])
        outline.append(["Apple"], to: "Fruit")
        outline.append(["Leek"], to: "Vegetables")
        source.apply(outline, to: 0, animatingDifferences: false)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 400))
        window.addSubview(collection)
        window.makeKeyAndVisible()
        scene.layout(in: CGSize(width: 320, height: 400))
        func tap(_ point: CGPoint, time: Double) {
            scene.pointerDown(at: point, type: .touch, time: time)
            scene.pointerUp(at: point, time: time + 0.05)
            _ = scene.advanceFrame(elapsed: 0.5)
            scene.layout(in: CGSize(width: 320, height: 400))
        }
        // Cell style: a tap on the text selects; one on the chevron expands.
        tap(CGPoint(x: 60, y: 35 + 28), time: 0)
        #expect(selections.selected == [IndexPath(item: 0, section: 0)] && source.snapshot(for: 0).isExpanded("Fruit") == false)
        tap(CGPoint(x: 290, y: 35 + 28), time: 1)
        #expect(source.snapshot(for: 0).isExpanded("Fruit") && counter.toggled == 1 && selections.selected.count == 1)
        #expect(source.snapshot().itemIdentifiers(inSection: 0) == ["Fruit", "Apple", "Vegetables"])
        // A hidden disclosure neither draws nor toggles by tap.
        let vegetables = try! #require(collection.cellForItem(at: IndexPath(item: 2, section: 0)) as? UICollectionViewListCell)
        tap(CGPoint(x: 290, y: vegetables.frame.midY), time: 2)
        #expect(!source.snapshot(for: 0).isExpanded("Vegetables") && selections.selected.count == 2)
        #expect(vegetables.contentView.frame.width == vegetables.bounds.width)
        withExtendedLifetime(source) {}
    }
}
