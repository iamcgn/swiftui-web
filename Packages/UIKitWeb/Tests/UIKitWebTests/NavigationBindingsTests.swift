// What swift-navigation's UIKit bindings (UIKitNavigation, in EhPanda) build on: an app's own
// traits (Values/UITraitCollection.swift) set on a view controller's `traitOverrides` before its
// view loads and read in its subtree, a text field's selection as `UITextInput` positions
// (Controls/UITextField.swift), and iOS 18 tabs selected by tab (Containers/UITab.swift).
import Testing
import UIKit
@testable import UIKitWebCore
#if canImport(AppKit)
import WebGraphicsNative
#endif
#if os(WASI)
import WebFoundation
#else
import Foundation
#endif

/// swift-navigation's dismiss action: a Sendable closure, so not Equatable.
struct DismissAction: Sendable {
    let run: (@MainActor @Sendable () -> Void)?
}

/// A count a Sendable closure can bump.
private final class Count: @unchecked Sendable { var value = 0 }

private enum DismissActionTrait: UITraitDefinition {
    static let defaultValue = DismissAction(run: nil)
}

/// An Equatable trait: changes are compared.
private enum ScoreTrait: UITraitDefinition {
    static let defaultValue = 0
}

extension UITraitCollection {
    fileprivate var dismiss: DismissAction { self[DismissActionTrait.self] }
    fileprivate var score: Int { self[ScoreTrait.self] }
}

extension UIMutableTraits {
    fileprivate var dismiss: DismissAction {
        get { self[DismissActionTrait.self] }
        set { self[DismissActionTrait.self] = newValue }
    }
    fileprivate var score: Int {
        get { self[ScoreTrait.self] }
        set { self[ScoreTrait.self] = newValue }
    }
}

@Suite @MainActor struct NavigationBindingsTests {
    private func scene() -> (UIKitScene, UIWindow, UIViewController) {
        let scene = UIKitScene.shared
        scene.removeAllWindows()
        #if canImport(AppKit)
        scene.textEngine = CoreTextEngine()
        #else
        scene.textEngine = SyntheticTextEngine()
        #endif
        scene.configureScreen(size: CGSize(width: 320, height: 480), scale: 2)
        let root = UIViewController()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        window.rootViewController = root
        window.makeKeyAndVisible()
        scene.layout(in: CGSize(width: 320, height: 480))
        return (scene, window, root)
    }

    @Test func anAppsTraitsReachTheSubtreeFromAControllersOverrides() {
        let (_, window, root) = scene()
        #expect(UITraitCollection().dismiss.run == nil && UITraitCollection().score == 0)
        #expect(DismissActionTrait.identifier.hasSuffix("DismissActionTrait") && !ScoreTrait.affectsColorAppearance)

        // Set before the view loads, as swift-navigation does when it presents.
        let child = UIViewController()
        let dismissed = Count()
        child.traitOverrides.dismiss = DismissAction { dismissed.value += 1 }
        child.traitOverrides.score = 3
        #expect(child.traitOverrides.contains(ScoreTrait.self) && !child.traitOverrides.contains(UITraitHorizontalSizeClass.self))
        #expect(child.traitCollection.score == 3)
        root.addChild(child)
        root.view.addSubview(child.view)
        child.didMove(toParent: root)
        let label = UILabel()
        child.view.addSubview(label)
        label.traitCollection.dismiss.run?()
        #expect(dismissed.value == 1 && label.traitCollection.score == 3)
        // The parent and the window don't see the child's traits.
        #expect(root.traitCollection.dismiss.run == nil && window.traitCollection.score == 0)

        // A view's own override sits under the controller's; removing it shows the controller's again.
        label.traitOverrides.score = 7
        #expect(label.traitCollection.score == 7 && child.view.traitCollection.score == 3)
        label.traitOverrides.remove(ScoreTrait.self)
        #expect(label.traitCollection.score == 3)

        // UIKit's traits read and set by type too.
        child.traitOverrides[UITraitUserInterfaceStyle.self] = .dark
        #expect(label.traitCollection[UITraitUserInterfaceStyle.self] == .dark && label.traitCollection.userInterfaceStyle == .dark)
        #expect(child.traitOverrides.userInterfaceStyle == .dark && UITraitUserInterfaceStyle.affectsColorAppearance)
        child.traitOverrides.remove(UITraitUserInterfaceStyle.self)
        #expect(child.traitOverrides.userInterfaceStyle == nil)
    }

    @Test func registeredObserversHearAnAppsTraitChange() {
        let (_, _, root) = scene()
        let view = UIView()
        root.view.addSubview(view)
        // Pin the style before observing, so the window's appearance (which other tests may set)
        // neither starts out dark nor changes underneath the observer (issue 203).
        root.traitOverrides[UITraitUserInterfaceStyle.self] = .light
        var scores: [Int] = []
        view.registerForTraitChanges([ScoreTrait.self]) { (view: UIView, _: UITraitCollection) in scores.append(view.traitCollection.score) }
        var styleChanges = 0
        view.registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (_: UIView, _: UITraitCollection) in styleChanges += 1 }
        root.traitOverrides.score = 2
        root.traitOverrides.score = 2   // the same value: nothing changed
        root.traitOverrides.score = 5
        #expect(scores == [2, 5] && styleChanges == 0)
        // A value that isn't Equatable counts as changed each time it's set.
        var dismissals = 0
        view.registerForTraitChanges([DismissActionTrait.self]) { (_: UIView, _: UITraitCollection) in dismissals += 1 }
        root.traitOverrides.dismiss = DismissAction(run: nil)
        root.traitOverrides.dismiss = DismissAction(run: nil)
        #expect(dismissals == 2 && scores == [2, 5])
        // Other traits changing leave it alone: it is the value set, passed down unchanged.
        root.traitOverrides.score = 7
        root.traitOverrides[UITraitUserInterfaceStyle.self] = .dark
        #expect(dismissals == 2 && scores == [2, 5, 7] && styleChanges == 1)
    }

    /// swift-navigation's `textSelection`: the selection as offsets from the start, and back.
    private func selection(of field: UITextField) -> Range<Int>? {
        guard let range = field.selectedTextRange else { return nil }
        return field.offset(from: field.beginningOfDocument, to: range.start)..<field.offset(from: field.beginningOfDocument, to: range.end)
    }

    private func select(_ range: Range<Int>, in field: UITextField) {
        guard let from = field.position(from: field.beginningOfDocument, offset: range.lowerBound),
              let to = field.position(from: field.beginningOfDocument, offset: range.upperBound) else { return }
        field.selectedTextRange = field.textRange(from: from, to: to)
    }

    final class Delegate: UITextFieldDelegate {
        var selectionChanges = 0
        func textFieldDidChangeSelection(_ textField: UITextField) { selectionChanges += 1 }
    }

    @Test func aTextFieldsSelectionIsTheElementsAsPositions() {
        let (scene, _, root) = scene()
        let field = UITextField(frame: CGRect(x: 20, y: 20, width: 280, height: 34))
        let delegate = Delegate()
        field.delegate = delegate
        root.view.addSubview(field)
        #expect(!field.hasText && selection(of: field) == 0..<0)

        // A text the app sets puts the caret at its end.
        field.text = "Hello world"
        #expect(field.hasText && selection(of: field) == 11..<11)
        #expect(field.text(in: field.textRange(from: field.beginningOfDocument, to: field.endOfDocument)!) == "Hello world")
        #expect(field.position(from: field.endOfDocument, offset: 1) == nil)

        // The app selects "world": the host's element is told to.
        select(6..<11, in: field)
        #expect(selection(of: field) == 6..<11)
        #expect(field.semanticsNode()?.textInput?.selection == TextRange(start: 6, end: 11))
        // A text the app sets after that sends the element the caret at its end, not the old selection.
        field.text = "Hello world, and the rest!"
        #expect(selection(of: field) == 26..<26 && field.semanticsNode()?.textInput?.selection == TextRange(start: 26, end: 26))
        field.text = "Hello world"

        // The host reports the caret moving: the field takes it, and the delegate hears.
        scene.textField(field.semanticsIdentifier, selectionStart: 2, end: 4)
        #expect(selection(of: field) == 2..<4 && delegate.selectionChanges == 1)
        #expect(field.semanticsNode()?.textInput?.selection == nil)
        // Typing in the middle keeps the selection the host reports next.
        scene.textField(field.semanticsIdentifier, didChange: "Heyllo world")
        scene.textField(field.semanticsIdentifier, selectionStart: 3, end: 3)
        #expect(field.text == "Heyllo world" && selection(of: field) == 3..<3)

        // Key input from the app types over the selection and reports the edit.
        var edits = 0
        field.addAction(UIAction { _ in edits += 1 }, for: .editingChanged)
        select(0..<3, in: field)
        field.insertText("😀")
        #expect(field.text == "😀llo world" && selection(of: field) == 2..<2 && edits == 1)
        field.deleteBackward()
        #expect(field.text == "llo world" && selection(of: field) == 0..<0 && edits == 2)
        field.deleteBackward()
        #expect(field.text == "llo world" && edits == 2)

        // The caret moves right along the text, and a range's rect spans its characters.
        let start = field.caretRect(for: field.beginningOfDocument), end = field.caretRect(for: field.endOfDocument)
        #expect(end.minX > start.minX && start.width == 2 && start.height > 0)
        let word = field.firstRect(for: field.textRange(from: field.beginningOfDocument, to: field.position(from: field.beginningOfDocument, offset: 3)!)!)
        #expect(word.minX == start.minX && word.width > 0 && word.maxX < end.minX)
        #expect(field.compare(field.beginningOfDocument, to: field.endOfDocument) == .orderedAscending)
    }

    @Test func tabsShowTheirControllersAndSelectByTab() {
        let (_, window, _) = scene()
        var made: [String] = []
        func tab(_ title: String, _ identifier: String) -> UITab {
            UITab(title: title, image: nil, identifier: identifier) { tab in
                made.append(tab.identifier)
                let controller = UIViewController()
                controller.title = tab.title
                return controller
            }
        }
        let library = tab("Library", "library"), search = tab("Search", "search"), settings = tab("Settings", "settings")
        let controller = UITabBarController(tabs: [library, search, settings])
        window.rootViewController = controller
        #expect(controller.tabs.map { $0.identifier } == ["library", "search", "settings"])
        #expect(controller.viewControllers?.count == 3 && controller.tabBar.items?.map { $0.title } == ["Library", "Search", "Settings"])
        #expect(controller.selectedTab === library && library.tabBarController === controller)

        controller.selectedTab = controller.tab(forIdentifier: "settings")
        #expect(controller.selectedIndex == 2 && controller.selectedViewController === settings.viewController)
        #expect(made == ["library", "search", "settings"])

        // A hidden tab leaves the bar; the selected one stays selected.
        search.isHidden = true
        #expect(controller.tabBar.items?.map { $0.title } == ["Library", "Settings"] && controller.selectedTab === settings)
        controller.selectedTab = search
        #expect(controller.selectedTab === settings)
        search.isHidden = false
        search.badgeValue = "3"
        #expect(controller.tabBar.items?[1].badgeValue == "3" && made.count == 3)
        #expect(controller.tab(forIdentifier: "missing") == nil)
    }
}
