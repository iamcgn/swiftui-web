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
