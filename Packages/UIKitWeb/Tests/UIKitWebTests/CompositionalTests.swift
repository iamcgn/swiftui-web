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

/// Orthogonal sections: the cells live in a scroll view of their own that scrolls sideways under
/// a horizontal drag, makes the cells that come into view, and leaves vertical drags to the list.
@Suite @MainActor struct OrthogonalTests {
    final class Source: NSObject, UICollectionViewDataSource {
        func numberOfSections(in collectionView: UICollectionView) -> Int { 2 }
        func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { section == 0 ? 4 : 12 }
        func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
            collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath)
        }
    }

    @Test func carouselScrollsSidewaysAndTheListVertically() {
        let scene = UIKitScene.shared
        scene.removeAllWindows()
        scene.configureScreen(size: CGSize(width: 320, height: 400), scale: 2)
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
            return NSCollectionLayoutSection(group: group)
        }
        let collection = UICollectionView(frame: CGRect(x: 0, y: 0, width: 320, height: 400), collectionViewLayout: layout)
        collection.register(UICollectionViewCell.self, forCellWithReuseIdentifier: "cell")
        let source = Source()
        collection.dataSource = source
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 400))
        window.addSubview(collection)
        window.makeKeyAndVisible()
        scene.layout(in: CGSize(width: 320, height: 400))
        // Two carousel cells fit the 288 pt scroll view; the third waits past its edge.
        #expect(collection.cellForItem(at: IndexPath(item: 1, section: 0)) != nil)
        #expect(collection.cellForItem(at: IndexPath(item: 2, section: 0)) == nil)
        #expect(collection.cellForItem(at: IndexPath(item: 0, section: 0))?.convert(CGPoint.zero, to: nil) == CGPoint(x: 16, y: 16))
        #expect(collection.layoutAttributesForItem(at: IndexPath(item: 2, section: 0))?.frame == CGRect(x: 440, y: 16, width: 200, height: 100))
        // A drag to the left on the carousel scrolls it, not the list.
        scene.pointerDown(at: CGPoint(x: 250, y: 60), type: .touch, time: 0)
        scene.pointerMoved(to: CGPoint(x: 150, y: 60), time: 0.05)
        scene.pointerMoved(to: CGPoint(x: 50, y: 60), time: 0.1)
        scene.pointerUp(at: CGPoint(x: 50, y: 60), time: 0.15)
        scene.layout(in: CGSize(width: 320, height: 400))
        #expect(collection.contentOffset.y == 0)
        let third = collection.cellForItem(at: IndexPath(item: 2, section: 0))
        #expect(third != nil)
        #expect((third?.convert(CGPoint.zero, to: nil).x ?? 1000) < 320)
        for _ in 0..<60 where scene.isAnimating { _ = scene.advanceFrame(elapsed: 0.05) }
        // A vertical drag on the carousel scrolls the list.
        scene.pointerDown(at: CGPoint(x: 100, y: 100), type: .touch, time: 1)
        scene.pointerMoved(to: CGPoint(x: 100, y: 60), time: 1.05)
        scene.pointerMoved(to: CGPoint(x: 100, y: 20), time: 1.1)
        scene.pointerUp(at: CGPoint(x: 100, y: 20), time: 1.15)
        scene.layout(in: CGSize(width: 320, height: 400))
        #expect(collection.contentOffset.y > 0)
    }
}
