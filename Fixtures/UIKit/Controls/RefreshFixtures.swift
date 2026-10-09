// UIRefreshControl (uk-refresh, Docs/elements/UIKit/UIScrollView.md): a table and a plain
// scroll view with refresh controls at rest, refreshing (begun programmatically, the content
// scrolled down to show the control as a pull would), and back at rest.
#if canImport(UIKit)
import UIKit
import UIKitFixtureKit

@MainActor public final class RefreshModel {
    let table = UITableView(frame: .zero, style: .plain)
    let scroll = UIScrollView()
    let tableControl = UIRefreshControl()
    let scrollControl = UIRefreshControl()
    let source = RefreshRows()
    public init() {}
}

final class RefreshRows: NSObject, UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { 20 }
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "row", for: indexPath)
        var content = cell.defaultContentConfiguration()
        content.text = "Row \(indexPath.row + 1)"
        cell.contentConfiguration = content
        return cell
    }
}

public enum RefreshFixtures {
    public static let all = [refresh]

    public static let refresh = UIKitFixture("uikit/scroll/refresh", size: CGSize(width: 320, height: 480), model: { RefreshModel() }, steps: [
        UIKitFixtureStep("refreshing") { model in
            // beginRefreshing does not scroll: the content is moved down by the control's
            // height, as an app does after a programmatic refresh.
            model.tableControl.beginRefreshing()
            model.table.setContentOffset(CGPoint(x: 0, y: -model.tableControl.frame.height), animated: false)
            model.scrollControl.beginRefreshing()
            model.scroll.setContentOffset(CGPoint(x: 0, y: -model.scrollControl.frame.height), animated: false)
        },
        UIKitFixtureStep("ended") { model in
            model.tableControl.endRefreshing()
            model.table.setContentOffset(.zero, animated: false)
            model.scrollControl.endRefreshing()
            model.scroll.setContentOffset(.zero, animated: false)
        },
    ]) { model in
        let root = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        root.backgroundColor = .white

        model.table.frame = CGRect(x: 0, y: 0, width: 320, height: 240)
        model.table.dataSource = model.source
        model.table.register(UITableViewCell.self, forCellReuseIdentifier: "row")
        model.table.refreshControl = model.tableControl
        root.addSubview(model.table.probe("table"))
        model.tableControl.probe("tableControl")

        model.scroll.frame = CGRect(x: 0, y: 240, width: 320, height: 240)
        model.scroll.backgroundColor = .systemGray6
        model.scroll.contentSize = CGSize(width: 320, height: 800)
        model.scrollControl.attributedTitle = NSAttributedString(string: "Pull to refresh")
        model.scroll.refreshControl = model.scrollControl
        let label = UILabel()
        label.text = "Scroll view content"
        label.font = .systemFont(ofSize: 17)
        label.sizeToFit()
        label.frame.origin = CGPoint(x: 16, y: 16)
        model.scroll.addSubview(label.probe("scrollLabel"))
        root.addSubview(model.scroll.probe("scroll"))
        model.scrollControl.probe("scrollControl")
        return root
    }
}
#endif
