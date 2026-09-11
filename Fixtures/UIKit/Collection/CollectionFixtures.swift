// UICollectionView with a flow layout (Docs/elements/UIKit/CollectionView.md): a grid of fixed
// items with section insets and spacing, a horizontal row, and items sized by the delegate,
// measured against UIKit on the simulator.
#if canImport(UIKit)
import UIKit
import UIKitFixtureKit

final class GridSource: NSObject, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    var counts: [Int] = [7]
    var probes: [IndexPath: String] = [:]
    var sizes: ((IndexPath) -> CGSize)?
    var colors: [UIColor] = [.systemBlue, .systemGreen, .systemOrange, .systemPink, .systemPurple, .systemTeal, .systemIndigo]

    func numberOfSections(in collectionView: UICollectionView) -> Int { counts.count }
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { counts[section] }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath)
        cell.contentView.backgroundColor = colors[(indexPath.section * 3 + indexPath.item) % colors.count]
        cell.contentView.layer.cornerRadius = 8
        if let probe = probes[indexPath] { cell.probe(probe) }
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        sizes?(indexPath) ?? (collectionViewLayout as? UICollectionViewFlowLayout)?.itemSize ?? CGSize(width: 50, height: 50)
    }
}

public enum CollectionFixtures {
    public static let all = [grid, horizontal, sized]

    @MainActor static var sources: [GridSource] = []

    @MainActor static func make(layout: UICollectionViewFlowLayout, source: GridSource, frame: CGRect = CGRect(x: 0, y: 0, width: 320, height: 400)) -> UIView {
        let root = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 400))
        let collection = UICollectionView(frame: frame, collectionViewLayout: layout)
        collection.register(UICollectionViewCell.self, forCellWithReuseIdentifier: "cell")
        collection.dataSource = source
        collection.delegate = source
        collection.backgroundColor = .systemBackground
        root.addSubview(collection.probe("collection"))
        sources.append(source)
        return root
    }

    /// 90 × 60 items in 16 pt insets with 8 pt spacing: three per row in 320, wrapping.
    public static let grid = UIKitFixture("uikit/collection/grid", size: CGSize(width: 320, height: 400)) {
        let layout = UICollectionViewFlowLayout()
        layout.itemSize = CGSize(width: 90, height: 60)
        layout.minimumInteritemSpacing = 8
        layout.minimumLineSpacing = 8
        layout.sectionInset = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        let source = GridSource()
        source.counts = [7, 2]
        source.probes = [IndexPath(item: 0, section: 0): "item0", IndexPath(item: 2, section: 0): "item2", IndexPath(item: 3, section: 0): "item3",
                         IndexPath(item: 6, section: 0): "item6", IndexPath(item: 0, section: 1): "second0", IndexPath(item: 1, section: 1): "second1"]
        return make(layout: layout, source: source)
    }

    /// A horizontal flow: 120 × 80 items in one line, 12 apart, 20 pt insets.
    public static let horizontal = UIKitFixture("uikit/collection/horizontal", size: CGSize(width: 320, height: 400)) {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.itemSize = CGSize(width: 120, height: 80)
        layout.minimumLineSpacing = 12
        layout.sectionInset = UIEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        let source = GridSource()
        source.counts = [4]
        source.probes = [IndexPath(item: 0, section: 0): "item0", IndexPath(item: 1, section: 0): "item1", IndexPath(item: 3, section: 0): "item3"]
        return make(layout: layout, source: source, frame: CGRect(x: 0, y: 0, width: 320, height: 120))
    }

    /// Items sized by the delegate: widths 60, 100, 140, 60, 60; a row breaks where the next
    /// item does not fit.
    public static let sized = UIKitFixture("uikit/collection/sized", size: CGSize(width: 320, height: 400)) {
        let layout = UICollectionViewFlowLayout()
        layout.minimumInteritemSpacing = 10
        layout.minimumLineSpacing = 10
        layout.sectionInset = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        let source = GridSource()
        source.counts = [5]
        source.sizes = { path in CGSize(width: [60, 100, 140, 60, 60][path.item], height: 40) }
        source.probes = [IndexPath(item: 0, section: 0): "item0", IndexPath(item: 1, section: 0): "item1", IndexPath(item: 2, section: 0): "item2",
                         IndexPath(item: 3, section: 0): "item3", IndexPath(item: 4, section: 0): "item4"]
        return make(layout: layout, source: source)
    }
}
#endif
