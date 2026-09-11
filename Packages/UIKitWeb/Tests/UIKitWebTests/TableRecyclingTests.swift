// UITableView recycling (Containers/UITableView.swift): with a known row height only the rows in
// view (and a page around them) have cells; scrolling brings others in and returns the rest to
// the reuse pool, which dequeueReusableCell hands back.
import Testing
import UIKit

@Suite @MainActor struct TableRecyclingTests {
    final class Source: NSObject, UITableViewDataSource {
        var made = 0
        var dequeued = 0
        func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { 1000 }
        func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
            let cell: UITableViewCell
            if let reused = tableView.dequeueReusableCell(withIdentifier: "row") {
                cell = reused
                dequeued += 1
            } else {
                cell = UITableViewCell(style: .default, reuseIdentifier: "row")
                made += 1
            }
            cell.textLabel?.text = "Row \(indexPath.row)"
            return cell
        }
    }

    @Test func onlyTheRowsInViewHaveCells() {
        let scene = UIKitScene.shared
        scene.removeAllWindows()
        scene.configureScreen(size: CGSize(width: 320, height: 400), scale: 2)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 400))
        let table = UITableView(frame: window.bounds, style: .plain)
        table.rowHeight = 44
        let source = Source()
        table.dataSource = source
        window.addSubview(table)
        window.makeKeyAndVisible()
        scene.layout(in: CGSize(width: 320, height: 400))
        #expect(table.contentSize.height == 44_000)
        #expect(table.visibleCells.count < 30, "\(table.visibleCells.count)")
        #expect(source.made < 30)
        #expect(abs(table.rectForRow(at: IndexPath(row: 999, section: 0)).minY - 43956) < 0.001)
        // Scrolling far down shows those rows, made from recycled cells.
        table.contentOffset = CGPoint(x: 0, y: 500 * 44)
        scene.layout(in: CGSize(width: 320, height: 400))
        let paths = table.indexPathsForVisibleRows ?? []
        #expect(paths.contains(IndexPath(row: 502, section: 0)))
        #expect(!paths.contains(IndexPath(row: 0, section: 0)))
        #expect(source.dequeued > 0)
        #expect(source.made < 40, "\(source.made)")
        #expect(table.cellForRow(at: IndexPath(row: 502, section: 0))?.textLabel?.text == "Row 502")
    }
}

/// Collection view headers and footers: laid out from the reference sizes, dequeued and pooled.
@Suite @MainActor struct CollectionSupplementaryTests {
    final class Source: NSObject, UICollectionViewDataSource {
        var made = 0
        func numberOfSections(in collectionView: UICollectionView) -> Int { 3 }
        func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { 2 }
        func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
            collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath)
        }
        func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> UICollectionReusableView {
            made += 1
            return collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: "header", for: indexPath)
        }
    }

    @Test func headersAndFootersFrameTheSections() {
        let scene = UIKitScene.shared
        scene.removeAllWindows()
        scene.configureScreen(size: CGSize(width: 320, height: 200), scale: 2)
        let layout = UICollectionViewFlowLayout()
        layout.itemSize = CGSize(width: 90, height: 60)
        layout.sectionInset = UIEdgeInsets(top: 12, left: 16, bottom: 12, right: 16)
        layout.headerReferenceSize = CGSize(width: 0, height: 44)
        layout.footerReferenceSize = CGSize(width: 0, height: 30)
        let collection = UICollectionView(frame: CGRect(x: 0, y: 0, width: 320, height: 200), collectionViewLayout: layout)
        collection.register(UICollectionViewCell.self, forCellWithReuseIdentifier: "cell")
        collection.register(UICollectionReusableView.self, forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader, withReuseIdentifier: "header")
        collection.register(UICollectionReusableView.self, forSupplementaryViewOfKind: UICollectionView.elementKindSectionFooter, withReuseIdentifier: "header")
        let source = Source()
        collection.dataSource = source
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 200))
        window.addSubview(collection)
        window.makeKeyAndVisible()
        scene.layout(in: CGSize(width: 320, height: 200))
        // A section is 44 + 12 + 60 + 12 + 30 = 158 tall; the content holds three.
        #expect(collection.contentSize.height == 474)
        let header0 = collection.supplementaryView(forElementKind: UICollectionView.elementKindSectionHeader, at: IndexPath(item: 0, section: 0))
        #expect(header0?.frame == CGRect(x: 0, y: 0, width: 320, height: 44))
        #expect(collection.cellForItem(at: IndexPath(item: 0, section: 0))?.frame == CGRect(x: 16, y: 56, width: 90, height: 60))
        let footer0 = collection.supplementaryView(forElementKind: UICollectionView.elementKindSectionFooter, at: IndexPath(item: 0, section: 0))
        #expect(footer0?.frame == CGRect(x: 0, y: 128, width: 320, height: 30))
        #expect(collection.supplementaryView(forElementKind: UICollectionView.elementKindSectionHeader, at: IndexPath(item: 0, section: 1))?.frame.minY == 158)
        // Only the views in the 200 pt window exist: two headers, one footer.
        #expect(source.made == 3)
        #expect(collection.supplementaryView(forElementKind: UICollectionView.elementKindSectionHeader, at: IndexPath(item: 0, section: 2)) == nil)
        // Scrolling to the end pools the first section's views and makes the last section's.
        collection.contentOffset = CGPoint(x: 0, y: 274)
        scene.layout(in: CGSize(width: 320, height: 200))
        #expect(collection.supplementaryView(forElementKind: UICollectionView.elementKindSectionHeader, at: IndexPath(item: 0, section: 0)) == nil)
        #expect(collection.supplementaryView(forElementKind: UICollectionView.elementKindSectionFooter, at: IndexPath(item: 0, section: 2))?.frame.maxY == 474)
    }
}
