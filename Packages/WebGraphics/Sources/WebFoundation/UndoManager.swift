// `UndoManager` for wasm and Linux, whose Foundations lack it (SwiftUI's `undoManager` environment
// value, Core Data and document apps). Registrations go into groups; a group is one undo step.
// `undo()` runs the top group's actions newest first, and the actions they register go to the
// redo stack; `redo()` does the same the other way. With `groupsByEvent` on (the default), a
// registration outside any group opens one that closes on the main actor's next turn, as
// Foundation's closes at the end of the run loop pass. Selector and invocation registration
// (`registerUndo(withTarget:selector:object:)`, `prepare(withInvocationTarget:)`) is not kept:
// there is no Objective-C runtime to send them through.
#if !canImport(Darwin)
#if !os(WASI)
import Foundation
#endif

extension Notification.Name {
    public static let NSUndoManagerCheckpoint = Notification.Name("NSUndoManagerCheckpointNotification")
    public static let NSUndoManagerWillUndoChange = Notification.Name("NSUndoManagerWillUndoChangeNotification")
    public static let NSUndoManagerWillRedoChange = Notification.Name("NSUndoManagerWillRedoChangeNotification")
    public static let NSUndoManagerDidUndoChange = Notification.Name("NSUndoManagerDidUndoChangeNotification")
    public static let NSUndoManagerDidRedoChange = Notification.Name("NSUndoManagerDidRedoChangeNotification")
    public static let NSUndoManagerDidOpenUndoGroup = Notification.Name("NSUndoManagerDidOpenUndoGroupNotification")
    public static let NSUndoManagerWillCloseUndoGroup = Notification.Name("NSUndoManagerWillCloseUndoGroupNotification")
    public static let NSUndoManagerDidCloseUndoGroup = Notification.Name("NSUndoManagerDidCloseUndoGroupNotification")
}

open class UndoManager: NSObject, @unchecked Sendable {
    /// One registered action, kept with its target so `removeAllActions(withTarget:)` can find it.
    private struct Action {
        let target: AnyObject
        let perform: @MainActor (AnyObject) -> Void
    }

    /// What a group holds: an action, or a nested group that closed inside it.
    private enum Item {
        case action(Action)
        case group(Group)
    }

    /// One undo step: its actions and the groups nested in it, in the order they were
    /// registered, and its name. A nested group stays whole so `undoNestedGroup()` can undo it
    /// while the group around it is still open.
    private final class Group {
        var items: [Item] = []
        var name = ""
        var isDiscardable = false

        var hasActions: Bool {
            items.contains {
                if case .group(let nested) = $0 { return nested.hasActions }
                return true
            }
        }

        /// Runs the actions newest first, a nested group's as one.
        @MainActor func performNewestFirst() {
            for item in items.reversed() {
                switch item {
                case .action(let action): action.perform(action.target)
                case .group(let nested): nested.performNewestFirst()
                }
            }
        }

        /// Drops the actions registered with `object`, and any nested group left empty.
        func strip(_ object: AnyObject) {
            for case .group(let nested) in items { nested.strip(object) }
            items.removeAll {
                switch $0 {
                case .action(let action): return action.target === object
                case .group(let nested): return !nested.hasActions
                }
            }
        }
    }

    private var undoStack: [Group] = []
    private var redoStack: [Group] = []
    /// The groups opened and not yet closed, outermost first.
    private var openGroups: [Group] = []
    private var disableCount = 0
    private var closesOnNextTurn = false

    /// Whether a registration outside a group opens one that closes after the current turn.
    open var groupsByEvent = true
    /// How many undo steps are kept (0: no limit); the oldest go first.
    open var levelsOfUndo = 0 {
        didSet { trim(&undoStack); trim(&redoStack) }
    }
    open var runLoopModes: [RunLoop.Mode] = [.default]
    open private(set) var isUndoing = false
    open private(set) var isRedoing = false

    public override init() { super.init() }

    /// How many groups are open.
    open var groupingLevel: Int { openGroups.count }

    open var isUndoRegistrationEnabled: Bool { disableCount == 0 }

    open func disableUndoRegistration() { disableCount += 1 }

    open func enableUndoRegistration() {
        if disableCount > 0 { disableCount -= 1 }
    }

    open func beginUndoGrouping() {
        if openGroups.isEmpty { post(.NSUndoManagerCheckpoint) }
        openGroups.append(Group())
        post(.NSUndoManagerDidOpenUndoGroup)
    }

    open func endUndoGrouping() {
        guard let group = openGroups.popLast() else { return }
        post(.NSUndoManagerWillCloseUndoGroup)
        if let outer = openGroups.last {
            // A nested group belongs to the group around it, and stays whole inside it.
            if group.hasActions { outer.items.append(.group(group)) }
            if outer.name.isEmpty { outer.name = group.name }
        } else if group.hasActions {
            if isUndoing {
                push(group, onto: &redoStack)
            } else if isRedoing {
                push(group, onto: &undoStack)
            } else {
                push(group, onto: &undoStack)
                redoStack.removeAll()
            }
        }
        post(.NSUndoManagerDidCloseUndoGroup)
    }

    /// Registers `handler` to run on `target` when the current group is undone.
    open func registerUndo<TargetType: AnyObject>(withTarget target: TargetType, handler: @escaping @MainActor (TargetType) -> Void) {
        guard isUndoRegistrationEnabled else { return }
        if openGroups.isEmpty {
            guard groupsByEvent else { return }
            beginUndoGrouping()
            closeOnNextTurn()
        }
        // A new change, not one an undo or redo makes, ends what could be redone at once, before
        // its group closes.
        if !isUndoing && !isRedoing { redoStack.removeAll() }
        openGroups[openGroups.count - 1].items.append(.action(Action(target: target) { handler($0 as! TargetType) }))
    }

    /// Names the open group, or the step on top of the stack the next registration goes to.
    open func setActionName(_ actionName: String) {
        if let group = openGroups.last {
            group.name = actionName
        } else if isUndoing, let group = redoStack.last {
            group.name = actionName
        } else if let group = undoStack.last {
            group.name = actionName
        }
    }

    open func setActionIsDiscardable(_ discardable: Bool) {
        (openGroups.last ?? undoStack.last)?.isDiscardable = discardable
    }

    open var canUndo: Bool {
        !undoStack.isEmpty || openGroups.contains { $0.hasActions }
    }

    open var canRedo: Bool { !redoStack.isEmpty }

    open var undoActionName: String {
        openGroups.first(where: { $0.hasActions })?.name ?? undoStack.last?.name ?? ""
    }

    open var redoActionName: String { redoStack.last?.name ?? "" }

    open var undoActionIsDiscardable: Bool { undoStack.last?.isDiscardable ?? false }
    open var redoActionIsDiscardable: Bool { redoStack.last?.isDiscardable ?? false }

    open var undoMenuItemTitle: String { undoMenuTitle(forUndoActionName: undoActionName) }
    open var redoMenuItemTitle: String { redoMenuTitle(forUndoActionName: redoActionName) }

    open func undoMenuTitle(forUndoActionName actionName: String) -> String {
        actionName.isEmpty ? "Undo" : "Undo " + actionName
    }

    open func redoMenuTitle(forUndoActionName actionName: String) -> String {
        actionName.isEmpty ? "Redo" : "Redo " + actionName
    }

    /// Closes the group a registration opened by itself, then undoes the top step.
    @MainActor open func undo() {
        if groupsByEvent, openGroups.count == 1 { endUndoGrouping() }
        guard openGroups.isEmpty else { return }
        undoNestedGroup()
    }

    /// Undoes the last group: the top step, or, while a group is open, the group that last
    /// closed inside it. Its actions run newest first, and what they register becomes the step
    /// `redo()` performs.
    @MainActor open func undoNestedGroup() {
        let group: Group
        if let open = openGroups.last {
            guard case .group(let nested)? = open.items.last else { return }
            open.items.removeLast()
            group = nested
        } else {
            guard let top = undoStack.popLast() else { return }
            group = top
        }
        post(.NSUndoManagerCheckpoint)
        post(.NSUndoManagerWillUndoChange)
        isUndoing = true
        perform(group)
        isUndoing = false
        post(.NSUndoManagerDidUndoChange)
    }

    /// Performs the step the last undo registered.
    @MainActor open func redo() {
        guard openGroups.isEmpty, let group = redoStack.popLast() else { return }
        post(.NSUndoManagerCheckpoint)
        post(.NSUndoManagerWillRedoChange)
        isRedoing = true
        perform(group)
        isRedoing = false
        post(.NSUndoManagerDidRedoChange)
    }

    /// Runs `group` inside a top-level group of its own, so what it registers lands on the
    /// redo stack (undoing) or the undo stack (redoing), even while the caller has groups open.
    @MainActor private func perform(_ group: Group) {
        let outer = openGroups
        openGroups = []
        beginUndoGrouping()
        openGroups[0].name = group.name
        group.performNewestFirst()
        endUndoGrouping()
        openGroups = outer
    }

    open func removeAllActions() {
        undoStack.removeAll()
        redoStack.removeAll()
        openGroups.removeAll()
    }

    /// Removes the actions registered with `target`, and any step left empty.
    open func removeAllActions(withTarget target: Any) {
        let object = target as AnyObject
        func strip(_ stack: inout [Group]) {
            for group in stack { group.strip(object) }
            stack.removeAll { !$0.hasActions }
        }
        strip(&undoStack)
        strip(&redoStack)
        for group in openGroups { group.strip(object) }
    }

    private func push(_ group: Group, onto stack: inout [Group]) {
        stack.append(group)
        trim(&stack)
    }

    private func trim(_ stack: inout [Group]) {
        if levelsOfUndo > 0, stack.count > levelsOfUndo { stack.removeFirst(stack.count - levelsOfUndo) }
    }

    private func closeOnNextTurn() {
        guard !closesOnNextTurn else { return }
        closesOnNextTurn = true
        Task { @MainActor in
            self.closesOnNextTurn = false
            if self.groupsByEvent, self.openGroups.count == 1 { self.endUndoGrouping() }
        }
    }

    private func post(_ name: Notification.Name) {
        NotificationCenter.default.post(name: name, object: self)
    }
}
#endif
