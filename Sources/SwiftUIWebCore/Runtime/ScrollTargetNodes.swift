// The transparent nodes of the scroll position, target layout, geometry and phase modifiers
// (API/ScrollTargets.swift). A scroll view finds the observers and the position binding by
// walking its ancestors up to the enclosing scroll view; the target layout is found below it.

/// Node for `onScrollGeometryChange`: derives the value from each published geometry and queues
/// the action when it changes. The first publication runs the action with the value of an empty
/// geometry, then with the first real one when it differs (`scroll/geometry`: two calls at rest).
@MainActor
package final class ScrollGeometryChangeNode<Content: View, Value: Equatable>: TypedNode<ModifiedContent<Content, _ScrollGeometryChangeModifier<Value>>>, _ScrollGeometryObserving {
    package private(set) var child: TypedNode<Content>!
    private var last: Value?

    init(_ context: _NodeContext<ModifiedContent<Content, _ScrollGeometryChangeModifier<Value>>>) {
        super.init(view: context.view, parent: context.parent, runtime: context.runtime, environment: context.environment)
        child = Content._makeNode(_NodeContext(view: context.view.content, parent: self, environment: context.environment))
    }

    override package func update(view: ModifiedContent<Content, _ScrollGeometryChangeModifier<Value>>, environment: EnvironmentValues, force: Bool) {
        self.view = view
        self.environment = environment
        clearNeedsUpdate()
        child.update(view: view.content, environment: environment, force: force)
    }

    package func scrollGeometryDidChange(_ geometry: ScrollGeometry) {
        let modifier = view.modifier
        if last == nil {
            let initial = modifier.transform(ScrollGeometry(contentOffset: .zero, contentSize: .zero, contentInsets: EdgeInsets(), containerSize: .zero))
            last = initial
            runtime.scheduler.enqueue { modifier.action(initial, initial) }
        }
        let value = modifier.transform(geometry)
        guard let previous = last, previous != value else { return }
        last = value
        runtime.scheduler.enqueue { modifier.action(previous, value) }
    }

    override package var structuralChildren: [ViewNode] { [child] }
    override package var layoutChildren: [ViewNode] { child.layoutChildren }
    override package var nodeDescription: String { "OnScrollGeometryChange" }
}

/// Node for `onScrollPhaseChange`: queues the action for each phase change it is told about.
@MainActor
package final class ScrollPhaseChangeNode<Content: View>: TypedNode<ModifiedContent<Content, _ScrollPhaseChangeModifier>>, _ScrollPhaseObserving {
    package private(set) var child: TypedNode<Content>!

    init(_ context: _NodeContext<ModifiedContent<Content, _ScrollPhaseChangeModifier>>) {
        super.init(view: context.view, parent: context.parent, runtime: context.runtime, environment: context.environment)
        child = Content._makeNode(_NodeContext(view: context.view.content, parent: self, environment: context.environment))
    }

    override package func update(view: ModifiedContent<Content, _ScrollPhaseChangeModifier>, environment: EnvironmentValues, force: Bool) {
        self.view = view
        self.environment = environment
        clearNeedsUpdate()
        child.update(view: view.content, environment: environment, force: force)
    }

    package func scrollPhaseDidChange(from old: ScrollPhase, to new: ScrollPhase, context: ScrollPhaseChangeContext) {
        let action = view.modifier.action
        runtime.scheduler.enqueue { action(old, new, context) }
    }

    override package var structuralChildren: [ViewNode] { [child] }
    override package var layoutChildren: [ViewNode] { child.layoutChildren }
    override package var nodeDescription: String { "OnScrollPhaseChange" }
}

/// Node for `scrollPosition`: holds the binding for the scroll view below.
@MainActor
package final class ScrollPositionNode<Content: View>: TypedNode<ModifiedContent<Content, _ScrollPositionModifier>>, _ScrollPositioning {
    package private(set) var child: TypedNode<Content>!

    init(_ context: _NodeContext<ModifiedContent<Content, _ScrollPositionModifier>>) {
        super.init(view: context.view, parent: context.parent, runtime: context.runtime, environment: context.environment)
        child = Content._makeNode(_NodeContext(view: context.view.content, parent: self, environment: context.environment))
    }

    override package func update(view: ModifiedContent<Content, _ScrollPositionModifier>, environment: EnvironmentValues, force: Bool) {
        self.view = view
        self.environment = environment
        clearNeedsUpdate()
        child.update(view: view.content, environment: environment, force: force)
    }

    package var positionAnchor: UnitPoint? { view.modifier.anchor }
    package var currentPosition: ScrollPosition { view.modifier.read() }
    package func userScrolled(to id: AnyHashable?) { view.modifier.write(id) }

    override package var structuralChildren: [ViewNode] { [child] }
    override package var layoutChildren: [ViewNode] { child.layoutChildren }
    override package var nodeDescription: String { "ScrollPosition" }
}

/// A node whose subtree holds the scroll targets: the children of the outermost layout below it.
@MainActor
package protocol _ScrollTargetLayoutProviding: AnyObject {
    var isEnabled: Bool { get }
    /// The targets in layout order: the identity of each (a `ForEach` element's or `id(_:)`'s)
    /// and the layout node.
    func scrollTargets() -> [(id: AnyHashable?, node: ViewNode)]
}

/// Node for `scrollTargetLayout`.
@MainActor
package final class ScrollTargetLayoutNode<Content: View>: TypedNode<ModifiedContent<Content, _ScrollTargetLayoutModifier>>, _ScrollTargetLayoutProviding {
    package private(set) var child: TypedNode<Content>!

    init(_ context: _NodeContext<ModifiedContent<Content, _ScrollTargetLayoutModifier>>) {
        super.init(view: context.view, parent: context.parent, runtime: context.runtime, environment: context.environment)
        child = Content._makeNode(_NodeContext(view: context.view.content, parent: self, environment: context.environment))
    }

    override package func update(view: ModifiedContent<Content, _ScrollTargetLayoutModifier>, environment: EnvironmentValues, force: Bool) {
        self.view = view
        self.environment = environment
        clearNeedsUpdate()
        child.update(view: view.content, environment: environment, force: force)
    }

    package var isEnabled: Bool { view.modifier.isEnabled }

    package func scrollTargets() -> [(id: AnyHashable?, node: ViewNode)] {
        // The outermost layout container below: its content's items are the targets.
        guard let container = child.descendants(where: { $0 is _ScrollTargetContainer }).first as? _ScrollTargetContainer else { return [] }
        var targets: [(id: AnyHashable?, node: ViewNode)] = []
        Self.collect(container.targetContent, id: nil, into: &targets)
        return targets
    }

    /// Walks the container's content: `ForEach` entries and `id(_:)` give identities, transparent
    /// nodes are looked through, and each layout node is one target.
    private static func collect(_ node: ViewNode, id: AnyHashable?, into targets: inout [(id: AnyHashable?, node: ViewNode)]) {
        if let forEach = node as? _ForEachNodeProviding {
            for (entryID, entry) in forEach._entries { collect(entry, id: entryID, into: &targets) }
        } else if let identified = node as? _IdentifiedNode {
            for child in node.structuralChildren { collect(child, id: identified.identifier, into: &targets) }
        } else if node.isLayoutNode {
            targets.append((id, node))
        } else {
            for child in node.structuralChildren { collect(child, id: id, into: &targets) }
        }
    }

    override package var structuralChildren: [ViewNode] { [child] }
    override package var layoutChildren: [ViewNode] { child.layoutChildren }
    override package var nodeDescription: String { "ScrollTargetLayout" }
}

/// A layout container whose content's items can be scroll targets.
@MainActor
package protocol _ScrollTargetContainer: AnyObject {
    var targetContent: ViewNode { get }
}

extension LayoutContainerNode: _ScrollTargetContainer {
    package var targetContent: ViewNode { child }
}

/// Node for `scrollIndicatorsFlash(trigger:)`: flashes the indicators of the scroll views
/// within when the trigger changes.
@MainActor
package final class ScrollIndicatorsFlashNode<Content: View, Value: Equatable>: TypedNode<ModifiedContent<Content, _ScrollIndicatorsFlashModifier<Value>>> {
    package private(set) var child: TypedNode<Content>!

    init(_ context: _NodeContext<ModifiedContent<Content, _ScrollIndicatorsFlashModifier<Value>>>) {
        super.init(view: context.view, parent: context.parent, runtime: context.runtime, environment: context.environment)
        child = Content._makeNode(_NodeContext(view: context.view.content, parent: self, environment: context.environment))
    }

    override package func update(view: ModifiedContent<Content, _ScrollIndicatorsFlashModifier<Value>>, environment: EnvironmentValues, force: Bool) {
        let changed = self.view.modifier.trigger != view.modifier.trigger
        self.view = view
        self.environment = environment
        clearNeedsUpdate()
        child.update(view: view.content, environment: environment, force: force)
        if changed {
            for node in child.descendants(where: { $0 is _Scrollable }) { (node as! _Scrollable).showIndicators() }
        }
    }

    override package var structuralChildren: [ViewNode] { [child] }
    override package var layoutChildren: [ViewNode] { child.layoutChildren }
    override package var nodeDescription: String { "ScrollIndicatorsFlash" }
}
