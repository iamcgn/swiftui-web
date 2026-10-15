// Hardware keyboard and the focus system (uk-keyboard): key commands on the responder chain,
// presses down the chain, Tab and Shift-Tab through the focusable views with the ring, the
// arrows through a table's rows (selection following focus), Space activating a control.
import Testing
import UIKitWebCore
#if os(WASI)
import WebFoundation
#else
import Foundation
#endif

@MainActor final class KeyLog { var events: [String] = [] }

final class CommandController: UIViewController {
    let log: KeyLog
    init(log: KeyLog) { self.log = log; super.init(nibName: nil, bundle: nil) }
    override var keyCommands: [UIKeyCommand]? {
        [UIKeyCommand(title: "Save", action: { [log] _ in log.events.append("save") }, input: "s", modifierFlags: .command),
         UIKeyCommand(title: "New", action: { [log] _ in log.events.append("new") }, input: "N", modifierFlags: .command),
         UIKeyCommand(input: UIKeyCommand.inputEscape, modifierFlags: []) { [log] _ in log.events.append("escape") }]
    }
    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if let key = presses.first?.key, key.characters == "x" { log.events.append("x began"); return }
        super.pressesBegan(presses, with: event)
    }
    override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
        log.events.append("focus \(context.previouslyFocusedView.map { _ in "view" } ?? "nil") -> \(context.nextFocusedView.map { _ in "view" } ?? "nil")")
    }
}

final class RowsSource: NSObject, UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { 3 }
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "row") ?? UITableViewCell(style: .default, reuseIdentifier: "row")
        cell.textLabel?.text = "Row \(indexPath.row)"
        return cell
    }
}

@Suite @MainActor struct KeyboardTests {
    private func key(_ key: KeyEquivalent, _ characters: String = "", _ modifiers: EventModifiers = []) -> KeyEvent {
        KeyEvent(key: key, characters: characters, modifiers: modifiers)
    }

    @Test func commandsPressesFocusAndActivation() {
        let scene = UIKitScene.shared
        scene.removeAllWindows()
        scene.configureScreen(size: CGSize(width: 320, height: 400), scale: 2)
        let log = KeyLog()
        let controller = CommandController(log: log)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 400))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        var pressed = 0
        let first = UIButton(type: .system, primaryAction: UIAction(title: "First") { _ in pressed += 1 })
        first.frame = CGRect(x: 20, y: 20, width: 100, height: 32)
        let second = UIButton(type: .system, primaryAction: UIAction(title: "Second") { _ in })
        second.frame = CGRect(x: 140, y: 20, width: 100, height: 32)
        let disabled = UIButton(type: .system, primaryAction: UIAction(title: "Off") { _ in })
        disabled.frame = CGRect(x: 20, y: 70, width: 100, height: 32)
        disabled.isEnabled = false
        let table = UITableView(frame: CGRect(x: 0, y: 120, width: 320, height: 200), style: .plain)
        table.rowHeight = 44
        let source = RowsSource()
        table.dataSource = source
        table.selectionFollowsFocus = true
        for view in [first, second, disabled, table] { controller.view.addSubview(view) }
        scene.layout(in: CGSize(width: 320, height: 400))
        // Key commands on the responder chain (the controller's) run on their keys alone.
        #expect(scene.keyDown(key(KeyEquivalent("s"), "s", .command)) && log.events == ["save"])
        #expect(scene.keyDown(key(.escape)) && log.events.last == "escape")
        #expect(!scene.keyDown(key(KeyEquivalent("s"), "s")), "the bare key is not the command")
        #expect(scene.keyDown(key(KeyEquivalent("n"), "n", .command)) && log.events.last == "new", "a capital-letter input matches the key as UIKit's does")
        #expect(!scene.keyDown(key(KeyEquivalent("n"), "N", [.command, .shift])), "Shift is a modifier, not the capital")
        // A press the controller takes is handled; one nobody takes is not.
        #expect(scene.keyDown(key(KeyEquivalent("x"), "x")) && log.events.last == "x began")
        #expect(!scene.keyDown(key(KeyEquivalent("y"), "y")))
        // Tab moves focus through the enabled controls and the table's rows in reading order,
        // showing the ring; Shift-Tab goes back; the disabled button is skipped.
        #expect(scene.focusSystem.focusedItem == nil)
        #expect(scene.keyDown(key(.tab)))
        #expect(first.isFocused && scene.focusSystem.showsFocusRing && log.events.last == "focus nil -> view")
        #expect(scene.render(scale: 2).commands.map(\.description).contains { $0.hasPrefix("strokePath") && $0.contains("#007AFF") }, "the focus ring")
        #expect(scene.keyDown(key(.tab)) && second.isFocused)
        #expect(scene.keyDown(key(.tab)) && (scene.focusSystem.focusedItem as? UITableViewCell) === table.cellForRow(at: IndexPath(row: 0, section: 0)))
        #expect(table.indexPathForSelectedRow == IndexPath(row: 0, section: 0), "selection follows focus")
        // The arrows walk the rows.
        #expect(scene.keyDown(key(.downArrow)) && table.indexPathForSelectedRow == IndexPath(row: 1, section: 0))
        #expect(scene.keyDown(key(.downArrow)) && table.indexPathForSelectedRow == IndexPath(row: 2, section: 0))
        #expect(scene.keyDown(key(.downArrow)) && table.indexPathForSelectedRow == IndexPath(row: 2, section: 0), "the last row stays")
        #expect(scene.keyDown(key(.upArrow)) && table.indexPathForSelectedRow == IndexPath(row: 1, section: 0))
        // Shift-Tab back to the second row? No: back to the previous focusable, row 0.
        #expect(scene.keyDown(key(.tab, "", .shift)) && table.indexPathForSelectedRow == IndexPath(row: 0, section: 0))
        #expect(scene.keyDown(key(.tab, "", .shift)) && second.isFocused)
        #expect(scene.keyDown(key(.tab, "", .shift)) && first.isFocused)
        // Space activates the focused control; a touch hides the ring.
        #expect(scene.keyDown(key(.space, " ")) && pressed == 1)
        scene.pointerDown(at: CGPoint(x: 300, y: 390), type: .mouse, time: 1)
        scene.pointerUp(at: CGPoint(x: 300, y: 390), time: 1.1)
        #expect(!scene.focusSystem.showsFocusRing)
        // Programmatic focus.
        scene.focusSystem.requestFocusUpdate(to: second)
        second.updateFocusIfNeeded()
        #expect(second.isFocused)
        scene.removeAllWindows()
    }
}
