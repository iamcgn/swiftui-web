// Diffable data sources (Containers/DiffableDataSource.swift): snapshots edit sections and
// items, applying one reloads the view to match, and cell registrations configure cells by item.
import Testing
import UIKit

@Suite @MainActor struct DiffableTests {
    enum Section: Hashable, Sendable { case main, more }

    @Test func snapshotsEditSectionsAndItems() {
        var snapshot = NSDiffableDataSourceSnapshot<Section, String>()
        snapshot.appendSections([.main, .more])
        snapshot.appendItems(["a", "b", "c"], toSection: .main)
        snapshot.appendItems(["x"])   // the last section
        #expect(snapshot.numberOfSections == 2)
        #expect(snapshot.numberOfItems == 4)
        #expect(snapshot.itemIdentifiers(inSection: .more) == ["x"])
        snapshot.insertItems(["a2"], afterItem: "a")
        snapshot.moveItem("c", beforeItem: "a")
        #expect(snapshot.itemIdentifiers(inSection: .main) == ["c", "a", "a2", "b"])
        snapshot.appendItems(["b"], toSection: .more)   // moves out of main
        #expect(snapshot.itemIdentifiers(inSection: .main) == ["c", "a", "a2"])
        #expect(snapshot.sectionIdentifier(containingItem: "b") == .more)
        #expect(snapshot.indexOfItem("x") == 3)
        snapshot.deleteItems(["a2"])
        snapshot.deleteSections([.more])
        #expect(snapshot.itemIdentifiers == ["c", "a"])
        snapshot.reloadItems(["a"])
        #expect(snapshot.reloadedItemIdentifiers == ["a"])
        snapshot.deleteAllItems()
        #expect(snapshot.numberOfSections == 0)
    }

    @Test func collectionDataSourceAppliesSnapshotsThroughRegistrations() {
        let scene = UIKitScene.shared
        scene.removeAllWindows()
        scene.configureScreen(size: CGSize(width: 320, height: 300), scale: 2)
        let layout = UICollectionViewFlowLayout()
        layout.itemSize = CGSize(width: 90, height: 40)
        let collection = UICollectionView(frame: CGRect(x: 0, y: 0, width: 320, height: 300), collectionViewLayout: layout)
        var configured: [String] = []
        let registration = UICollectionView.CellRegistration<UICollectionViewCell, String> { cell, _, item in
            configured.append(item)
            cell.contentView.backgroundColor = item == "a" ? .systemRed : .systemBlue
        }
        let source = UICollectionViewDiffableDataSource<Section, String>(collectionView: collection) { collection, path, item in
            collection.dequeueConfiguredReusableCell(using: registration, for: path, item: item)
        }
        var snapshot = NSDiffableDataSourceSnapshot<Section, String>()
        snapshot.appendSections([.main])
        snapshot.appendItems(["a", "b", "c"])
        source.apply(snapshot, animatingDifferences: false)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 300))
        window.addSubview(collection)
        window.makeKeyAndVisible()
        scene.layout(in: CGSize(width: 320, height: 300))
        #expect(collection.visibleCells.count == 3)
        #expect(configured == ["a", "b", "c"])
        #expect(source.itemIdentifier(for: IndexPath(item: 1, section: 0)) == "b")
        #expect(source.indexPath(for: "c") == IndexPath(item: 2, section: 0))
        #expect(collection.cellForItem(at: IndexPath(item: 0, section: 0))?.contentView.backgroundColor == .systemRed)
        var next = source.snapshot()
        next.deleteItems(["b"])
        next.appendItems(["d"])
        var completed = false
        source.apply(next) { completed = true }
        scene.layout(in: CGSize(width: 320, height: 300))
        // The animated apply completes with its 0.3 s animation (BatchUpdateTests).
        _ = scene.advanceFrame(elapsed: 0.05)
        #expect(!completed)
        _ = scene.advanceFrame(elapsed: 0.3)
        #expect(completed)
        #expect(collection.visibleCells.count == 3)
        #expect(source.itemIdentifier(for: IndexPath(item: 1, section: 0)) == "c")
        #expect(source.indexPath(for: "d") == IndexPath(item: 2, section: 0))
    }

    @Test func tableDataSourceAppliesSnapshots() {
        let scene = UIKitScene.shared
        scene.removeAllWindows()
        scene.configureScreen(size: CGSize(width: 320, height: 300), scale: 2)
        let table = UITableView(frame: CGRect(x: 0, y: 0, width: 320, height: 300), style: .plain)
        let source = UITableViewDiffableDataSource<Section, Int>(tableView: table) { table, _, item in
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            cell.textLabel?.text = "Row \(item)"
            return cell
        }
        var snapshot = NSDiffableDataSourceSnapshot<Section, Int>()
        snapshot.appendSections([.main, .more])
        snapshot.appendItems([1, 2], toSection: .main)
        snapshot.appendItems([3], toSection: .more)
        source.apply(snapshot)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 300))
        window.addSubview(table)
        window.makeKeyAndVisible()
        scene.layout(in: CGSize(width: 320, height: 300))
        #expect(table.numberOfSections == 2)
        #expect(table.numberOfRows(inSection: 0) == 2)
        #expect(table.cellForRow(at: IndexPath(row: 0, section: 1))?.textLabel?.text == "Row 3")
        #expect(source.sectionIdentifier(for: 1) == .more)
    }
}
