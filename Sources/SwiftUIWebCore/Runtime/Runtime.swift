/// Owns one mounted view tree, its scheduler and (from step 9) the layout and painting
/// pipeline. Hosts (canvas, headless) create one runtime per window.
@MainActor
package final class Runtime {
    package let scheduler = UpdateScheduler()
    package private(set) var root: RootNode!

    /// Environment the root view is mounted in.
    package var rootEnvironment: EnvironmentValues

    package init(environment: EnvironmentValues = EnvironmentValues()) {
        self.rootEnvironment = environment
        self.root = RootNode(runtime: self, environment: environment)
    }

    /// Mounts `view` as the root, replacing any previous root view.
    @discardableResult
    package func mount<V: View>(_ view: V) -> TypedNode<V> {
        root.mount(view)
    }

    /// Applies pending invalidations (top-down by depth). Hosts call this once per frame.
    package func flush() {
        scheduler.flush()
    }
}

/// The parentless node at the top of the tree. Holds the mounted root view's node.
@MainActor
package final class RootNode: ViewNode {
    package private(set) var child: ViewNode?

    package init(runtime: Runtime, environment: EnvironmentValues) {
        super.init(parent: nil, runtime: runtime, environment: environment)
    }

    fileprivate func mount<V: View>(_ view: V) -> TypedNode<V> {
        if let existing = child as? TypedNode<V> {
            existing.update(view: view, environment: environment)
            return existing
        }
        child?.unmount()
        let node = V._makeNode(_NodeContext(view: view, parent: self, environment: environment))
        child = node
        return node
    }

    override package var structuralChildren: [ViewNode] { child.map { [$0] } ?? [] }
    override package var layoutChildren: [ViewNode] { child?.layoutChildren ?? [] }
    override package var nodeDescription: String { "Root" }
}

/// Collects invalidated nodes and updates them in depth order so that a parent's update, which
/// already refreshes its subtree, makes the children's own pending updates unnecessary.
@MainActor
package final class UpdateScheduler {
    private var dirty: [ObjectIdentifier: ViewNode] = [:]

    /// Called the first time work becomes pending after an idle period. Hosts use it to request
    /// an animation frame; headless callers flush explicitly.
    package var onNeedsFlush: (@MainActor () -> Void)?

    /// Number of `flush` calls that did work, for tests.
    package private(set) var flushCount = 0

    package var hasPendingWork: Bool { !dirty.isEmpty }

    package init() {}

    package func schedule(_ node: ViewNode) {
        let wasIdle = dirty.isEmpty
        dirty[ObjectIdentifier(node)] = node
        if wasIdle { onNeedsFlush?() }
    }

    package func flush() {
        guard !dirty.isEmpty else { return }
        flushCount += 1
        var passes = 0
        while !dirty.isEmpty {
            passes += 1
            precondition(passes < 1000, "UpdateScheduler: updates keep invalidating nodes; giving up")
            let batch = dirty.values.sorted { $0.depth < $1.depth }
            dirty.removeAll(keepingCapacity: true)
            for node in batch {
                node.updateIfNeeded()
            }
        }
    }
}
