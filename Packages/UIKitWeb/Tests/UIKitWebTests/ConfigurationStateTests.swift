// Cell configuration state (Containers/ContentConfiguration.swift, ios/representable/hostingstate):
// a cell's configuration update handler runs before its first layout and whenever its state
// changes (selection, highlight), the content configuration is updated for the state, and a
// content view that supports the new configuration is reused rather than remade.
import Testing
import UIKit

@Suite @MainActor struct ConfigurationStateTests {
    final class Source: NSObject, UITableViewDataSource {
        var states: [UICellConfigurationState] = []
        var madeViews = 0
        func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { 2 }
        func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            var content = cell.defaultContentConfiguration()
            content.text = "Row \(indexPath.row)"
            cell.contentConfiguration = content
            cell.configurationUpdateHandler = { [weak self] cell, state in
                self?.states.append(state)
                var content = cell.contentConfiguration as! UIListContentConfiguration
                content.text = state.isSelected ? "Selected" : "Row \(indexPath.row)"
                cell.contentConfiguration = content
            }
            return cell
        }
    }

    private func table() -> (UITableView, Source) {
        let scene = UIKitScene.shared
        scene.removeAllWindows()
        scene.configureScreen(size: CGSize(width: 320, height: 300), scale: 2)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 300))
        let table = UITableView(frame: window.bounds, style: .plain)
        let source = Source()
        table.dataSource = source
        window.addSubview(table)
        window.makeKeyAndVisible()
        scene.layout(in: CGSize(width: 320, height: 300))
        return (table, source)
    }

    @Test func handlerRunsBeforeTheFirstLayoutAndOnSelection() {
        let (table, source) = table()
        #expect(source.states.count == 2)
        #expect(source.states.allSatisfy { !$0.isSelected })
        let first = table.cellForRow(at: IndexPath(row: 0, section: 0))!
        let contentView = first.contentView.subviews.first
        table.selectRow(at: IndexPath(row: 0, section: 0), animated: false, scrollPosition: .none)
        UIKitScene.shared.layout(in: CGSize(width: 320, height: 300))
        #expect(source.states.count == 3)
        #expect(source.states.last?.isSelected == true)
        #expect((first.contentConfiguration as? UIListContentConfiguration)?.text == "Selected")
        // The list content view supports every list configuration: the same view is kept.
        #expect(first.contentView.subviews.first === contentView)
        table.deselectRow(at: IndexPath(row: 0, section: 0), animated: false)
        UIKitScene.shared.layout(in: CGSize(width: 320, height: 300))
        #expect(source.states.last?.isSelected == false)
        #expect((first.contentConfiguration as? UIListContentConfiguration)?.text == "Row 0")
        // Highlighting is a state too; setting the same value again is not a change.
        first.setHighlighted(true, animated: false)
        first.setHighlighted(true, animated: false)
        UIKitScene.shared.layout(in: CGSize(width: 320, height: 300))
        #expect(source.states.count == 5)
        #expect(source.states.last?.isHighlighted == true)
    }

    @Test func collectionCellsUpdateForSelection() {
        let scene = UIKitScene.shared
        scene.removeAllWindows()
        scene.configureScreen(size: CGSize(width: 320, height: 300), scale: 2)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 300))
        let layout = UICollectionViewCompositionalLayout.list(using: UICollectionLayoutListConfiguration(appearance: .plain))
        let collection = UICollectionView(frame: window.bounds, collectionViewLayout: layout)
        var seen: [Bool] = []
        let registration = UICollectionView.CellRegistration<UICollectionViewListCell, Int> { cell, _, item in
            cell.configurationUpdateHandler = { cell, state in
                seen.append(state.isSelected)
                var content = UIListContentConfiguration.cell()
                content.text = state.isSelected ? "Selected" : "Item \(item)"
                cell.contentConfiguration = content
            }
        }
        let source = UICollectionViewDiffableDataSource<Int, Int>(collectionView: collection) { collection, indexPath, item in
            collection.dequeueConfiguredReusableCell(using: registration, for: indexPath, item: item)
        }
        var snapshot = NSDiffableDataSourceSnapshot<Int, Int>()
        snapshot.appendSections([0])
        snapshot.appendItems([1, 2])
        source.apply(snapshot, animatingDifferences: false)
        window.addSubview(collection)
        window.makeKeyAndVisible()
        scene.layout(in: CGSize(width: 320, height: 300))
        // Once per cell before its first layout (dequeuing prepares the cell for reuse, which
        // asks for another update), none selected.
        #expect(seen.count >= 2 && seen.allSatisfy { !$0 }, "\(seen)")
        collection.selectItem(at: IndexPath(item: 1, section: 0), animated: false, scrollPosition: [])
        scene.layout(in: CGSize(width: 320, height: 300))
        #expect(seen.last == true)
        let cell = collection.cellForItem(at: IndexPath(item: 1, section: 0))
        #expect((cell?.contentConfiguration as? UIListContentConfiguration)?.text == "Selected")
    }
}
