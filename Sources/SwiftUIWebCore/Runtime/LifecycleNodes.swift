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
