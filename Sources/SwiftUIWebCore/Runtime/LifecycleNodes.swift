import WebFoundation
import WebCombine
// onAppear/onDisappear and task: transparent nodes that run their actions through the scheduler
// after the update pass that inserted them and when they are unmounted (Docs/elements/Lifecycle.md).

@MainActor
package final class AppearanceActionNode<Content: View>: TypedNode<ModifiedContent<Content, _AppearanceActionModifier>> {
    package private(set) var child: TypedNode<Content>!

    init(_ context: _NodeContext<ModifiedContent<Content, _AppearanceActionModifier>>) {
        super.init(view: context.view, parent: context.parent, runtime: context.runtime, environment: context.environment)
        child = Content._makeNode(_NodeContext(view: context.view.content, parent: self, environment: context.environment))
        if let appear = context.view.modifier.appear {
            runtime.scheduler.enqueue { appear.run() }
        }
    }

    override package func update(view: ModifiedContent<Content, _AppearanceActionModifier>, environment: EnvironmentValues, force: Bool) {
        self.view = view
        self.environment = environment
        clearNeedsUpdate()
        child.update(view: view.content, environment: environment, force: force)
    }

    override package func unmount() {
        if let disappear = view.modifier.disappear {
            runtime.scheduler.enqueue { disappear.run() }
        }
        super.unmount()
    }

    override package var structuralChildren: [ViewNode] { [child] }
    override package var layoutChildren: [ViewNode] { child.layoutChildren }
    override package var nodeDescription: String { "OnAppear" }
}

@MainActor
package final class TaskNode<Content: View>: TypedNode<ModifiedContent<Content, _TaskModifier>> {
    package private(set) var child: TypedNode<Content>!
    package private(set) var task: Task<Void, Never>?

    init(_ context: _NodeContext<ModifiedContent<Content, _TaskModifier>>) {
        super.init(view: context.view, parent: context.parent, runtime: context.runtime, environment: context.environment)
        child = Content._makeNode(_NodeContext(view: context.view.content, parent: self, environment: context.environment))
        start()
    }

    /// Starts the task after the current update pass, like `onAppear`.
    private func start() {
        let modifier = view.modifier
        runtime.scheduler.enqueue { [weak self] in
            guard let self, self.task == nil else { return }
            self.task = Task(priority: modifier.priority) { @MainActor in await modifier.action.run() }
        }
    }

    override package func update(view: ModifiedContent<Content, _TaskModifier>, environment: EnvironmentValues, force: Bool) {
        let idChanged = self.view.modifier.id != view.modifier.id
        self.view = view
        self.environment = environment
        clearNeedsUpdate()
        child.update(view: view.content, environment: environment, force: force)
        if idChanged {
            task?.cancel()
            task = nil
            start()
        }
    }

    override package func unmount() {
        task?.cancel()
        task = nil
        super.unmount()
    }

    override package var structuralChildren: [ViewNode] { [child] }
    override package var layoutChildren: [ViewNode] { child.layoutChildren }
    override package var nodeDescription: String { "Task" }
}

/// `onReceive`: subscribes when mounted, cancels when unmounted.
@MainActor
package final class OnReceiveNode<Content: View>: TypedNode<ModifiedContent<Content, _OnReceiveModifier>> {
    package private(set) var child: TypedNode<Content>!
    private var cancellable: AnyCancellable?

    init(_ context: _NodeContext<ModifiedContent<Content, _OnReceiveModifier>>) {
        super.init(view: context.view, parent: context.parent, runtime: context.runtime, environment: context.environment)
        child = Content._makeNode(_NodeContext(view: context.view.content, parent: self, environment: context.environment))
        let subscribe = context.view.modifier.subscribe
        runtime.scheduler.enqueue { [weak self] in
            guard let self, self.isMounted, self.cancellable == nil else { return }
            self.cancellable = subscribe()
        }
    }

    override package func update(view: ModifiedContent<Content, _OnReceiveModifier>, environment: EnvironmentValues, force: Bool) {
        self.view = view
        self.environment = environment
        clearNeedsUpdate()
        child.update(view: view.content, environment: environment, force: force)
    }

    override package func unmount() {
        cancellable?.cancel()
        cancellable = nil
        super.unmount()
    }

    override package var structuralChildren: [ViewNode] { [child] }
    override package var layoutChildren: [ViewNode] { child.layoutChildren }
    override package var nodeDescription: String { "OnReceive" }
}

/// `onOpenURL`: a handler registered with the runtime while mounted.
@MainActor
package final class OpenURLHandlerNode<Content: View>: TypedNode<ModifiedContent<Content, _OnOpenURLModifier>> {
    package private(set) var child: TypedNode<Content>!

    init(_ context: _NodeContext<ModifiedContent<Content, _OnOpenURLModifier>>) {
        super.init(view: context.view, parent: context.parent, runtime: context.runtime, environment: context.environment)
        child = Content._makeNode(_NodeContext(view: context.view.content, parent: self, environment: context.environment))
        runtime.openURLHandlers.append(WeakNode(node: self))
    }

    override package func update(view: ModifiedContent<Content, _OnOpenURLModifier>, environment: EnvironmentValues, force: Bool) {
        self.view = view
        self.environment = environment
        clearNeedsUpdate()
        child.update(view: view.content, environment: environment, force: force)
    }

    package func handle(_ url: URL) { view.modifier.action(url) }

    override package func unmount() {
        runtime.openURLHandlers.removeAll { $0.node === self || $0.node == nil }
        super.unmount()
    }

    override package var structuralChildren: [ViewNode] { [child] }
    override package var layoutChildren: [ViewNode] { child.layoutChildren }
    override package var nodeDescription: String { "OnOpenURL" }
}

/// `onContinueUserActivity`: a handler registered with the runtime while mounted.
@MainActor
package final class ContinueActivityHandlerNode<Content: View>: TypedNode<ModifiedContent<Content, _OnContinueUserActivityModifier>> {
    package private(set) var child: TypedNode<Content>!

    init(_ context: _NodeContext<ModifiedContent<Content, _OnContinueUserActivityModifier>>) {
        super.init(view: context.view, parent: context.parent, runtime: context.runtime, environment: context.environment)
        child = Content._makeNode(_NodeContext(view: context.view.content, parent: self, environment: context.environment))
        runtime.activityHandlers.append(WeakNode(node: self))
    }

    override package func update(view: ModifiedContent<Content, _OnContinueUserActivityModifier>, environment: EnvironmentValues, force: Bool) {
        self.view = view
        self.environment = environment
        clearNeedsUpdate()
        child.update(view: view.content, environment: environment, force: force)
    }

    package func handle(_ activity: NSUserActivity) -> Bool {
        guard activity.activityType == view.modifier.activityType else { return false }
        view.modifier.action(activity)
        return true
    }

    override package func unmount() {
        runtime.activityHandlers.removeAll { $0.node === self || $0.node == nil }
        super.unmount()
    }

    override package var structuralChildren: [ViewNode] { [child] }
    override package var layoutChildren: [ViewNode] { child.layoutChildren }
    override package var nodeDescription: String { "OnContinueUserActivity" }
}

/// `userActivity`: one activity per mounted view, filled in and made current while active.
@MainActor
package final class UserActivityNode<Content: View>: TypedNode<ModifiedContent<Content, _UserActivityModifier>> {
    package private(set) var child: TypedNode<Content>!
    package private(set) var activity: NSUserActivity?
    package private(set) var isCurrent = false

    init(_ context: _NodeContext<ModifiedContent<Content, _UserActivityModifier>>) {
        super.init(view: context.view, parent: context.parent, runtime: context.runtime, environment: context.environment)
        child = Content._makeNode(_NodeContext(view: context.view.content, parent: self, environment: context.environment))
        runtime.advertisedActivities.append(WeakNode(node: self))
        advertise()
    }

    override package func update(view: ModifiedContent<Content, _UserActivityModifier>, environment: EnvironmentValues, force: Bool) {
        self.view = view
        self.environment = environment
        clearNeedsUpdate()
        child.update(view: view.content, environment: environment, force: force)
        advertise()
    }

    /// The activity, filled in by the view's closure and current while active; resigned otherwise.
    private func advertise() {
        let modifier = view.modifier
        guard modifier.isActive else {
            if isCurrent { activity?.resignCurrent() }
            isCurrent = false
            return
        }
        if activity == nil || activity?.activityType != modifier.activityType {
            activity?.invalidate()
            activity = NSUserActivity(activityType: modifier.activityType)
        }
        guard let activity else { return }
        modifier.update(activity)
        activity.becomeCurrent()
        isCurrent = true
    }

    override package func unmount() {
        activity?.invalidate()
        isCurrent = false
        runtime.advertisedActivities.removeAll { $0.node === self || $0.node == nil }
        super.unmount()
    }

    override package var structuralChildren: [ViewNode] { [child] }
    override package var layoutChildren: [ViewNode] { child.layoutChildren }
    override package var nodeDescription: String { "UserActivity" }
}

@MainActor package protocol _ActivityAdvertising: AnyObject {
    var activity: NSUserActivity? { get }
    var isCurrent: Bool { get }
}
extension UserActivityNode: _ActivityAdvertising {}

extension Runtime {
    /// The current activity of the type a mounted `userActivity` view advertises, innermost last.
    public func currentUserActivity(ofType activityType: String) -> NSUserActivity? {
        var current: NSUserActivity?
        for entry in advertisedActivities {
            guard let node = entry.node as? any _ActivityAdvertising, node.isCurrent,
                  let activity = node.activity, activity.activityType == activityType else { continue }
            current = activity
        }
        return current
    }

    /// Delivers a URL to every mounted `onOpenURL` handler, outermost first.
    public func openURL(_ url: URL) {
        for entry in openURLHandlers { (entry.node as? any _OpenURLHandling)?.handle(url) }
    }

    /// Delivers a user activity to the mounted `onContinueUserActivity` handlers of its type;
    /// returns whether one took it.
    @discardableResult
    public func continueUserActivity(_ activity: NSUserActivity) -> Bool {
        var handled = false
        for entry in activityHandlers { if (entry.node as? any _ActivityHandling)?.handle(activity) == true { handled = true } }
        return handled
    }
}

@MainActor package protocol _OpenURLHandling: AnyObject { func handle(_ url: URL) }
@MainActor package protocol _ActivityHandling: AnyObject { func handle(_ activity: NSUserActivity) -> Bool }
extension OpenURLHandlerNode: _OpenURLHandling {}
extension ContinueActivityHandlerNode: _ActivityHandling {}
