// uk-dragdrop (Events/DragDrop.swift): drag and drop interactions lifted by the scene's
// pointer, the collection and table drag and drop delegates, and the host's external entry
// points carrying a session across the app boundary.
import Testing
import WebGraphics
@testable import UIKitWebCore
import UIKit

@Suite @MainActor struct DragDropTests {
    final class Source: NSObject, UIDragInteractionDelegate {
        var text = "Hello"
        var began = 0
        var ended: [UIDropOperation] = []
        func dragInteraction(_ interaction: UIDragInteraction, itemsForBeginning session: any UIDragSession) -> [UIDragItem] {
            [DragDropTests.textItem(text)]
        }
        func dragInteraction(_ interaction: UIDragInteraction, sessionWillBegin session: any UIDragSession) { began += 1 }
        func dragInteraction(_ interaction: UIDragInteraction, session: any UIDragSession, didEndWith operation: UIDropOperation) { ended.append(operation) }
    }

    final class Target: NSObject, UIDropInteractionDelegate {
        var entered = 0, exited = 0, updates = 0, endedSessions = 0
        var dropped: [String] = []
        var localDrops = 0
        var operation: UIDropOperation = .copy
        func dropInteraction(_ interaction: UIDropInteraction, canHandle session: any UIDropSession) -> Bool { session.canLoadObjects(ofClass: String.self) }
        func dropInteraction(_ interaction: UIDropInteraction, sessionDidEnter session: any UIDropSession) { entered += 1 }
        func dropInteraction(_ interaction: UIDropInteraction, sessionDidUpdate session: any UIDropSession) -> UIDropProposal {
            updates += 1
            return UIDropProposal(operation: operation)
        }
        func dropInteraction(_ interaction: UIDropInteraction, sessionDidExit session: any UIDropSession) { exited += 1 }
        func dropInteraction(_ interaction: UIDropInteraction, performDrop session: any UIDropSession) {
            if session.localDragSession != nil { localDrops += 1 }
            session.loadObjects(ofClass: String.self) { [self] strings in dropped += strings }
        }
        func dropInteraction(_ interaction: UIDropInteraction, sessionDidEnd session: any UIDropSession) { endedSessions += 1 }
    }

    /// A drag item carrying `text`; Foundation's providers load on a queue of their own, so
    /// the test preloads the value the way the stand-in on wasm gives it at once.
    static func textItem(_ text: String) -> UIDragItem {
        let item = UIDragItem(itemProvider: NSItemProvider(object: text as NSString))
        item.localObject = text
        item._preload(.text(text), forTypeIdentifier: "public.utf8-plain-text")
        return item
    }

    private func scene() -> (UIKitScene, UIView) {
        let scene = UIKitScene.shared
        scene.removeAllWindows()
        scene.configureScreen(size: CGSize(width: 320, height: 400), scale: 2)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 400))
        let root = UIView(frame: window.bounds)
        window.addSubview(root)
        window.makeKeyAndVisible()
        return (scene, root)
    }

    @Test func dragAndDropInteractions() {
        let (scene, root) = scene()
        let card = UIView(frame: CGRect(x: 20, y: 20, width: 100, height: 60))
        card.backgroundColor = .systemBlue
        let well = UIView(frame: CGRect(x: 20, y: 200, width: 280, height: 150))
        root.addSubview(card)
        root.addSubview(well)
        let source = Source(), target = Target()
        card.addInteraction(UIDragInteraction(delegate: source))
        well.addInteraction(UIDropInteraction(delegate: target))
        scene.layout(in: CGSize(width: 320, height: 400))

        // A finger held half a second lifts; the preview rides under it at 0.8 opacity.
        scene.pointerDown(at: CGPoint(x: 50, y: 40), type: .touch, time: 0)
        #expect(!scene.isDragging)
        _ = scene.advanceFrame(elapsed: 0.6)
        #expect(scene.isDragging && source.began == 1 && scene.pointerCursor == "grabbing")
        scene.pointerMoved(to: CGPoint(x: 150, y: 260), time: 0.7)
        #expect(target.entered == 1 && target.updates == 1)
        let list = scene.render(scale: 2)
        #expect(list.commands.contains { if case .beginGroup(let opacity) = $0 { return opacity == 0.8 } else { return false } })
        // The preview keeps the grab offset: the card's origin 30 left and 20 up of the pointer.
        let session = try! #require(scene.dragSession)
        #expect(session.grab == CGPoint(x: 30, y: 20) && session.location(in: well) == CGPoint(x: 130, y: 60))
        scene.pointerMoved(to: CGPoint(x: 150, y: 100), time: 0.8)
        #expect(target.exited == 1)
        scene.pointerMoved(to: CGPoint(x: 160, y: 300), time: 0.9)
        scene.pointerUp(at: CGPoint(x: 160, y: 300), time: 1)
        #expect(!scene.isDragging && target.dropped == ["Hello"] && target.localDrops == 1 && target.endedSessions == 1)
        #expect(source.ended == [.copy] && scene.pointerCursor == nil)

        // A pointer lifts after 4 pt of travel, no wait; a forbidden proposal drops nothing.
        target.operation = .forbidden
        scene.pointerDown(at: CGPoint(x: 50, y: 40), type: .mouse, time: 2)
        scene.pointerMoved(to: CGPoint(x: 56, y: 40), time: 2.05)
        #expect(scene.isDragging && source.began == 2)
        scene.pointerMoved(to: CGPoint(x: 160, y: 300), time: 2.1)
        scene.pointerUp(at: CGPoint(x: 160, y: 300), time: 2.2)
        #expect(target.dropped == ["Hello"] && source.ended == [.copy, .forbidden])

        // A finger that travels before the lift is a scroll, not a drag.
        scene.pointerDown(at: CGPoint(x: 50, y: 40), type: .touch, time: 3)
        scene.pointerMoved(to: CGPoint(x: 50, y: 80), time: 3.1)
        _ = scene.advanceFrame(elapsed: 0.6)
        #expect(!scene.isDragging)
        scene.pointerUp(at: CGPoint(x: 50, y: 80), time: 3.8)
        withExtendedLifetime((source, target)) {}
    }

    final class Reorderer: NSObject, UICollectionViewDataSource, UICollectionViewDragDelegate, UICollectionViewDropDelegate, UITableViewDataSource, UITableViewDragDelegate, UITableViewDropDelegate {
        var items = ["a", "b", "c", "d"]
        var entered = 0
        var proposals: [IndexPath?] = []
        var drops: [(IndexPath?, IndexPath?, UIDropOperation)] = []
        func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { items.count }
        func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
            collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath)
        }
        func collectionView(_ collectionView: UICollectionView, itemsForBeginning session: any UIDragSession, at indexPath: IndexPath) -> [UIDragItem] {
            [DragDropTests.textItem(items[indexPath.item])]
        }
        func collectionView(_ collectionView: UICollectionView, dropSessionDidEnter session: any UIDropSession) { entered += 1 }
        func collectionView(_ collectionView: UICollectionView, dropSessionDidUpdate session: any UIDropSession, withDestinationIndexPath destinationIndexPath: IndexPath?) -> UICollectionViewDropProposal {
            proposals.append(destinationIndexPath)
            return UICollectionViewDropProposal(operation: session.localDragSession != nil ? .move : .copy, intent: .insertAtDestinationIndexPath)
        }
        func collectionView(_ collectionView: UICollectionView, performDropWith coordinator: UICollectionViewDropCoordinator) {
            for item in coordinator.items {
                drops.append((item.sourceIndexPath, coordinator.destinationIndexPath, coordinator.proposal.operation))
                guard let from = item.sourceIndexPath, let to = coordinator.destinationIndexPath else { continue }
                let value = items.remove(at: from.item)
                items.insert(value, at: min(to.item, items.count))
                collectionView.reloadData()
            }
        }
        func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { items.count }
        func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
            let cell = tableView.dequeueReusableCell(withIdentifier: "row") ?? UITableViewCell(style: .default, reuseIdentifier: "row")
            cell.textLabel?.text = items[indexPath.row]
            return cell
        }
        func tableView(_ tableView: UITableView, itemsForBeginning session: any UIDragSession, at indexPath: IndexPath) -> [UIDragItem] {
            [DragDropTests.textItem(items[indexPath.row])]
        }
        func tableView(_ tableView: UITableView, performDropWith coordinator: UITableViewDropCoordinator) {
            for item in coordinator.items { drops.append((item.sourceIndexPath, coordinator.destinationIndexPath, coordinator.proposal.operation)) }
        }
    }

    @Test func collectionAndTableDelegates() throws {
        let (scene, root) = scene()
        let item = NSCollectionLayoutItem(layoutSize: NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .absolute(40)))
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .absolute(40)), subitems: [item])
        let collection = UICollectionView(frame: CGRect(x: 0, y: 0, width: 320, height: 200), collectionViewLayout: UICollectionViewCompositionalLayout(section: NSCollectionLayoutSection(group: group)))
        collection.register(UICollectionViewCell.self, forCellWithReuseIdentifier: "cell")
        let reorderer = Reorderer()
        collection.dataSource = reorderer
        collection.dragDelegate = reorderer
        collection.dropDelegate = reorderer
        root.addSubview(collection)
        scene.layout(in: CGSize(width: 320, height: 400))
        // Lift "a" (row 0) and drop it on "c" (row 2): a move with the source index path.
        scene.pointerDown(at: CGPoint(x: 100, y: 20), type: .touch, time: 0)
        _ = scene.advanceFrame(elapsed: 0.6)
        #expect(scene.isDragging && collection.hasActiveDrag)
        scene.pointerMoved(to: CGPoint(x: 100, y: 100), time: 0.7)
        #expect(reorderer.entered == 1 && collection.hasActiveDrop && reorderer.proposals.last == IndexPath(item: 2, section: 0))
        scene.pointerUp(at: CGPoint(x: 100, y: 100), time: 0.8)
        #expect(reorderer.drops.count == 1 && reorderer.drops[0].0 == IndexPath(item: 0, section: 0) && reorderer.drops[0].1 == IndexPath(item: 2, section: 0) && reorderer.drops[0].2 == .move)
        #expect(reorderer.items == ["b", "c", "a", "d"] && !collection.hasActiveDrag && !collection.hasActiveDrop)
        // Past the last item the destination is the end of the section.
        scene.pointerDown(at: CGPoint(x: 100, y: 20), type: .mouse, time: 2)
        scene.pointerMoved(to: CGPoint(x: 100, y: 190), time: 2.1)
        #expect(reorderer.proposals.last == IndexPath(item: 4, section: 0))
        scene.cancelDrag()
        #expect(!scene.isDragging)
        // Turning drags off removes the lift.
        collection.dragInteractionEnabled = false
        scene.pointerDown(at: CGPoint(x: 100, y: 20), type: .mouse, time: 3)
        scene.pointerMoved(to: CGPoint(x: 100, y: 100), time: 3.1)
        #expect(!scene.isDragging)
        scene.pointerUp(at: CGPoint(x: 100, y: 100), time: 3.2)

        // A table: rows lift the same way and the coordinator names the destination row.
        collection.removeFromSuperview()
        let table = UITableView(frame: CGRect(x: 0, y: 0, width: 320, height: 300), style: .plain)
        table.rowHeight = 44
        table.dataSource = reorderer
        table.dragDelegate = reorderer
        table.dropDelegate = reorderer
        root.addSubview(table)
        scene.layout(in: CGSize(width: 320, height: 400))
        scene.pointerDown(at: CGPoint(x: 100, y: 22), type: .mouse, time: 4)
        scene.pointerMoved(to: CGPoint(x: 100, y: 66), time: 4.1)
        #expect(table.hasActiveDrag)
        scene.pointerMoved(to: CGPoint(x: 100, y: 150), time: 4.2)
        scene.pointerUp(at: CGPoint(x: 100, y: 150), time: 4.3)
        let last = try #require(reorderer.drops.last)
        #expect(last.0 == IndexPath(row: 0, section: 0) && last.1 == IndexPath(row: 3, section: 0) && last.2 == .move)
        withExtendedLifetime(reorderer) {}
    }

    @Test func acrossTheAppBoundary() {
        let (scene, root) = scene()
        let card = UIView(frame: CGRect(x: 20, y: 20, width: 100, height: 60))
        let well = UIView(frame: CGRect(x: 20, y: 200, width: 280, height: 150))
        root.addSubview(card)
        root.addSubview(well)
        let source = Source(), target = Target()
        card.addInteraction(UIDragInteraction(delegate: source))
        well.addInteraction(UIDropInteraction(delegate: target))
        scene.layout(in: CGSize(width: 320, height: 400))
        // The host asks before marking its canvas draggable; the system drag lifts the items.
        #expect(scene.hasDragSource(at: CGPoint(x: 50, y: 40)) && !scene.hasDragSource(at: CGPoint(x: 200, y: 40)))
        let items = scene.beginExternalDrag(at: CGPoint(x: 50, y: 40))
        #expect(items == [ExternalDragItem(type: "text/plain", text: "Hello")])
        #expect(scene.isDragging && scene.externalDragItems() == items)
        let preview = scene.externalDragPreview()
        #expect(preview?.size == CGSize(width: 100, height: 60) && preview?.grab == CGPoint(x: 30, y: 20))
        // The system drag paints its own image: the scene's render has no preview group.
        #expect(!scene.render(scale: 2).commands.contains { if case .beginGroup(let opacity) = $0 { return opacity == 0.8 } else { return false } })
        #expect(scene.externalDragUpdated(types: ["text/plain"], at: CGPoint(x: 100, y: 250)) && target.entered == 1)
        scene.externalDragExited()
        #expect(target.exited == 1 && scene.isDragging)
        scene.externalDragEnded(dropped: true)
        #expect(!scene.isDragging && source.ended == [.cancel])

        // A drag from outside: its types target the well, the drop brings the data.
        #expect(scene.externalDragUpdated(types: ["text/plain"], at: CGPoint(x: 100, y: 250)))
        #expect(scene.isDragging && scene.dragSession?.localDragSession == nil && target.entered == 2)
        #expect(scene.externalDrop(items: [ExternalDragItem(type: "text/plain", text: "From outside")], at: CGPoint(x: 100, y: 250)))
        #expect(target.dropped == ["From outside"] && target.localDrops == 0 && !scene.isDragging)
        // A type the well cannot take targets nothing.
        #expect(!scene.externalDragUpdated(types: ["image/png"], at: CGPoint(x: 100, y: 250)))
        scene.externalDragExited()
        #expect(!scene.isDragging)
        withExtendedLifetime((source, target)) {}
    }
}
