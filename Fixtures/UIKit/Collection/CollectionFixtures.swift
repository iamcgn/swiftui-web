// UICollectionView with a flow layout (Docs/elements/UIKit/CollectionView.md): a grid of fixed
// items with section insets and spacing, a horizontal row, and items sized by the delegate,
// measured against UIKit on the simulator.
#if canImport(UIKit)
import UIKit
import UIKitFixtureKit

class GridSource: NSObject, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
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

    /// Declared on the class so a subclass's override is the protocol witness (a method added
    /// only in the subclass would lose to the protocol extension's default in Swift).
    func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> UICollectionReusableView {
        collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: "header", for: indexPath)
    }
}

/// A section header or footer: a label 16 in, vertically centred.
final class SectionHeaderView: UICollectionReusableView {
    let label = UILabel()   // added on first layout: no initializer to mirror on both UIKits
    override func layoutSubviews() {
        super.layoutSubviews()
        if label.superview == nil { addSubview(label) }
        label.sizeToFit()
        label.frame.origin = CGPoint(x: 16, y: ((bounds.height - label.frame.height) / 2).rounded())
    }
}

/// A grid source that also supplies headers and footers.
final class HeaderSource: GridSource {
    var headerProbes: [Int: String] = [:]
    var footerProbes: [Int: String] = [:]
    override func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> UICollectionReusableView {
        let view = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: "header", for: indexPath) as! SectionHeaderView
        let isHeader = kind == UICollectionView.elementKindSectionHeader
        view.label.text = isHeader ? "Section \(indexPath.section + 1)" : "\(counts[indexPath.section]) items"
        view.label.font = isHeader ? .systemFont(ofSize: 17, weight: .semibold) : .systemFont(ofSize: 13)
        view.label.textColor = isHeader ? .label : .secondaryLabel
        view.backgroundColor = isHeader ? .systemGray6 : .clear
        if let probe = isHeader ? headerProbes[indexPath.section] : footerProbes[indexPath.section] { view.probe(probe) }
        return view
    }
}

/// A cell whose size comes from its label's constraints (12 sideways, 8 above and below).
final class TagCell: UICollectionViewCell {
    let label = UILabel()   // constrained on first layout: no initializer to mirror on both UIKits
    private var constrained = false
    func configure(_ text: String) {
        label.text = text
        label.font = .systemFont(ofSize: 15)
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
        contentView.backgroundColor = .systemGray5
        contentView.layer.cornerRadius = 8
    }
}

/// A source of tag cells sized by their content.
final class TagSource: NSObject, UICollectionViewDataSource {
    let tags = ["Swift", "SwiftUI", "UIKit", "Auto Layout", "Compositional", "Web"]
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { tags.count }
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "tag", for: indexPath) as! TagCell
        cell.configure(tags[indexPath.item])
        return cell.probe("item\(indexPath.item)")
    }
}

/// Two sections of list cells: a plain text row, a subtitle row, a value-style row, a row with a checkmark.
final class ListSource: NSObject, UICollectionViewDataSource {
    let rows: [[(text: String, secondary: String?, accessory: Int)]] = [
        [("Wi-Fi", nil, 1), ("Bluetooth", "On", 1)],
        [("General", nil, 1), ("Sounds", "Silent", 0)],
    ]
    func numberOfSections(in collectionView: UICollectionView) -> Int { rows.count }
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { rows[section].count }
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "list", for: indexPath) as! UICollectionViewListCell
        let row = rows[indexPath.section][indexPath.item]
        var content = cell.defaultContentConfiguration()
        content.text = row.text
        content.secondaryText = row.secondary
        cell.contentConfiguration = content
        cell.accessories = row.accessory == 1 ? [.disclosureIndicator()] : [.checkmark()]
        return cell.probe("item\(indexPath.section * 2 + indexPath.item)")
    }
}

/// Two sections with header cells ("General", "Display") and a footer under the first.
final class ListHeaderSource: NSObject, UICollectionViewDataSource {
    let rows = [["Wi-Fi", "Bluetooth"], ["Brightness"]]
    func numberOfSections(in collectionView: UICollectionView) -> Int { rows.count }
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { rows[section].count }
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "list", for: indexPath) as! UICollectionViewListCell
        var content = cell.defaultContentConfiguration()
        content.text = rows[indexPath.section][indexPath.item]
        cell.contentConfiguration = content
        return cell.probe("row\(indexPath.section)\(indexPath.item)")
    }
    func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> UICollectionReusableView {
        let isHeader = kind == UICollectionView.elementKindSectionHeader
        let cell = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: isHeader ? "header" : "footer", for: indexPath) as! UICollectionViewListCell
        var content = cell.defaultContentConfiguration()
        content.text = isHeader ? (indexPath.section == 0 ? "General" : "Display") : "A footer note about the section."
        cell.contentConfiguration = content
        return cell.probe(isHeader ? "header\(indexPath.section)" : "footer\(indexPath.section)")
    }
}


/// Two sections whose first items are their headers (`headerMode == .firstItemInSection`).
final class FirstItemSource: NSObject, UICollectionViewDataSource {
    let rows = [["General", "Wi-Fi", "Bluetooth"], ["Display", "Brightness"]]
    func numberOfSections(in collectionView: UICollectionView) -> Int { rows.count }
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { rows[section].count }
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "list", for: indexPath) as! UICollectionViewListCell
        var content = cell.defaultContentConfiguration()
        content.text = rows[indexPath.section][indexPath.item]
        cell.contentConfiguration = content
        return cell.probe("row\(indexPath.section)\(indexPath.item)")
    }
}

/// A section background decoration: a grey rounded card behind the section.
final class SectionBackgroundView: UICollectionReusableView {
    override func apply(_ layoutAttributes: UICollectionViewLayoutAttributes) {
        super.apply(layoutAttributes)
        backgroundColor = .systemGray5
        layer.cornerRadius = 12
        probe("background\(layoutAttributes.indexPath.section)")
    }
}

/// The collection view a behaviour fixture scrolls between renders.
@MainActor public final class CollectionModel {
    var collection: UICollectionView?
    public init() {}
}


/// The outline's data source: parents with an outline disclosure over their children.
@MainActor final class OutlineModel {
    var collection: UICollectionView?
    var source: UICollectionViewDiffableDataSource<Int, String>?
    static let children: [String: [String]] = ["Fruit": ["Apple", "Pear"], "Vegetables": ["Carrot", "Leek"]]
    static let roots = ["Fruit", "Vegetables", "Other"]

    func sectionSnapshot(expanded: [String]) -> NSDiffableDataSourceSectionSnapshot<String> {
        var snapshot = NSDiffableDataSourceSectionSnapshot<String>()
        snapshot.append(Self.roots)
        for (parent, children) in Self.children.sorted(by: { $0.key < $1.key }) { snapshot.append(children, to: parent) }
        snapshot.expand(expanded)
        return snapshot
    }
}

public enum CollectionFixtures {
    public static let all = [grid, horizontal, sized, headers, selfSizing, compositional, list, orthogonal, listHeaders, firstItem, decoration, pinned, outline]

    @MainActor static var sources: [GridSource] = []

    @MainActor static func make(layout: UICollectionViewLayout, source: GridSource, frame: CGRect = CGRect(x: 0, y: 0, width: 320, height: 400)) -> UIView {
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

    /// Self-sizing cells: the flow layout's automatic estimated size lets each cell take its
    /// constraints' fitting size (a 15 pt label 12 in and 8 down), wrapping into lines.
    @MainActor static var tagSources: [TagSource] = []
    public static let selfSizing = UIKitFixture("uikit/collection/selfsizing", size: CGSize(width: 320, height: 200)) {
        let root = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 200))
        let layout = UICollectionViewFlowLayout()
        layout.estimatedItemSize = UICollectionViewFlowLayout.automaticSize
        layout.minimumInteritemSpacing = 8
        layout.minimumLineSpacing = 8
        layout.sectionInset = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        let collection = UICollectionView(frame: CGRect(x: 0, y: 0, width: 320, height: 200), collectionViewLayout: layout)
        collection.register(TagCell.self, forCellWithReuseIdentifier: "tag")
        let source = TagSource()
        tagSources.append(source)
        collection.dataSource = source
        collection.backgroundColor = .systemBackground
        root.addSubview(collection.probe("collection"))
        return root
    }

    /// A compositional layout: a section of full-width 44 pt rows 8 apart with a 30 pt header,
    /// then a three-column grid of 60 pt cells 8 apart inside 16 pt content insets.
    public static let compositional = UIKitFixture("uikit/collection/compositional", size: CGSize(width: 320, height: 400)) {
        let layout = UICollectionViewCompositionalLayout { section, _ in
            if section == 0 {
                let item = NSCollectionLayoutItem(layoutSize: NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .absolute(44)))
                let group = NSCollectionLayoutGroup.horizontal(layoutSize: NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .absolute(44)), subitems: [item])
                let section = NSCollectionLayoutSection(group: group)
                section.interGroupSpacing = 8
                let header = NSCollectionLayoutBoundarySupplementaryItem(layoutSize: NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .absolute(30)), elementKind: UICollectionView.elementKindSectionHeader, alignment: .top)
                section.boundarySupplementaryItems = [header]
                return section
            }
            let item = NSCollectionLayoutItem(layoutSize: NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0 / 3.0), heightDimension: .absolute(60)))
            let group = NSCollectionLayoutGroup.horizontal(layoutSize: NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .absolute(60)), subitems: [item])
            group.interItemSpacing = .fixed(8)
            let section = NSCollectionLayoutSection(group: group)
            section.interGroupSpacing = 8
            section.contentInsets = NSDirectionalEdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)
            return section
        }
        let source = HeaderSource()
        source.counts = [2, 5]
        source.probes = [IndexPath(item: 0, section: 0): "item0", IndexPath(item: 1, section: 0): "item1", IndexPath(item: 0, section: 1): "item2", IndexPath(item: 2, section: 1): "item4", IndexPath(item: 3, section: 1): "item5"]
        source.headerProbes = [0: "header0"]
        let root = make(layout: layout, source: source)
        let collection = root.subviews.first { $0 is UICollectionView } as! UICollectionView
        collection.register(SectionHeaderView.self, forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader, withReuseIdentifier: "header")
        return root
    }

    /// A list layout in the inset grouped appearance: list cells with text, secondary text and
    /// a disclosure accessory in two sections.
    public static let list = UIKitFixture("uikit/collection/list", size: CGSize(width: 320, height: 400)) {
        var configuration = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
        configuration.headerMode = .none
        let layout = UICollectionViewCompositionalLayout.list(using: configuration)
        let source = ListSource()
        listSources.append(source)
        let root = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 400))
        let collection = UICollectionView(frame: root.bounds, collectionViewLayout: layout)
        collection.register(UICollectionViewListCell.self, forCellWithReuseIdentifier: "list")
        collection.dataSource = source
        root.addSubview(collection.probe("collection"))
        return root
    }

    @MainActor static var listSources: [ListSource] = []

    /// A list with supplementary headers and a footer made from list cells' default header and
    /// footer content configurations.
    public static let listHeaders = UIKitFixture("uikit/collection/listheaders", size: CGSize(width: 320, height: 400)) {
        var configuration = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
        configuration.headerMode = .supplementary
        configuration.footerMode = .supplementary
        let layout = UICollectionViewCompositionalLayout.list(using: configuration)
        let source = ListHeaderSource()
        listHeaderSources.append(source)
        let root = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 400))
        let collection = UICollectionView(frame: root.bounds, collectionViewLayout: layout)
        collection.register(UICollectionViewListCell.self, forCellWithReuseIdentifier: "list")
        collection.register(UICollectionViewListCell.self, forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader, withReuseIdentifier: "header")
        collection.register(UICollectionViewListCell.self, forSupplementaryViewOfKind: UICollectionView.elementKindSectionFooter, withReuseIdentifier: "footer")
        collection.dataSource = source
        root.addSubview(collection.probe("collection"))
        return root
    }

    @MainActor static var listHeaderSources: [ListHeaderSource] = []

    /// A list whose first item in each section is its header (`headerMode == .firstItemInSection`).
    public static let firstItem = UIKitFixture("uikit/collection/firstitem", size: CGSize(width: 320, height: 400)) {
        var configuration = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
        configuration.headerMode = .firstItemInSection
        let layout = UICollectionViewCompositionalLayout.list(using: configuration)
        let source = FirstItemSource()
        firstItemSources.append(source)
        let root = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 400))
        let collection = UICollectionView(frame: root.bounds, collectionViewLayout: layout)
        collection.register(UICollectionViewListCell.self, forCellWithReuseIdentifier: "list")
        collection.dataSource = source
        root.addSubview(collection.probe("collection"))
        return root
    }

    @MainActor static var firstItemSources: [FirstItemSource] = []

    /// Section background decoration items: full-width 44 pt rows 8 apart in 16 pt insets, the
    /// second section's background inset 8 sideways.
    public static let decoration = UIKitFixture("uikit/collection/decoration", size: CGSize(width: 320, height: 400)) {
        let layout = UICollectionViewCompositionalLayout { section, _ in
            let item = NSCollectionLayoutItem(layoutSize: NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .absolute(44)))
            let group = NSCollectionLayoutGroup.horizontal(layoutSize: NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .absolute(44)), subitems: [item])
            let layoutSection = NSCollectionLayoutSection(group: group)
            layoutSection.interGroupSpacing = 8
            layoutSection.contentInsets = NSDirectionalEdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)
            let background = NSCollectionLayoutDecorationItem.background(elementKind: "background")
            if section == 1 { background.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8) }
            layoutSection.decorationItems = [background]
            return layoutSection
        }
        layout.register(SectionBackgroundView.self, forDecorationViewOfKind: "background")
        let source = GridSource()
        source.counts = [2, 3]
        source.probes = [IndexPath(item: 0, section: 0): "item0", IndexPath(item: 1, section: 0): "item1", IndexPath(item: 0, section: 1): "item2", IndexPath(item: 2, section: 1): "item4"]
        return make(layout: layout, source: source)
    }

    /// Boundary headers pinned to the visible bounds: each stays at the top while its section
    /// scrolls under it and the next section's header pushes it away.
    public static let pinned = UIKitFixture("uikit/collection/pinned", size: CGSize(width: 320, height: 300),
                                            model: { CollectionModel() },
                                            steps: [UIKitFixtureStep("scroll") { model in
                                                        model.collection?.contentOffset = CGPoint(x: 0, y: 100)
                                                        model.collection?.layoutIfNeeded()
                                                    },
                                                    UIKitFixtureStep("push") { model in
                                                        model.collection?.contentOffset = CGPoint(x: 0, y: 320)
                                                        model.collection?.layoutIfNeeded()
                                                    }]) { model in
        let layout = UICollectionViewCompositionalLayout { _, _ in
            let item = NSCollectionLayoutItem(layoutSize: NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .absolute(44)))
            let group = NSCollectionLayoutGroup.horizontal(layoutSize: NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .absolute(44)), subitems: [item])
            let section = NSCollectionLayoutSection(group: group)
            section.interGroupSpacing = 8
            let header = NSCollectionLayoutBoundarySupplementaryItem(layoutSize: NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .absolute(30)), elementKind: UICollectionView.elementKindSectionHeader, alignment: .top)
            header.pinToVisibleBounds = true
            section.boundarySupplementaryItems = [header]
            return section
        }
        let source = HeaderSource()
        source.counts = [6, 6]
        source.probes = [IndexPath(item: 5, section: 0): "item5", IndexPath(item: 0, section: 1): "item6"]   // no probe on a row that scrolls away: UIKitWeb recycles its cell, UIKit keeps it
        source.headerProbes = [0: "header0", 1: "header1"]
        let root = make(layout: layout, source: source, frame: CGRect(x: 0, y: 0, width: 320, height: 300))
        let collection = root.subviews.first { $0 is UICollectionView } as! UICollectionView
        collection.register(SectionHeaderView.self, forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader, withReuseIdentifier: "header")
        model.collection = collection
        return root
    }

    /// An orthogonally scrolling section (a carousel of 200 × 100 groups 12 apart, inset 16)
    /// above a plain vertical section of full-width rows.
    public static let orthogonal = UIKitFixture("uikit/collection/orthogonal", size: CGSize(width: 320, height: 400)) {
        let layout = UICollectionViewCompositionalLayout { section, _ in
            if section == 0 {
                let item = NSCollectionLayoutItem(layoutSize: NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .fractionalHeight(1)))
                let group = NSCollectionLayoutGroup.horizontal(layoutSize: NSCollectionLayoutSize(widthDimension: .absolute(200), heightDimension: .absolute(100)), subitems: [item])
                let section = NSCollectionLayoutSection(group: group)
                section.orthogonalScrollingBehavior = .continuous
                section.interGroupSpacing = 12
                section.contentInsets = NSDirectionalEdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)
                return section
            }
            let item = NSCollectionLayoutItem(layoutSize: NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .absolute(44)))
            let group = NSCollectionLayoutGroup.horizontal(layoutSize: NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .absolute(44)), subitems: [item])
            let section = NSCollectionLayoutSection(group: group)
            section.interGroupSpacing = 8
            return section
        }
        let source = GridSource()
        source.counts = [4, 2]
        source.probes = [IndexPath(item: 0, section: 0): "item0", IndexPath(item: 1, section: 0): "item1", IndexPath(item: 2, section: 0): "item2", IndexPath(item: 0, section: 1): "item4", IndexPath(item: 1, section: 1): "item5"]
        return make(layout: layout, source: source)
    }

    /// Section headers (44 tall) and footers (30 tall) from the flow layout's reference sizes.
    public static let headers = UIKitFixture("uikit/collection/headers", size: CGSize(width: 320, height: 400)) {
        let layout = UICollectionViewFlowLayout()
        layout.itemSize = CGSize(width: 90, height: 60)
        layout.minimumInteritemSpacing = 9
        layout.minimumLineSpacing = 12
        layout.sectionInset = UIEdgeInsets(top: 12, left: 16, bottom: 12, right: 16)
        layout.headerReferenceSize = CGSize(width: 0, height: 44)
        layout.footerReferenceSize = CGSize(width: 0, height: 30)
        let source = HeaderSource()
        source.counts = [3, 2]
        source.probes = [IndexPath(item: 0, section: 0): "item0", IndexPath(item: 0, section: 1): "item3"]
        source.headerProbes = [0: "header0", 1: "header1"]
        source.footerProbes = [0: "footer0", 1: "footer1"]
        let root = make(layout: layout, source: source)
        let collection = root.subviews.first { $0 is UICollectionView } as! UICollectionView
        collection.register(SectionHeaderView.self, forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader, withReuseIdentifier: "header")
        collection.register(SectionHeaderView.self, forSupplementaryViewOfKind: UICollectionView.elementKindSectionFooter, withReuseIdentifier: "header")
        return root
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

    /// An outline in a list: parents with an outline disclosure, children under an expanded
    /// parent; the steps collapse the first parent and expand the second.
    public static let outline = UIKitFixture("uikit/collection/outline", size: CGSize(width: 320, height: 400),
                                             model: { OutlineModel() },
                                             steps: [UIKitFixtureStep("collapse") { model in
                                                         model.source?.apply(model.sectionSnapshot(expanded: []), to: 0, animatingDifferences: false)
                                                         model.collection?.layoutIfNeeded()
                                                     },
                                                     UIKitFixtureStep("expand") { model in
                                                         model.source?.apply(model.sectionSnapshot(expanded: ["Vegetables"]), to: 0, animatingDifferences: false)
                                                         model.collection?.layoutIfNeeded()
                                                     }]) { model in
        var configuration = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
        configuration.headerMode = .none
        let layout = UICollectionViewCompositionalLayout.list(using: configuration)
        let root = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 400))
        let collection = UICollectionView(frame: root.bounds, collectionViewLayout: layout)
        let registration = UICollectionView.CellRegistration<UICollectionViewListCell, String> { cell, _, item in
            var content = cell.defaultContentConfiguration()
            content.text = item
            cell.contentConfiguration = content
            cell.accessories = OutlineModel.children[item] != nil ? [.outlineDisclosure()] : []
            // Only the roots are probed: they stay on show through the steps (a removed child's
            // cell would keep reporting a stale frame, or its reused cell another item's).
            if OutlineModel.roots.contains(item) { cell.probe("item-\(item)") }
        }
        let source = UICollectionViewDiffableDataSource<Int, String>(collectionView: collection) { collection, path, item in
            collection.dequeueConfiguredReusableCell(using: registration, for: path, item: item)
        }
        var sections = NSDiffableDataSourceSnapshot<Int, String>()
        sections.appendSections([0])
        source.apply(sections, animatingDifferences: false)
        source.apply(model.sectionSnapshot(expanded: ["Fruit"]), to: 0, animatingDifferences: false)
        model.collection = collection
        model.source = source
        root.addSubview(collection.probe("collection"))
        return root
    }
}
#endif
