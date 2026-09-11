// UIToolbar and UISearchBar (Containers/UIToolbar.swift, Controls/UISearchBar.swift): the
// toolbar places its platters as UIKit does (uikit/toolbar/basic), a tapped item fires once, and
// the search bar edits through the host with its delegate hearing about text, search and cancel.
import Testing
import UIKit
import WebGraphics

@Suite @MainActor struct BarTests {
    private func window() -> (UIWindow, UIViewController) {
        let scene = UIKitScene.shared
        scene.removeAllWindows()
        scene.textEngine = try! Goldens.textEngine()
        scene.configureScreen(size: CGSize(width: 320, height: 500), scale: 2)
        let root = UIViewController()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 500))
        window.rootViewController = root
        window.makeKeyAndVisible()
        scene.layout(in: CGSize(width: 320, height: 500))
        return (window, root)
    }

    @Test func toolbarPlacesItsPlatters() {
        let (_, root) = window()
        let scene = UIKitScene.shared
        let counts = Counts()
        let toolbar = UIToolbar()
        toolbar.items = [
            UIBarButtonItem(title: "Edit", primaryAction: UIAction { _ in counts.taps += 1 }),
            UIBarButtonItem(barButtonSystemItem: .flexibleSpace),
            UIBarButtonItem(barButtonSystemItem: .add),
            UIBarButtonItem(barButtonSystemItem: .fixedSpace),
            UIBarButtonItem(barButtonSystemItem: .trash),
            UIBarButtonItem(barButtonSystemItem: .flexibleSpace),
            UIBarButtonItem(barButtonSystemItem: .action),
        ]
        toolbar.items?[3].width = 24
        toolbar.sizeToFit()
        #expect(toolbar.frame.height == 48)
        toolbar.frame = CGRect(x: 0, y: 452, width: 320, height: 48)
        root.view.addSubview(toolbar)
        scene.layout(in: CGSize(width: 320, height: 500))
        let platters = scene.semanticsTree().filter { $0.role == .button }.sorted { $0.frame.minX < $1.frame.minX }
        #expect(platters.map(\.label) == ["Edit", "plus", "trash", "square.and.arrow.up"])
        let xs = platters.map(\.frame.minX)
        #expect(xs == [16, 97.5, 181.5, 256])
        #expect(platters.map(\.frame.width) == [54.5, 48, 48, 48])
        #expect(platters.allSatisfy { $0.frame.height == 48 })
        guard let edit = platters.first else { return }
        scene.pointerDown(at: CGPoint(x: edit.frame.midX, y: edit.frame.midY), type: .touch, time: 1)
        scene.pointerUp(at: CGPoint(x: edit.frame.midX, y: edit.frame.midY), time: 1.1)
        #expect(counts.taps == 1)
    }

    @Test func toolbarWithoutFlexibleSpacesCentresItsItems() {
        let (_, root) = window()
        let scene = UIKitScene.shared
        let toolbar = UIToolbar()
        toolbar.items = [UIBarButtonItem(barButtonSystemItem: .add)]
        toolbar.sizeToFit()
        #expect(toolbar.frame.size == CGSize(width: 0, height: 48))
        toolbar.frame = CGRect(x: 16, y: 120, width: 0, height: 48)
        root.view.addSubview(toolbar)
        scene.layout(in: CGSize(width: 320, height: 500))
        // The platter overflows the empty bar, centred on it (UIKit places it at -24 in the bar).
        #expect(toolbar.subviews.first?.frame == CGRect(x: -24, y: 0, width: 48, height: 48))
    }

    @Test func searchBarEditsThroughTheHost() {
        let (_, root) = window()
        let scene = UIKitScene.shared
        let bar = UISearchBar()
        bar.placeholder = "Search"
        bar.sizeToFit()
        #expect(bar.frame.height == 64)
        bar.frame = CGRect(x: 0, y: 16, width: 320, height: 64)
        let listener = SearchListener()
        bar.delegate = listener
        root.view.addSubview(bar)
        scene.layout(in: CGSize(width: 320, height: 500))
        #expect(bar.searchTextField.frame == CGRect(x: 8, y: 10, width: 304, height: 44))
        guard let field = scene.semanticsTree().first(where: { $0.textInput != nil }) else { Issue.record("no field"); return }
        #expect(field.textInput?.placeholder == "Search")
        #expect(field.textInput?.textRect.minX == 47.5)
        scene.pointerDown(at: CGPoint(x: 160, y: 48), type: .touch, time: 1)
        scene.pointerUp(at: CGPoint(x: 160, y: 48), time: 1.1)
        #expect(bar.isFirstResponder)
        #expect(listener.began == 1)
        scene.textField(field.identifier, didChange: "Swi")
        #expect(bar.text == "Swi")
        #expect(listener.changes == ["Swi"])
        scene.textFieldDidSubmit(field.identifier)
        #expect(listener.searched == 1)
        bar.showsCancelButton = true
        scene.layout(in: CGSize(width: 320, height: 500))
        #expect(bar.searchTextField.frame.width == 249)
        guard let cancel = scene.semanticsTree().first(where: { $0.label == "Cancel" }) else { Issue.record("no cancel"); return }
        #expect(cancel.frame == CGRect(x: 268, y: 26, width: 44, height: 44))
        scene.pointerDown(at: CGPoint(x: cancel.frame.midX, y: cancel.frame.midY), type: .touch, time: 2)
        scene.pointerUp(at: CGPoint(x: cancel.frame.midX, y: cancel.frame.midY), time: 2.1)
        #expect(listener.cancelled == 1)
        #expect(!bar.isFirstResponder)
        #expect(listener.ended == 1)
    }
}

@MainActor
private final class Counts {
    var taps = 0
}

@MainActor
private final class SearchListener: UISearchBarDelegate {
    var began = 0, ended = 0, searched = 0, cancelled = 0
    var changes: [String] = []
    func searchBarTextDidBeginEditing(_ searchBar: UISearchBar) { began += 1 }
    func searchBarTextDidEndEditing(_ searchBar: UISearchBar) { ended += 1 }
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) { changes.append(searchText) }
    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) { searched += 1 }
    func searchBarCancelButtonClicked(_ searchBar: UISearchBar) { cancelled += 1 }
}
