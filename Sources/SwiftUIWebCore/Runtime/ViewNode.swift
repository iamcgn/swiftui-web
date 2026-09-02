// The runtime's node tree mirrors the view *type* tree (Docs/ARCHITECTURE.md, invariant 1):
// every view value in a body is represented by one node whose class is chosen statically
// through `View._makeNode`. There is no AttributeGraph and no general diffing; identity is
// structural, and only `ForEach` reconciles by key.

/// A node in the runtime tree. Members are `package`; the class is public only because the
/// hidden `View._makeNode` hook must name it.
@MainActor
open class ViewNode {
    /// The runtime this node belongs to.
    package unowned let runtime: Runtime

    /// The structural parent, `nil` for the root.
    package private(set) weak var parent: ViewNode?

    /// Distance from the root. The scheduler updates dirty nodes top-down by depth.
    package let depth: Int

    /// The environment in which this node's view lives.
    package var environment: EnvironmentValues

    /// Set by `invalidate()`; cleared once the node has been updated.
    package private(set) var needsUpdate = false

    /// False once `unmount()` has run.
    package private(set) var isMounted = true

    package init(parent: ViewNode?, runtime: Runtime, environment: EnvironmentValues) {
        self.runtime = runtime
        self.parent = parent
        self.depth = (parent?.depth ?? -1) + 1
        self.environment = environment
    }

    // MARK: Invalidation

    /// Marks the node dirty and asks the scheduler for a flush.
    package func invalidate() {
        guard isMounted, !needsUpdate else { return }
        needsUpdate = true
        runtime.scheduler.schedule(self)
    }

    /// Re-runs this node's update from its stored view. Called by the scheduler.
    package func updateIfNeeded() {
        guard needsUpdate, isMounted else { return }
        performUpdate()
    }

    /// Subclasses re-evaluate from their stored state. Must call `clearNeedsUpdate()`.
    package func performUpdate() {
        clearNeedsUpdate()
    }

    package func clearNeedsUpdate() {
        needsUpdate = false
    }

    // MARK: Tree

    /// Children in structural order (for debugging and tree-shape tests).
    package var structuralChildren: [ViewNode] { [] }

    /// The nodes this subtree contributes to the enclosing layout container (invariant 2).
    /// Lists (`TupleView`, `Group`, `Optional`, `_ConditionalContent`, environment modifiers)
    /// contribute their children; layout-participating nodes contribute themselves.
    package var layoutChildren: [ViewNode] { [self] }

    /// Short description of the node for tree dumps.
    package var nodeDescription: String {
        String(describing: type(of: self))
    }

    /// Tears the subtree down. Subclasses unmount children first, then call super.
    package func unmount() {
        for child in structuralChildren { child.unmount() }
        isMounted = false
        needsUpdate = false
    }

    /// Indented dump of the subtree, one node per line, for tests and debugging.
    package func dump(indent: Int = 0) -> String {
        var lines = [String(repeating: "  ", count: indent) + nodeDescription]
        for child in structuralChildren {
            lines.append(child.dump(indent: indent + 1))
        }
        return lines.joined(separator: "\n")
    }
}

/// A node whose view type is known statically. `View._makeNode` returns one of these so parents
/// can push new view values to their children without casts.
@MainActor
open class TypedNode<V: View>: ViewNode {
    /// The most recent view value.
    package var view: V

    package init(view: V, parent: ViewNode?, runtime: Runtime, environment: EnvironmentValues) {
        self.view = view
        super.init(parent: parent, runtime: runtime, environment: environment)
    }

    /// Receives a new view value from the parent. `force` is set when the parent knows the
    /// subtree must be re-evaluated regardless of equality (for example after `invalidate()`).
    package func update(view: V, environment: EnvironmentValues, force: Bool = false) {
        self.view = view
        self.environment = environment
        clearNeedsUpdate()
    }

    override package func performUpdate() {
        update(view: view, environment: environment, force: true)
    }

    override package var nodeDescription: String {
        _shortTypeName(type(of: self))
    }
}

/// The information `View._makeNode` receives to build a node.
public struct _NodeContext<V: View> {
    package let view: V
    package let parent: ViewNode
    package let environment: EnvironmentValues

    package init(view: V, parent: ViewNode, environment: EnvironmentValues) {
        self.view = view
        self.parent = parent
        self.environment = environment
    }

    package var runtime: Runtime { parent.runtime }
}

extension View {
    /// Hidden hook: builds the runtime node for a view value and performs its first update.
    /// Composite views get a `CompositeNode`; primitive views override this.
    public static func _makeNode(_ context: _NodeContext<Self>) -> TypedNode<Self> {
        CompositeNode(context)
    }
}

extension Never {
    public static func _makeNode(_ context: _NodeContext<Never>) -> TypedNode<Never> {
        switch context.view {}
    }
}

/// Node for a view with a `body`: evaluates it and keeps one child for `V.Body`.
@MainActor
package final class CompositeNode<V: View>: TypedNode<V> {
    package private(set) var child: TypedNode<V.Body>?

    /// Number of body evaluations, for tests.
    package private(set) var bodyEvaluations = 0

    /// Storage for the view's dynamic properties (`@State` boxes and the like).
    package private(set) var propertyStorage: AnyObject?

    package init(_ context: _NodeContext<V>) {
        super.init(view: context.view, parent: context.parent, runtime: context.runtime,
                   environment: context.environment)
        evaluateBody()
    }

    override package func update(view: V, environment: EnvironmentValues, force: Bool) {
        let changed = force || needsUpdate
            || _valuesDiffer(self.view, view)
            || self.environment.generation != environment.generation
        self.view = view
        self.environment = environment
        clearNeedsUpdate()
        if changed { evaluateBody() }
    }

    private func evaluateBody() {
        bodyEvaluations += 1
        _DynamicPropertyFields<V>.installAll(into: &view, node: self, slot: &propertyStorage)
        let body = view.body
        if let child {
            child.update(view: body, environment: environment)
        } else {
            child = V.Body._makeNode(_NodeContext(view: body, parent: self, environment: environment))
        }
    }

    override package var structuralChildren: [ViewNode] { child.map { [$0] } ?? [] }
    override package var layoutChildren: [ViewNode] { child?.layoutChildren ?? [] }
}

/// Node for a primitive view that participates in layout on its own (Text, Spacer, stacks…).
/// Step 5 adds the layout entry points; until then it only holds the value.
@MainActor
open class LeafNode<V: View>: TypedNode<V> {
    public init(_ context: _NodeContext<V>) {
        super.init(view: context.view, parent: context.parent, runtime: context.runtime,
                   environment: context.environment)
    }
}

// MARK: - Change detection

/// Whether two view values differ. Equatable types compare with `==`; plain-old-data types
/// compare bitwise; anything else (closures, existentials) is assumed to have changed.
package func _valuesDiffer<T>(_ old: T, _ new: T) -> Bool {
    if let equatable = T.self as? any Equatable.Type {
        return !_openEquatable(equatable, old, new)
    }
    if _isPOD(T.self) {
        return withUnsafeBytes(of: old) { a in
            withUnsafeBytes(of: new) { b in
                !a.elementsEqual(b)
            }
        }
    }
    return true
}

private func _openEquatable<E: Equatable>(_: E.Type, _ a: Any, _ b: Any) -> Bool {
    (a as! E) == (b as! E)
}

/// Strips module and private-context qualifiers from a type description, inside generic
/// arguments too: `Module.(unknown context at $1).Outer.Inner<Module.Arg>` → `Inner<Arg>`.
package func _shortTypeName(_ type: Any.Type) -> String {
    let full = Array(String(describing: type))
    var out = ""
    var token = ""
    var index = 0
    func flushToken() {
        if let dot = token.lastIndex(of: ".") {
            out += token[token.index(after: dot)...]
        } else {
            out += token
        }
        token = ""
    }
    while index < full.count {
        let character = full[index]
        if character == "(" {
            // Drop `(unknown context at $…)` and `(extension in Module)` qualifiers entirely.
            if let close = full[index...].firstIndex(of: ")"),
               String(full[index...close]).hasPrefix("(unknown context") ||
               String(full[index...close]).hasPrefix("(extension in")
            {
                index = close + 1
                continue
            }
        }
        if character.isLetter || character.isNumber || character == "_" || character == "." || character == "$" {
            token.append(character)
        } else {
            flushToken()
            out.append(character)
        }
        index += 1
    }
    flushToken()
    return out
}
