// Batch updates (Containers/BatchUpdates.swift): the rows kept across an update map to their
// new places; an animated diffable apply or performBatchUpdates keeps the surviving cells and
// slides them, fades removed cells out and new ones in, and runs the completion at the end.
import Testing
import UIKit
@testable import UIKitWebCore

@Suite @MainActor struct BatchUpdateTests {
    @Test func mappingSkipsDeletesAndInserts() {
        var update = BatchUpdateMapping(oldCounts: [4, 2])
        update.deletedItems = [IndexPath(item: 1, section: 0)]
        update.insertedItems = [IndexPath(item: 0, section: 0)]
        update.deletedSections = [1]
        update.reloadedItems = [IndexPath(item: 3, section: 0)]
        let result = update.retained()
        // Row 0 moves to 1 (an insert at 0), row 1 is gone, rows 2 and 3 become 2 and 3; section 1 is gone.
        #expect(result.mapping[IndexPath(item: 0, section: 0)] == IndexPath(item: 1, section: 0))
        #expect(result.mapping[IndexPath(item: 1, section: 0)] == nil)
        #expect(result.mapping[IndexPath(item: 2, section: 0)] == IndexPath(item: 2, section: 0))
        #expect(result.mapping[IndexPath(item: 3, section: 0)] == IndexPath(item: 3, section: 0))
        #expect(result.mapping[IndexPath(item: 0, section: 1)] == nil)
        #expect(result.reloaded == [IndexPath(item: 3, section: 0)])
    }

    @Test func mappingFollowsMovesAndInsertedSections() {
        var update = BatchUpdateMapping(oldCounts: [3])
        update.moves = [IndexPath(item: 0, section: 0): IndexPath(item: 2, section: 0)]
        update.insertedSections = [0]
        let result = update.retained()
        // The old section is now section 1; row 0 moved to 2, rows 1 and 2 close up to 0 and 1.
        #expect(result.mapping[IndexPath(item: 0, section: 0)] == IndexPath(item: 2, section: 0))
        #expect(result.mapping[IndexPath(item: 1, section: 0)] == IndexPath(item: 0, section: 1))
        #expect(result.mapping[IndexPath(item: 2, section: 0)] == IndexPath(item: 1, section: 1))
    }

    private func window() -> UIWindow {
        UIKitScene.shared.removeAllWindows()
        UIKitScene.shared.configureScreen(size: CGSize(width: 320, height: 400), scale: 2)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 400))
        window.makeKeyAndVisible()
        return window
    }

    @Test func diffableApplyKeepsCellsAndAnimates() {
        let window = window()
        let layout = UICollectionViewFlowLayout()
        layout.itemSize = CGSize(width: 320, height: 40)
        layout.minimumLineSpacing = 0
        let collection = UICollectionView(frame: window.bounds, collectionViewLayout: layout)
        collection.register(UICollectionViewCell.self, forCellWithReuseIdentifier: "cell")
        window.addSubview(collection)
        let source = UICollectionViewDiffableDataSource<Int, String>(collectionView: collection) { collection, path, _ in
            let cell = collection.dequeueReusableCell(withReuseIdentifier: "cell", for: path)
            cell.contentView.backgroundColor = UIColor(red: 1, green: 0, blue: 0, alpha: 1)
            return cell
        }
        var snapshot = NSDiffableDataSourceSnapshot<Int, String>()
        snapshot.appendSections([0])
        snapshot.appendItems(["a", "b", "c"])
        source.apply(snapshot, animatingDifferences: false)
        UIKitScene.shared.layout(in: window.bounds.size)
        let cellB = collection.cellForItem(at: IndexPath(item: 1, section: 0))
        let cellA = collection.cellForItem(at: IndexPath(item: 0, section: 0))
        #expect(cellB != nil && cellA != nil)

        var next = NSDiffableDataSourceSnapshot<Int, String>()
        next.appendSections([0])
        next.appendItems(["b", "c", "d"])
        var completed = false
        source.apply(next, animatingDifferences: true) { completed = true }
        // "b" keeps its cell, now at item 0 and sliding up from 40; "a" fades; "d" fades in.
        #expect(collection.cellForItem(at: IndexPath(item: 0, section: 0)) === cellB)
        #expect(cellB?.frame.minY == 0)
        #expect(UIKitScene.shared.isAnimating)
        #expect(cellA?.superview === collection)
        #expect(cellA?.alpha == 0)
        let cellD = collection.cellForItem(at: IndexPath(item: 2, section: 0))
        #expect(cellD != nil && cellD !== cellA)
        #expect(cellD?.alpha == 1)
        // Mid way, painting shows the kept cells between their frames (a red row starting
        // strictly between 0 and 40) and no row settled at 0 yet.
        _ = UIKitScene.shared.advanceFrame(elapsed: 0.15)
        #expect(!completed)
        UIKitScene.shared.layout(in: window.bounds.size)
        let fills = UIKitScene.shared.render(scale: 2, background: false).commands.map(\.description).filter { $0.hasPrefix("fillRect") && $0.contains("#FF0000") }
        func top(_ fill: String) -> Double? {
            let inside = fill.dropFirst("fillRect(".count).split(separator: ")").first ?? ""
            let parts = inside.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            return parts.count >= 2 ? parts[1] : nil
        }
        let tops = fills.compactMap(top)
        #expect(tops.contains { $0 > 0 && $0 < 40 }, "\(fills)")
        _ = UIKitScene.shared.advanceFrame(elapsed: 0.2)
        #expect(completed)
        #expect(cellA?.superview == nil)
        #expect(collection.visibleCells.count == 3)
    }

    @Test func tableBatchUpdatesSlideRows() {
        final class Source: NSObject, UITableViewDataSource {
            var rows = ["one", "two", "three"]
            func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { rows.count }
            func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
                let cell = tableView.dequeueReusableCell(withIdentifier: "cell") ?? UITableViewCell(style: .default, reuseIdentifier: "cell")
                cell.textLabel?.text = rows[indexPath.row]
                return cell
            }
        }
        let window = window()
        let table = UITableView(frame: window.bounds, style: .plain)
        table.rowHeight = 44
        let source = Source()
        table.dataSource = source
        window.addSubview(table)
        UIKitScene.shared.layout(in: window.bounds.size)
        let second = table.cellForRow(at: IndexPath(row: 1, section: 0))
        let first = table.cellForRow(at: IndexPath(row: 0, section: 0))
        #expect(second != nil && first != nil)
        var done = false
        table.performBatchUpdates({
            source.rows = ["two", "three", "four"]
            table.deleteRows(at: [IndexPath(row: 0, section: 0)], with: .fade)
            table.insertRows(at: [IndexPath(row: 2, section: 0)], with: .fade)
        }, completion: { _ in done = true })
        #expect(table.cellForRow(at: IndexPath(row: 0, section: 0)) === second)
        #expect(second?.frame.minY == 0)
        #expect(first?.alpha == 0 && first?.superview === table)
        #expect(UIKitScene.shared.isAnimating)
        _ = UIKitScene.shared.advanceFrame(elapsed: 0.4)
        #expect(done)
        #expect(first?.superview == nil)
        #expect(table.cellForRow(at: IndexPath(row: 2, section: 0))?.textLabel?.text == "four")
    }
}
