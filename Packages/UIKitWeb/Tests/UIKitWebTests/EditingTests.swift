// Table editing (Containers/SwipeActions.swift): a leftward pan on a row reveals its trailing
// actions and settles open past half their width; a tap on an action runs its handler; a full
// swipe performs the first action; vertical pans scroll instead; editing mode's controls
// reveal the Delete button or commit an insert.
import Testing
import UIKit
@testable import UIKitWebCore

@Suite @MainActor struct EditingTests {
    final class Source: NSObject, UITableViewDataSource, UITableViewDelegate {
        var rows = ["a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l"]
        var committed: [(UITableViewCell.EditingStyle, IndexPath)] = []
        var flagged: [IndexPath] = []
        var offersActions = true
        func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { rows.count }
        func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
            let cell = tableView.dequeueReusableCell(withIdentifier: "cell") ?? UITableViewCell(style: .default, reuseIdentifier: "cell")
            cell.textLabel?.text = rows[indexPath.row]
            cell.showsReorderControl = true
            return cell
        }
        func tableView(_ tableView: UITableView, editingStyleForRowAt indexPath: IndexPath) -> UITableViewCell.EditingStyle { indexPath.row == 2 ? .insert : .delete }
        var moved: [(IndexPath, IndexPath)] = []
        func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool { true }
        func tableView(_ tableView: UITableView, moveRowAt sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath) {
            moved.append((sourceIndexPath, destinationIndexPath))
            rows.insert(rows.remove(at: sourceIndexPath.row), at: destinationIndexPath.row)
        }
        func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
            committed.append((editingStyle, indexPath))
            if editingStyle == .delete { rows.remove(at: indexPath.row); tableView.deleteRows(at: [indexPath], with: .fade) }
        }
        func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
            guard offersActions else { return nil }
            let flag = UIContextualAction(style: .normal, title: "Flag") { [weak self] _, _, done in self?.flagged.append(indexPath); done(true) }
            let configuration = UISwipeActionsConfiguration(actions: [flag])
            configuration.performsFirstActionWithFullSwipe = true
            return configuration
        }
    }

    private func table() -> (UITableView, Source) {
        let scene = UIKitScene.shared
        scene.removeAllWindows()
        scene.configureScreen(size: CGSize(width: 320, height: 300), scale: 2)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 300))
        let table = UITableView(frame: window.bounds, style: .plain)
        table.rowHeight = 44
        let source = Source()
        table.dataSource = source
        table.delegate = source
        window.addSubview(table)
        window.makeKeyAndVisible()
        scene.layout(in: window.bounds.size)
        return (table, source)
    }

    private func drag(from: CGPoint, to: CGPoint, steps: Int = 4) {
        let scene = UIKitScene.shared
        scene.pointerDown(at: from, type: .touch, time: 0)
        for step in 1...steps {
            let t = Double(step) / Double(steps)
            scene.pointerMoved(to: CGPoint(x: from.x + (to.x - from.x) * t, y: from.y + (to.y - from.y) * t), time: 0.05 * Double(step))
        }
        scene.pointerUp(at: to, time: 0.05 * Double(steps) + 0.2)
        _ = scene.advanceFrame(elapsed: 0.5)
    }

    @Test func swipeRevealsAndSettlesOpen() {
        let (table, source) = table()
        defer { withExtendedLifetime(source) {} }
        let cell = table.cellForRow(at: IndexPath(row: 1, section: 0))!
        drag(from: CGPoint(x: 250, y: 66), to: CGPoint(x: 150, y: 66))
        #expect(table.swipedRow == IndexPath(row: 1, section: 0))
        #expect(cell.isSwipeOpen)
        #expect(cell.swipeOffset == -cell.swipeActionsWidth)
        #expect(cell.swipeActionsWidth >= 74)
        #expect(cell.contentView.frame.minX == cell.swipeOffset)
        #expect(table.contentOffset.y == 0)
        // A tap elsewhere closes it.
        UIKitScene.shared.pointerDown(at: CGPoint(x: 100, y: 200), type: .touch, time: 2)
        UIKitScene.shared.pointerUp(at: CGPoint(x: 100, y: 200), time: 2.05)
        _ = UIKitScene.shared.advanceFrame(elapsed: 0.5)
        #expect(table.swipedRow == nil)
        #expect(cell.swipeOffset == 0)
    }

    @Test func shortSwipeClosesAndVerticalPanScrolls() {
        let (table, source) = table()
        defer { withExtendedLifetime(source) {} }
        drag(from: CGPoint(x: 250, y: 66), to: CGPoint(x: 230, y: 66))
        #expect(table.swipedRow == nil)
        drag(from: CGPoint(x: 160, y: 250), to: CGPoint(x: 160, y: 100))
        #expect(table.swipedRow == nil)
        #expect(table.contentOffset.y > 0)
    }

    @Test func actionTapAndFullSwipeRunHandlers() {
        let (table, source) = table()
        defer { withExtendedLifetime(source) {} }
        drag(from: CGPoint(x: 250, y: 66), to: CGPoint(x: 150, y: 66))
        let cell = table.cellForRow(at: IndexPath(row: 1, section: 0))!
        let button = cell.subviews.compactMap { $0 as? SwipeActionButton }.first
        #expect(button != nil)
        let centre = button!.convert(CGPoint(x: button!.bounds.midX, y: button!.bounds.midY), to: nil)
        UIKitScene.shared.pointerDown(at: centre, type: .touch, time: 3)
        UIKitScene.shared.pointerUp(at: centre, time: 3.05)
        _ = UIKitScene.shared.advanceFrame(elapsed: 0.5)
        #expect(source.flagged == [IndexPath(row: 1, section: 0)])
        #expect(table.swipedRow == nil)
        // A full swipe past the middle performs the first action at once.
        drag(from: CGPoint(x: 300, y: 110), to: CGPoint(x: 40, y: 110))
        #expect(source.flagged.count == 2 && source.flagged.last == IndexPath(row: 2, section: 0))
    }

    @Test func editingControlsDeleteAndInsert() {
        let (table, source) = table()
        defer { withExtendedLifetime(source) {} }
        source.offersActions = false
        table.setEditing(true, animated: false)
        UIKitScene.shared.layout(in: CGSize(width: 320, height: 300))
        let first = table.cellForRow(at: IndexPath(row: 0, section: 0))!
        #expect(first.isEditing && first.contentView.frame.minX == 40)
        // The insert control commits an insert.
        UIKitScene.shared.pointerDown(at: CGPoint(x: 28, y: 110), type: .touch, time: 4)
        UIKitScene.shared.pointerUp(at: CGPoint(x: 28, y: 110), time: 4.05)
        _ = UIKitScene.shared.advanceFrame(elapsed: 0.5)
        #expect(source.committed.map(\.0) == [.insert])
        // The delete control reveals Delete; tapping it commits the delete and the row goes.
        UIKitScene.shared.pointerDown(at: CGPoint(x: 28, y: 22), type: .touch, time: 5)
        UIKitScene.shared.pointerUp(at: CGPoint(x: 28, y: 22), time: 5.05)
        _ = UIKitScene.shared.advanceFrame(elapsed: 0.5)
        #expect(table.swipedRow == IndexPath(row: 0, section: 0))
        let button = first.subviews.compactMap { $0 as? SwipeActionButton }.first
        #expect(button?.action.title == "Delete")
        let centre = button.map { $0.convert(CGPoint(x: $0.bounds.midX, y: $0.bounds.midY), to: nil) } ?? .zero
        UIKitScene.shared.pointerDown(at: centre, type: .touch, time: 6)
        UIKitScene.shared.pointerUp(at: centre, time: 6.05)
        _ = UIKitScene.shared.advanceFrame(elapsed: 0.5)
        #expect(source.committed.map(\.0) == [.insert, .delete])
        #expect(source.rows.first == "b")
        #expect(table.cellForRow(at: IndexPath(row: 0, section: 0))?.textLabel?.text == "b")
    }

    @Test func draggingTheGripReordersRows() {
        let (table, source) = table()
        defer { withExtendedLifetime(source) {} }
        table.setEditing(true, animated: false)
        UIKitScene.shared.layout(in: CGSize(width: 320, height: 300))
        let first = table.cellForRow(at: IndexPath(row: 0, section: 0))!
        // Drag row 0's grip (at the right edge) down past the third row's middle.
        let scene = UIKitScene.shared
        scene.pointerDown(at: CGPoint(x: 300, y: 22), type: .touch, time: 10)
        scene.pointerMoved(to: CGPoint(x: 300, y: 60), time: 10.05)
        #expect(table.reorderingRow == IndexPath(row: 0, section: 0))
        scene.pointerMoved(to: CGPoint(x: 300, y: 120), time: 10.1)
        #expect(first.frame.minY == 98)
        _ = scene.advanceFrame(elapsed: 0.3)
        // The second and third rows have moved up to make way.
        #expect(table.cellForRow(at: IndexPath(row: 1, section: 0))?.frame.minY == 0)
        scene.pointerUp(at: CGPoint(x: 300, y: 120), time: 10.3)
        _ = scene.advanceFrame(elapsed: 0.5)
        #expect(source.moved.map { $0.0.row } == [0] && source.moved.map { $0.1.row } == [2])
        #expect(source.rows.prefix(3) == ["b", "c", "a"])
        #expect(table.reorderingRow == nil)
        #expect(table.cellForRow(at: IndexPath(row: 2, section: 0)) === first)
        #expect(first.frame.minY == 88)
        #expect(table.cellForRow(at: IndexPath(row: 2, section: 0))?.textLabel?.text == "a")
    }

    /// The section index (Containers/SectionIndex.swift): a touch on a title scrolls its section
    /// to the top; dragging along the strip follows.
    @Test func sectionIndexJumpsToSections() {
        final class Indexed: NSObject, UITableViewDataSource {
            let titles = ["A", "B", "C", "D", "E", "F", "G", "H"]
            func numberOfSections(in tableView: UITableView) -> Int { titles.count }
            func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { 3 }
            func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? { titles[section] }
            func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
                tableView.dequeueReusableCell(withIdentifier: "cell") ?? UITableViewCell(style: .default, reuseIdentifier: "cell")
            }
            func sectionIndexTitles(for tableView: UITableView) -> [String]? { titles }
        }
        let scene = UIKitScene.shared
        scene.removeAllWindows()
        scene.configureScreen(size: CGSize(width: 320, height: 300), scale: 2)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 300))
        let table = UITableView(frame: window.bounds, style: .plain)
        table.rowHeight = 44
        let source = Indexed()
        defer { withExtendedLifetime(source) {} }
        table.dataSource = source
        window.addSubview(table)
        window.makeKeyAndVisible()
        scene.layout(in: window.bounds.size)
        #expect(!table.sectionIndex.isHidden && table.sectionIndex.frame == CGRect(x: 305, y: 0, width: 15, height: 300))
        #expect(table.cellForRow(at: IndexPath(row: 0, section: 0))?.contentView.frame.width == 305)
        // The strip's column of 8 titles is centred: 112 tall from 94; the fourth title at 136..150.
        scene.pointerDown(at: CGPoint(x: 312, y: 143), type: .touch, time: 1)
        #expect(table.contentOffset.y == table.rectForRow(at: IndexPath(row: 0, section: 3)).minY - 28)
        scene.pointerMoved(to: CGPoint(x: 312, y: 200), time: 1.1)
        scene.pointerUp(at: CGPoint(x: 312, y: 200), time: 1.2)
        let last = table.contentOffset.y
        #expect(last > table.rectForRow(at: IndexPath(row: 0, section: 3)).minY - 28)
        #expect(last <= max(0, table.contentSize.height - 300))
    }
}
