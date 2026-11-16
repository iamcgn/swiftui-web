// UndoManager as document and Core Data apps and SwiftUI's `undoManager` use it: named steps,
// undo then redo, nested groups, the levels kept and disabled registration. The cases run
// against Foundation's on Apple platforms and WebFoundation's on wasm and Linux, with explicit
// groups (no run loop turns here to close the groups an event opens).
import Testing
import WebFoundation

private final class Count: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func add() { lock.lock(); value += 1; lock.unlock() }
    var total: Int { lock.lock(); defer { lock.unlock() }; return value }
}

/// A value whose every change registers its inverse, as an app's model does.
@MainActor private final class Box {
    let manager: UndoManager
    private(set) var value = 0
    init(_ manager: UndoManager) { self.manager = manager }
    func set(_ newValue: Int) {
        let old = value
        value = newValue
        manager.registerUndo(withTarget: self) { box in MainActor.assumeIsolated { box.set(old) } }
    }
}

@Suite @MainActor struct UndoManagerTests {
    private func manager() -> UndoManager {
        let manager = UndoManager()
        manager.groupsByEvent = false
        return manager
    }

    private func step(_ manager: UndoManager, _ name: String, _ change: () -> Void) {
        manager.beginUndoGrouping()
        change()
        manager.setActionName(name)
        manager.endUndoGrouping()
    }

    @Test func namedStepsUndoAndRedo() {
        let manager = manager()
        let box = Box(manager)
        #expect(!manager.canUndo && !manager.canRedo)
        #expect(manager.undoMenuItemTitle == "Undo" && manager.redoMenuItemTitle == "Redo")
        step(manager, "One") { box.set(1) }
        step(manager, "Two") { box.set(2) }
        #expect(manager.canUndo && !manager.canRedo)
        #expect(manager.undoActionName == "Two" && manager.undoMenuItemTitle == "Undo Two")
        manager.undo()
        #expect(box.value == 1)
        #expect(manager.canRedo && manager.redoActionName == "Two" && manager.redoMenuItemTitle == "Redo Two")
        #expect(manager.undoActionName == "One")
        manager.redo()
        #expect(box.value == 2 && manager.undoActionName == "Two" && !manager.canRedo)
        manager.undo()
        manager.undo()
        #expect(box.value == 0 && !manager.canUndo && manager.redoActionName == "One")
        // A new step after undoing drops what could be redone.
        step(manager, "Five") { box.set(5) }
        #expect(!manager.canRedo && manager.undoActionName == "Five")
    }

    @Test func nestedGroupsAreOneStep() {
        let manager = manager()
        let box = Box(manager)
        manager.beginUndoGrouping()
        manager.beginUndoGrouping()
        #expect(manager.groupingLevel == 2)
        box.set(1)
        manager.endUndoGrouping()
        box.set(2)
        manager.endUndoGrouping()
        #expect(manager.groupingLevel == 0)
        manager.undo()
        #expect(box.value == 0 && !manager.canUndo)
        manager.redo()
        #expect(box.value == 2)
    }

    @Test func levelsOfUndoKeepTheNewestSteps() {
        let manager = manager()
        manager.levelsOfUndo = 2
        let box = Box(manager)
        step(manager, "One") { box.set(1) }
        step(manager, "Two") { box.set(2) }
        step(manager, "Three") { box.set(3) }
        manager.undo()
        manager.undo()
        #expect(box.value == 1 && !manager.canUndo)
    }

    @Test func disabledRegistrationRecordsNothing() {
        let manager = manager()
        let box = Box(manager)
        manager.disableUndoRegistration()
        #expect(!manager.isUndoRegistrationEnabled)
        step(manager, "Hidden") { box.set(1) }
        #expect(!manager.canUndo)
        manager.enableUndoRegistration()
        #expect(manager.isUndoRegistrationEnabled)
        step(manager, "Shown") { box.set(2) }
        manager.undo()
        #expect(box.value == 1)
    }

    @Test func undoAndRedoPostTheirNotifications() {
        let manager = manager()
        let box = Box(manager)
        let undone = Count(), redone = Count()
        let center = NotificationCenter.default
        let a = center.addObserver(forName: .NSUndoManagerDidUndoChange, object: manager, queue: nil) { _ in undone.add() }
        let b = center.addObserver(forName: .NSUndoManagerDidRedoChange, object: manager, queue: nil) { _ in redone.add() }
        step(manager, "One") { box.set(1) }
        manager.undo()
        manager.redo()
        manager.undo()
        center.removeObserver(a)
        center.removeObserver(b)
        #expect(undone.total == 2 && redone.total == 1)
    }
}
