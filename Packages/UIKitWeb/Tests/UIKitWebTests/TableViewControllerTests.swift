// uk-table-controller (Containers/UITableViewController.swift, App/StatusBarAndSizeTransitions.swift):
// a table view controller subclass overrides the data source and delegate methods it is, a
// tap reaches its didSelectRowAt and the next appearance clears the selection; a window resize
// is a size transition the controller hears before the new size, whose alongside blocks and
// completions run after it; the status bar preferences, the scene's status bar manager and the
// iOS 9 `openURL(_:)` answer as UIKit's do; a custom sheet detent reads its resolution context.
import Testing
import UIKit
@testable import UIKitWebCore

@MainActor private final class FruitList: UITableViewController {
    let fruits = ["Apple", "Banana", "Cherry"]
    var picked: [IndexPath] = []
    var transitions: [String] = []

    init() { super.init(style: .grouped) }
    required init?(coder: NSCoder) { nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.register(UITableViewCell.classForCoder(), forCellReuseIdentifier: "fruit")
    }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { fruits.count }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "fruit", for: indexPath)
        cell.textLabel?.text = fruits[indexPath.row]
        return cell
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) { picked.append(indexPath) }

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        transitions.append("will \(Int(size.width))x\(Int(size.height)) from \(Int(view.bounds.width))")
        #expect(transitionCoordinator != nil)
        coordinator.animate(alongsideTransition: { [unowned self] context in
            transitions.append("alongside at \(Int(view.bounds.width)) animated \(context.isAnimated)")
        }, completion: { [unowned self] context in
            transitions.append("done cancelled \(context.isCancelled)")
        })
    }
}

@Suite @MainActor struct TableViewControllerTests {
    private func host(_ controller: UIViewController) -> UIKitScene {
        let scene = UIKitScene.shared
        scene.removeAllWindows()
        scene.textEngine = try! Goldens.textEngine()
        scene.configureScreen(size: CGSize(width: 320, height: 480), scale: 2)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        scene.layout(in: CGSize(width: 320, height: 480))
        return scene
    }

    @Test func aSubclassIsItsTablesSourceAndDelegate() {
        let list = FruitList()
        let scene = host(list)
        #expect(list.tableView.style == .grouped)
        #expect(list.tableView.dataSource === list && list.tableView.delegate === list)
        #expect(list.tableView.visibleCells.compactMap { $0.textLabel?.text } == ["Apple", "Banana", "Cherry"])

        // A tap on the second row reaches the subclass's didSelectRowAt and selects the row.
        let cell = list.tableView.cellForRow(at: IndexPath(row: 1, section: 0))!
        let centre = cell.convert(CGPoint(x: cell.bounds.midX, y: cell.bounds.midY), to: nil)
        scene.pointerDown(at: centre, type: .touch, time: 0)
        scene.pointerUp(at: centre, time: 0.05)
        _ = scene.advanceFrame(elapsed: 0.5)
        #expect(list.picked == [IndexPath(row: 1, section: 0)])
        #expect(list.tableView.indexPathForSelectedRow == IndexPath(row: 1, section: 0))

        // The next appearance clears it, unless the controller keeps selections.
        list.viewWillAppear(false)
        #expect(list.tableView.indexPathForSelectedRow == nil)
        list.clearsSelectionOnViewWillAppear = false
        list.tableView.selectRow(at: IndexPath(row: 0, section: 0), animated: false, scrollPosition: .none)
        list.viewWillAppear(false)
        #expect(list.tableView.indexPathForSelectedRow == IndexPath(row: 0, section: 0))

        // A plain controller with no rows shows an empty plain table.
        let empty = UITableViewController()
        _ = host(empty)
        #expect(empty.tableView.style == .plain && empty.tableView.visibleCells.isEmpty)
    }

    @Test func aResizeIsASizeTransition() {
        let list = FruitList()
        let scene = host(list)
        #expect(list.transitions.isEmpty)
        scene.layout(in: CGSize(width: 480, height: 320))
        #expect(list.transitions == ["will 480x320 from 320", "alongside at 480 animated false", "done cancelled false"])
        #expect(list.transitionCoordinator == nil)
        // The same size again is no transition.
        scene.layout(in: CGSize(width: 480, height: 320))
        #expect(list.transitions.count == 3)
    }

    @Test func statusBarAndOpenURL() {
        let plain = UIViewController()
        #expect(plain.preferredStatusBarStyle == .default && !plain.prefersStatusBarHidden && plain.childForStatusBarStyle == nil)
        #expect(FruitList().preferredStatusBarStyle == .lightContent)
        let scene = host(plain)
        let manager = scene.windowScene.statusBarManager
        #expect(manager === scene.windowScene.statusBarManager)
        #expect(manager?.statusBarFrame == CGRect(x: 0, y: 0, width: 320, height: UIScreen.main.safeAreaInsets.top))

        var opened: [String] = []
        scene.openURL = { opened.append($0) }
        defer { scene.openURL = nil }
        #expect(UIApplication.shared.openURL(URL(string: "https://example.com/a")!))
        #expect(!UIApplication.shared.openURL(URL(string: UIApplication.openSettingsURLString)!))
        #expect(opened == ["https://example.com/a"])
        #if !canImport(Darwin)
        #expect(UIApplication.value(forKey: "sharedApplication") as? UIApplication === UIApplication.shared)
        #expect(UIApplication.value(forKey: "delegate") == nil)
        #endif
    }

    @Test func customDetentsReadTheirContext() {
        // RevenueCat's debug sheet: `.custom { context in context.maximumDetentValue * 0.5 }`.
        let half = UISheetPresentationController.Detent.custom { context in context.maximumDetentValue * 0.5 }
        let context = _DetentResolutionContext(maximumDetentValue: 600, containerTraitCollection: UIScreen.main.traitCollection)
        #expect(half.resolvedValue(in: context) == 300)
        #expect(UISheetPresentationController.Detent.medium().resolvedValue(in: context) == 300)
        #expect(UISheetPresentationController.Detent.large().resolvedValue(in: context) == 600)
    }
}
