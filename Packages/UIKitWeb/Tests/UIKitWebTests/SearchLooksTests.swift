// uk-searchbar (Controls/UISearchBar.swift, Containers/UINavigationController.swift): the
// prompt's band, the bookmark button and the delegate it calls, the clear button while editing,
// a search controller presenting its results and dismissing from Cancel, the bar hiding on
// scroll and coming back on a pull, and the toolbar sharing the bottom with a hidden bar.
import Testing
import UIKit
@testable import UIKitWebCore
#if canImport(AppKit)
import WebGraphicsNative
#endif

@Suite @MainActor struct SearchLooksTests {
    private func scene() -> UIKitScene {
        let scene = UIKitScene.shared
        scene.removeAllWindows()
        #if canImport(AppKit)
        scene.textEngine = CoreTextEngine()
        #else
        scene.textEngine = SyntheticTextEngine()
        #endif
        scene.configureScreen(size: CGSize(width: 320, height: 480), scale: 2)
        return scene
    }

    private func tap(_ scene: UIKitScene, at point: CGPoint) {
        scene.pointerDown(at: point, type: .touch, time: 0)
        scene.pointerUp(at: point, time: 0.05)
    }

    @MainActor final class Delegate: UISearchBarDelegate, UISearchResultsUpdating, UISearchControllerDelegate {
        var bookmarks = 0, results = 0, cancels = 0
        var updates: [String?] = []
        var presented: [Bool] = []
        func searchBarBookmarkButtonClicked(_ searchBar: UISearchBar) { bookmarks += 1 }
        func searchBarResultsListButtonClicked(_ searchBar: UISearchBar) { results += 1 }
        func searchBarCancelButtonClicked(_ searchBar: UISearchBar) { cancels += 1 }
        func updateSearchResults(for searchController: UISearchController) { updates.append(searchController.searchBar.text) }
        func didPresentSearchController(_ searchController: UISearchController) { presented.append(true) }
        func didDismissSearchController(_ searchController: UISearchController) { presented.append(false) }
    }

    @Test func promptBookmarkAndClearButton() {
        let scene = scene()
        let root = UIViewController()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        window.rootViewController = root
        window.makeKeyAndVisible()
        let delegate = Delegate()
        let bar = UISearchBar()
        bar.placeholder = "Search"
        bar.delegate = delegate
        bar.sizeToFit()
        #expect(bar.frame.height == 64)
        bar.prompt = "Find anything"
        #expect(bar.sizeThatFits(.zero).height == 98)
        bar.frame = CGRect(x: 0, y: 0, width: 320, height: 98)
        root.view.addSubview(bar)
        scene.layout(in: CGSize(width: 320, height: 480))
        #expect(bar.searchTextField.frame == CGRect(x: 8, y: 44, width: 304, height: 44))
        bar.showsBookmarkButton = true
        #expect(bar.searchTextField.showsAccessoryButton)
        tap(scene, at: CGPoint(x: 8 + 304 - 27, y: 44 + 22))
        #expect(delegate.bookmarks == 1 && delegate.results == 0)
        bar.showsBookmarkButton = false
        bar.showsSearchResultsButton = true
        tap(scene, at: CGPoint(x: 8 + 304 - 27, y: 44 + 22))
        #expect(delegate.results == 1)
        bar.text = "Swift"
        #expect(!bar.searchTextField.showsAccessoryButton && !bar.searchTextField.showsClearButton)
        bar.becomeFirstResponder()
        #expect(bar.searchTextField.showsClearButton)
        #expect(bar.searchTextField.clearButtonRect(forBounds: bar.searchTextField.bounds) == CGRect(x: 271.25, y: 13.25, width: 17, height: 17))
        let texts = scene.render(scale: 2, background: false).commands.compactMap { command -> String? in
            if case .drawText(let text, _, _, _) = command { return text }
            return nil
        }
        #expect(texts.contains("Find anything") && texts.contains("Swift"))
        bar.showsCancelButton = true
        scene.layout(in: CGSize(width: 320, height: 480))
        tap(scene, at: CGPoint(x: 320 - 8 - 22, y: 44 + 22))
        #expect(delegate.cancels == 1 && !bar.isFirstResponder)
    }

    private func rows(_ count: Int) -> UIViewController {
        final class Rows: UIViewController, UITableViewDataSource {
            let table = UITableView(frame: .zero, style: .plain)
            var count = 0
            override func viewDidLoad() {
                super.viewDidLoad()
                table.dataSource = self
                table.register(UITableViewCell.self, forCellReuseIdentifier: "row")
                table.frame = view.bounds
                table.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                view.addSubview(table)
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
        let controller = Rows()
        controller.count = count
        controller.title = "Rows"
        return controller
    }

    @Test func searchControllerPresentsResultsAndHidesOnScroll() {
        let scene = scene()
        let root = rows(40)
        root.toolbarItems = [UIBarButtonItem(barButtonSystemItem: .add, target: nil, action: nil)]
        let delegate = Delegate()
        let results = UIViewController()
        results.view.backgroundColor = .systemBackground
        let controller = UISearchController(searchResultsController: results)
        controller.searchBar.placeholder = "Search rows"
        controller.searchResultsUpdater = delegate
        controller.delegate = delegate
        root.navigationItem.searchController = controller
        let navigation = UINavigationController(rootViewController: root)
        navigation.navigationBar.prefersLargeTitles = true
        navigation.isToolbarHidden = false
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        window.rootViewController = navigation
        window.makeKeyAndVisible()
        scene.layout(in: CGSize(width: 320, height: 480))
        // Hidden until a pull: a zero-height band under the bar, the toolbar showing.
        #expect(controller.searchBar.frame == CGRect(x: 0, y: 116.5, width: 320, height: 0))
        #expect(!navigation.toolbar.isHidden)
        let table = root.view.subviews.first { $0 is UIScrollView } as! UIScrollView
        table.contentOffset.y = -116.5 - 20   // a pull past the top reveals the bar
        scene.layout(in: CGSize(width: 320, height: 480))
        #expect(controller.searchBar.frame.height == 60 && navigation.toolbar.isHidden)
        table.contentOffset.y = 200   // scrolling away hides it again and collapses the title
        scene.layout(in: CGSize(width: 320, height: 480))
        #expect(controller.searchBar.frame == CGRect(x: 0, y: 64, width: 320, height: 0))
        #expect(!navigation.toolbar.isHidden)

        controller.isActive = true
        scene.layout(in: CGSize(width: 320, height: 480))
        #expect(navigation.navigationBar.frame == CGRect(x: 0, y: 10, width: 320, height: 60))
        #expect(controller.searchBar.frame == CGRect(x: 0, y: 0, width: 320, height: 60) && controller.searchBar.superview === navigation.navigationBar)
        #expect(controller.searchBar.searchTextField.frame == CGRect(x: 16, y: 8, width: 233, height: 44))
        #expect(delegate.presented == [true] && delegate.updates.count == 1)
        #expect(results.viewIfLoaded?.superview == nil)   // no text yet: the content is dimmed, not replaced
        controller.searchBar.text = "Ro"
        scene.layout(in: CGSize(width: 320, height: 480))
        #expect(results.view.superview === navigation.view && results.view.frame == CGRect(x: 0, y: 0, width: 320, height: 480))
        #expect(delegate.updates.last == "Ro")
        controller.searchBar.text = ""
        scene.layout(in: CGSize(width: 320, height: 480))
        #expect(results.view.superview == nil)
        controller.showsSearchResultsController = true
        scene.layout(in: CGSize(width: 320, height: 480))
        #expect(results.view.superview === navigation.view)
        // Cancel dismisses the search; the bar goes back under the title.
        tap(scene, at: CGPoint(x: 282, y: 10 + 30))
        scene.layout(in: CGSize(width: 320, height: 480))
        #expect(!controller.isActive && delegate.presented == [true, false])
        #expect(results.view.superview == nil && navigation.navigationBar.frame.height == 54)
        #expect(controller.searchBar.superview === navigation.view && controller.searchBar.frame.height == 0)
    }
}
