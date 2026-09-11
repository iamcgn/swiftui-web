// UICollectionViewCompositionalLayout (Containers/CompositionalLayout.swift): repeating
// subitems, nested groups, vertical groups and section spacing resolve to frames.
import Testing
import UIKit

@Suite @MainActor struct CompositionalTests {
    final class Source: NSObject, UICollectionViewDataSource {
        var counts = [4]
        func numberOfSections(in collectionView: UICollectionView) -> Int { counts.count }
        func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { counts[section] }
        func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
            collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath)
        }
    }

    private func layoutFrames(_ layout: UICollectionViewLayout, counts: [Int]) -> (UICollectionView, [IndexPath: CGRect]) {
        let scene = UIKitScene.shared
        scene.removeAllWindows()
        scene.configureScreen(size: CGSize(width: 320, height: 400), scale: 2)
        let collection = UICollectionView(frame: CGRect(x: 0, y: 0, width: 320, height: 400), collectionViewLayout: layout)
        collection.register(UICollectionViewCell.self, forCellWithReuseIdentifier: "cell")
        let source = Source()
        source.counts = counts
        collection.dataSource = source
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 400))
        window.addSubview(collection)
        window.makeKeyAndVisible()
        scene.layout(in: CGSize(width: 320, height: 400))
        var result: [IndexPath: CGRect] = [:]
        for (section, count) in counts.enumerated() {
            for item in 0..<count {
                let path = IndexPath(item: item, section: section)
                if let frame = collection.layoutAttributesForItem(at: path)?.frame { result[path] = frame }
            }
        }
        withExtendedLifetime(source) {}
        return (collection, result)
    }

    @Test func repeatingSubitemsAndNestedGroups() {
        // Two 1/2-width items per row, 50 tall, rows 10 apart.
        let item = NSCollectionLayoutItem(layoutSize: NSCollectionLayoutSize(widthDimension: .fractionalWidth(0.5), heightDimension: .fractionalHeight(1)))
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .absolute(50)), repeatingSubitem: item, count: 2)
        let section = NSCollectionLayoutSection(group: group)
        section.interGroupSpacing = 10
        let (collection, frames) = layoutFrames(UICollectionViewCompositionalLayout(section: section), counts: [3])
        #expect(frames[IndexPath(item: 0, section: 0)] == CGRect(x: 0, y: 0, width: 160, height: 50))
        #expect(frames[IndexPath(item: 1, section: 0)] == CGRect(x: 160, y: 0, width: 160, height: 50))
        #expect(frames[IndexPath(item: 2, section: 0)] == CGRect(x: 0, y: 60, width: 160, height: 50))
        #expect(collection.contentSize.height == 110)

        // A leading full-height item next to a vertical group of two half-height items.
        let big = NSCollectionLayoutItem(layoutSize: NSCollectionLayoutSize(widthDimension: .fractionalWidth(0.5), heightDimension: .fractionalHeight(1)))
        let small = NSCollectionLayoutItem(layoutSize: NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .fractionalHeight(0.5)))
        let column = NSCollectionLayoutGroup.vertical(layoutSize: NSCollectionLayoutSize(widthDimension: .fractionalWidth(0.5), heightDimension: .fractionalHeight(1)), subitems: [small])
        let row = NSCollectionLayoutGroup.horizontal(layoutSize: NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .absolute(100)), subitems: [big, column])
        let nested = NSCollectionLayoutSection(group: row)
        nested.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20)
        let (_, nestedFrames) = layoutFrames(UICollectionViewCompositionalLayout(section: nested), counts: [3])
        #expect(nestedFrames[IndexPath(item: 0, section: 0)] == CGRect(x: 20, y: 0, width: 140, height: 100))
        #expect(nestedFrames[IndexPath(item: 1, section: 0)] == CGRect(x: 160, y: 0, width: 140, height: 50))
        #expect(nestedFrames[IndexPath(item: 2, section: 0)] == CGRect(x: 160, y: 50, width: 140, height: 50))
    }

    @Test func sectionsSpaceAndProvidersChoose() {
        let configuration = UICollectionViewCompositionalLayoutConfiguration()
        configuration.interSectionSpacing = 24
        let layout = UICollectionViewCompositionalLayout(sectionProvider: { section, environment in
            let height: CGFloat = section == 0 ? 40 : 30
            let item = NSCollectionLayoutItem(layoutSize: NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .absolute(height)))
            let group = NSCollectionLayoutGroup.horizontal(layoutSize: NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .absolute(height)), subitems: [item])
            #expect(environment.container.contentSize.width == 320)
            return NSCollectionLayoutSection(group: group)
        }, configuration: configuration)
        let (collection, frames) = layoutFrames(layout, counts: [1, 2])
        #expect(frames[IndexPath(item: 0, section: 0)] == CGRect(x: 0, y: 0, width: 320, height: 40))
        #expect(frames[IndexPath(item: 0, section: 1)] == CGRect(x: 0, y: 64, width: 320, height: 30))
        #expect(frames[IndexPath(item: 1, section: 1)] == CGRect(x: 0, y: 94, width: 320, height: 30))
        #expect(collection.contentSize.height == 124)
    }
}
