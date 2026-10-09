// UISearchBar looks and a search controller's results (uk-searchbar): a bar with a prompt, the
// bookmark button, the clear button while editing, and a navigation controller whose search
// bar hides on scroll, presents a results controller when activated and shares the floating
// bottom bar with toolbar items.
#if canImport(UIKit)
import UIKit
import UIKitFixtureKit

@MainActor public final class SearchLooksModel {
    let editing = UISearchBar()
    public init() {}
}

/// A screen listing numbered rows in a table, tall enough to scroll.
final class RowsController: UIViewController, UITableViewDataSource {
    let table = UITableView(frame: .zero, style: .plain)
    var count = 40
    var probeName = "table"

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        table.dataSource = self
        table.register(UITableViewCell.self, forCellReuseIdentifier: "row")
        table.frame = view.bounds
        table.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(table.probe(probeName))
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { count }
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "row", for: indexPath)
        var content = cell.defaultContentConfiguration()
        content.text = "Row \(indexPath.row + 1)"
        cell.contentConfiguration = content
        return cell
    }
}

@MainActor public final class SearchResultsModel {
    var navigation: UINavigationController?
    var searchController: UISearchController?
    var rows: RowsController?
    public init() {}
}

extension BarFixtures {
    /// A prompt above the field, the bookmark button beside the placeholder, and a bar with text
    /// whose clear button appears once it edits (the simulator paints clear buttons only while
    /// editing).
    public static let searchLooks = UIKitFixture("uikit/search/looks", size: CGSize(width: 320, height: 320), model: { SearchLooksModel() }, steps: [
        UIKitFixtureStep("edit") { model in model.editing.becomeFirstResponder() },
    ]) { model in
        let root = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 320))
        root.backgroundColor = .white

        let prompted = UISearchBar()
        prompted.placeholder = "Search"
        prompted.prompt = "Find anything in your library"
        prompted.sizeToFit()
        prompted.frame = CGRect(x: 0, y: 8, width: 320, height: prompted.frame.height)
        root.addSubview(prompted.probe("prompted"))
        prompted.searchTextField.probe("promptedField")

        let bookmark = UISearchBar()
        bookmark.placeholder = "Search"
        bookmark.showsBookmarkButton = true
        bookmark.sizeToFit()
        bookmark.frame = CGRect(x: 0, y: 112, width: 320, height: bookmark.frame.height)
        root.addSubview(bookmark.probe("bookmark"))
        bookmark.searchTextField.probe("bookmarkField")

        model.editing.text = "Swift"
        model.editing.sizeToFit()
        model.editing.frame = CGRect(x: 0, y: 192, width: 320, height: model.editing.frame.height)
        root.addSubview(model.editing.probe("editing"))
        model.editing.searchTextField.probe("editingField")
        return root
    }

    /// A large-titled navigation controller over a table with a search controller that presents
    /// a results controller, hides its bar on scroll and shares the bottom bar with toolbar items.
    public static let searchResults = UIKitFixture("uikit/nav/search-results", size: CGSize(width: 320, height: 480), model: { SearchResultsModel() }, steps: [
        UIKitFixtureStep("scroll") { model in
            model.rows?.table.setContentOffset(CGPoint(x: 0, y: 200), animated: false)
        },
        UIKitFixtureStep("activate") { model in
            model.rows?.table.setContentOffset(.zero, animated: false)
            model.searchController?.isActive = true
            model.searchController?.searchBar.text = "Ro"
        },
    ]) { model in
        let rows = RowsController()
        rows.title = "Rows"
        rows.toolbarItems = [
            UIBarButtonItem(barButtonSystemItem: .add, target: nil, action: nil),
            UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil),
        ]
        let results = ScreenController.make(title: "Results", text: "Results for the search", probe: "resultsLabel")
        let searchController = UISearchController(searchResultsController: results)
        searchController.searchBar.placeholder = "Search rows"
        rows.navigationItem.searchController = searchController
        rows.navigationItem.hidesSearchBarWhenScrolling = true
        let navigation = UINavigationController(rootViewController: rows)
        navigation.navigationBar.prefersLargeTitles = true
        navigation.isToolbarHidden = false
        navigation.navigationBar.probe("bar")
        searchController.searchBar.probe("search")
        rows.view.probe("content")
        model.navigation = navigation
        model.searchController = searchController
        model.rows = rows
        return navigation
    }.capturesWindow()
}
#endif
