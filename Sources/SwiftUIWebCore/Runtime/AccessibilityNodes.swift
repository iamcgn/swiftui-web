// The semantics walk: every painted node contributes its element (interactive nodes, text,
// images), accessibility modifier nodes hide, relabel or combine the elements below them.

@MainActor
package final class AccessibilityNode<Content: View>: TypedNode<ModifiedContent<Content, _AccessibilityModifier>> {
    package private(set) var child: TypedNode<Content>!

    init(_ context: _NodeContext<ModifiedContent<Content, _AccessibilityModifier>>) {
        super.init(view: context.view, parent: context.parent, runtime: context.runtime, environment: context.environment)
        child = Content._makeNode(_NodeContext(view: context.view.content, parent: self, environment: context.environment))
    }

    override package func update(view: ModifiedContent<Content, _AccessibilityModifier>, environment: EnvironmentValues, force: Bool) {
        self.view = view
        self.environment = environment
        clearNeedsUpdate()
        child.update(view: view.content, environment: environment, force: force)
    }

    package var attributes: AccessibilityAttributes { view.modifier.attributes }

    override package var structuralChildren: [ViewNode] { [child] }
    override package var layoutChildren: [ViewNode] { child.layoutChildren }
    override package var nodeDescription: String { "Accessibility" }
}

@MainActor
package protocol _AccessibilityAttributing: AnyObject {
    var attributes: AccessibilityAttributes { get }
}

extension AccessibilityNode: _AccessibilityAttributing {}

/// `accessibilityActions`: the content's buttons (built as a detached tree, never laid out or
/// painted) become custom actions named by their titles.
@MainActor
package final class AccessibilityActionsNode<Content: View>: TypedNode<ModifiedContent<Content, _AccessibilityActionsModifier>>, _AccessibilityAttributing {
    package private(set) var child: TypedNode<Content>!
    private var actionsTree: TypedNode<AnyView>!

    init(_ context: _NodeContext<ModifiedContent<Content, _AccessibilityActionsModifier>>) {
        super.init(view: context.view, parent: context.parent, runtime: context.runtime, environment: context.environment)
        child = Content._makeNode(_NodeContext(view: context.view.content, parent: self, environment: context.environment))
        // Parented here for the runtime's sake; not a structural child, so never laid out or painted.
        actionsTree = AnyView._makeNode(_NodeContext(view: context.view.modifier.content, parent: self, environment: context.environment))
    }

    override package func update(view: ModifiedContent<Content, _AccessibilityActionsModifier>, environment: EnvironmentValues, force: Bool) {
        self.view = view
        self.environment = environment
        clearNeedsUpdate()
        child.update(view: view.content, environment: environment, force: force)
        actionsTree.update(view: view.modifier.content, environment: environment, force: force)
    }

    override package func unmount() {
        actionsTree.unmount()
        super.unmount()
    }

    package var attributes: AccessibilityAttributes {
        var attributes = AccessibilityAttributes()
        for button in actionsTree.descendants(where: { $0 is ButtonHostNode }).compactMap({ $0 as? ButtonHostNode }) {
            attributes.actions.append(_AccessibilityAction(kind: .named(button.semantics.label), run: { button.pressBegan(); button.pressEnded(inside: true) }))
        }
        return attributes
    }

    override package var structuralChildren: [ViewNode] { [child] }
    override package var layoutChildren: [ViewNode] { child.layoutChildren }
    override package var nodeDescription: String { "AccessibilityActions" }
}

/// `accessibilityRepresentation` / `accessibilityChildren`: the content lays out and paints as
/// usual; the replacement view is laid out over it (never painted or hit) and its elements
/// stand in for the content's (or sit under the content's own element as a container).
@MainActor
package final class AccessibilityReplacementNode<Content: View>: LayoutNode<ModifiedContent<Content, _AccessibilityReplacementModifier>>, _AccessibilityReplacing {
    package private(set) var child: TypedNode<Content>!
    package private(set) var replacement: TypedNode<AnyView>!

    init(_ context: _NodeContext<ModifiedContent<Content, _AccessibilityReplacementModifier>>) {
        super.init(view: context.view, parent: context.parent, runtime: context.runtime, environment: context.environment)
        child = Content._makeNode(_NodeContext(view: context.view.content, parent: self, environment: context.environment))
        replacement = AnyView._makeNode(_NodeContext(view: context.view.modifier.replacement, parent: self, environment: context.environment))
    }

    override package func update(view: ModifiedContent<Content, _AccessibilityReplacementModifier>, environment: EnvironmentValues, force: Bool) {
        self.view = view
        self.environment = environment
        clearNeedsUpdate()
        child.update(view: view.content, environment: environment, force: force)
        replacement.update(view: view.modifier.replacement, environment: environment, force: force)
    }

    private var target: ViewNode? { child.layoutChildren.first }

    override package func computeSizeThatFits(_ proposal: ProposedViewSize) -> CGSize { target?.sizeThatFits(proposal) ?? .zero }
    override package func dimensions(in proposal: ProposedViewSize) -> ViewDimensions { target?.dimensions(in: proposal) ?? ViewDimensions(size: .zero) }
    override package func layoutContents(proposal: ProposedViewSize) {
        target?.place(at: .zero, anchor: .topLeading, proposal: proposal, by: self)
        let size = target?.frame.size ?? .zero
        for node in replacement.layoutChildren {
            node.place(at: .zero, anchor: .topLeading, proposal: ProposedViewSize(size), by: self)
        }
    }
    override package var layoutSpacing: ViewSpacing { target?.layoutSpacing ?? ViewSpacing() }
    override package var paintedChildren: [ViewNode] { target.map { [$0] } ?? [] }
    override package var structuralChildren: [ViewNode] { [child, replacement] }
    override package var nodeDescription: String { view.modifier.container ? "AccessibilityChildren" : "AccessibilityRepresentation" }

    package var isContainer: Bool { view.modifier.container }
    package var replacementRoots: [ViewNode] { replacement.layoutChildren }
}

@MainActor
package protocol _AccessibilityReplacing: AnyObject {
    var isContainer: Bool { get }
    var replacementRoots: [ViewNode] { get }
}

extension Runtime {
    /// Walks `node` (a layout node) and its subtree for elements.
    package func collectSemantics(_ node: ViewNode, attributes: AccessibilityAttributes?, into result: inout [SemanticsEntry]) {
        // Accessibility modifiers above this layout node (and the node's own, for a layout node
        // such as `help` that carries attributes), innermost first.
        var chain: [AccessibilityAttributes] = []
        if let own = node as? any _AccessibilityAttributing { chain.append(own.attributes) }
        var current: ViewNode? = node.parent
        while let candidate = current, !candidate.isLayoutNode || candidate === node.parent {
            if let scope = candidate as? any _AccessibilityAttributing { chain.append(scope.attributes) }
            if candidate.isLayoutNode { break }
            current = candidate.parent
        }
        var merged = attributes ?? AccessibilityAttributes()
        for entry in chain.reversed() { merged = entry.merged(over: merged) }
        if merged.hidden { return }
        if let behavior = merged.children, behavior.kind != .contain {
            // One element for the whole subtree, with the labels of its parts.
            var parts: [SemanticsEntry] = []
            collectElements(node, into: &parts)
            var element = SemanticsNode(role: .group, label: merged.label ?? parts.map(\.element.label).filter { !$0.isEmpty }.joined(separator: ", "),
                                        frame: node.frameInRoot, identifier: node.semanticsIdentifier)
            if let first = parts.first?.element, parts.count == 1 { element.role = first.role; element.isOn = first.isOn; element.range = first.range }
            var entry = SemanticsEntry(node: node, element: element)
            apply(merged, to: &entry, rotors: true)
            result.append(entry)
            return
        }
        var elements: [SemanticsEntry] = []
        collectElements(node, into: &elements)
        // A view with actions, a rotor or a focus target but no element of its own gets one.
        if elements.isEmpty, !merged.actions.isEmpty || merged.adjustable != nil || !merged.rotors.isEmpty || merged.focusable || merged.rotorEntry != nil {
            elements.append(SemanticsEntry(node: node, element: SemanticsNode(role: .group, label: merged.label ?? "", frame: node.frameInRoot, identifier: node.semanticsIdentifier)))
        }
        // A container (`accessibilityChildren`) takes the attributes alone; rotors go on the
        // first element in any case.
        let containerOnly = (node as? any _AccessibilityReplacing)?.isContainer == true
        for (index, var entry) in elements.enumerated() {
            if !merged.isEmpty, index == 0 || !containerOnly { apply(merged, to: &entry, rotors: index == 0) }
            result.append(entry)
        }
    }

    /// The elements of a layout node's subtree with modifiers inside it applied; children are
    /// ordered by their sort priority (higher first, stable).
    private func collectElements(_ node: ViewNode, into result: inout [SemanticsEntry]) {
        // A hosted tree lists its own elements (Runtime/PlatformViewNodes.swift).
        if let host = node as? _PlatformViewSemanticsProviding {
            result += host.semanticsEntries
            return
        }
        // `accessibilityRepresentation`: the replacement's elements instead of the content's;
        // `accessibilityChildren`: a container element over the replacement's elements.
        if let replacing = node as? any _AccessibilityReplacing {
            if replacing.isContainer {
                result.append(SemanticsEntry(node: node, element: SemanticsNode(role: .group, label: "", frame: node.frameInRoot, identifier: node.semanticsIdentifier)))
            }
            collectChildren(replacing.replacementRoots, into: &result)
            return
        }
        if let interactive = node as? any _Interactive, interactive.isInteractive {
            var element = interactive.semantics
            element.frame = node.frameInRoot
            result.append(SemanticsEntry(node: node, element: element))
            if interactive.exposesChildren { collectChildren(node.paintedChildren, into: &result) }
            return
        }
        if let provider = node as? any _SemanticsProviding, var element = provider.staticSemantics {
            element.frame = node.frameInRoot
            result.append(SemanticsEntry(node: node, element: element))
        }
        collectChildren(node.paintedChildren, into: &result)
    }

    private func collectChildren(_ children: [ViewNode], into result: inout [SemanticsEntry]) {
        var chunks: [(priority: Double, entries: [SemanticsEntry])] = []
        for child in children {
            var entries: [SemanticsEntry] = []
            collectSemantics(child, attributes: nil, into: &entries)
            chunks.append((entries.first?.sortPriority ?? 0, entries))
        }
        if chunks.contains(where: { $0.priority != 0 }) {
            chunks = chunks.enumerated().sorted { ($1.element.priority, $0.offset) < ($0.element.priority, $1.offset) }.map(\.element)
        }
        for chunk in chunks { result += chunk.entries }
    }

    private func apply(_ attributes: AccessibilityAttributes, to entry: inout SemanticsEntry, rotors: Bool) {
        if let label = attributes.label { entry.element.label = label }
        if let hint = attributes.hint { entry.element.hint = hint }
        if let value = attributes.value { entry.element.value = value }
        if let identifier = attributes.identifier { entry.element.accessibilityIdentifier = identifier }
        if attributes.addedTraits.contains(.isHeader) { entry.element.role = .heading }
        if attributes.addedTraits.contains(.isButton), entry.element.role == .text || entry.element.role == .group { entry.element.role = .button }
        if attributes.addedTraits.contains(.isLink) { entry.element.role = .link }
        if attributes.addedTraits.contains(.isImage) { entry.element.role = .image }
        if attributes.addedTraits.contains(.updatesFrequently) { entry.element.isLive = true }
        if attributes.addedTraits.contains(.isSelected) { entry.element.isSelected = true }
        if attributes.removedTraits.contains(.isSelected) { entry.element.isSelected = nil }
        if let level = attributes.headingLevel { entry.element.headingLevel = level }
        if let help = attributes.help { entry.element.description = help }
        if attributes.focusable { entry.element.isFocusable = true }
        if !attributes.customContent.isEmpty {
            let content = attributes.customContent.joined(separator: "; ")
            entry.element.hint = entry.element.hint.map { "\($0). \(content)" } ?? content
        }
        // Attributes apply level by level (the inner modifiers' first): accumulate, never clear.
        for action in attributes.actions where !entry.actions.contains(action) { entry.actions.append(action) }
        if let adjustable = attributes.adjustable { entry.adjustable = adjustable }
        if let priority = attributes.sortPriority { entry.sortPriority = priority }
        if rotors { for rotor in attributes.rotors where !entry.rotors.contains(rotor) { entry.rotors.append(rotor) } }
        if let key = attributes.rotorEntry { entry.rotorEntry = key }
        // A default action makes a static element activatable (a button to the host); custom
        // actions are listed by name; an adjustable one is incremented like a stepper.
        if entry.actions.contains(where: { $0.kind == .kind(.default) }), entry.element.role == .text || entry.element.role == .group || entry.element.role == .image {
            entry.element.role = .button
        }
        entry.element.customActions = entry.actions.compactMap { if case .named(let name) = $0.kind { return name } else { return nil } }
        if entry.adjustable != nil {
            entry.element.isAdjustable = true
            if entry.element.role == .text || entry.element.role == .group { entry.element.role = .stepper }
        }
    }

    /// Rotor entries resolved to the elements marked with their ids (after a full walk).
    package func resolveRotors(in entries: inout [SemanticsEntry]) {
        guard entries.contains(where: { !$0.rotors.isEmpty }) else { return }
        var targets: [AnyHashable: [(namespace: Namespace.ID, identifier: Int)]] = [:]
        for entry in entries {
            if let key = entry.rotorEntry { targets[key.id, default: []].append((key.namespace, entry.element.identifier)) }
        }
        var targeted: Set<Int> = []
        for index in entries.indices where !entries[index].rotors.isEmpty {
            entries[index].element.rotors = entries[index].rotors.map { rotor in
                SemanticsRotor(label: rotor.label, entries: rotor.entries.map { entry in
                    let candidates = entry.id.flatMap { targets[$0] } ?? []
                    let target = candidates.first { entry.namespace == nil || $0.namespace == entry.namespace }?.identifier
                    if let target { targeted.insert(target) }
                    return SemanticsRotor.Entry(label: entry.label, target: target)
                })
            }
        }
        // An entry's element takes focus when the entry is chosen.
        for index in entries.indices where targeted.contains(entries[index].element.identifier) { entries[index].element.isFocusable = true }
    }

    /// The cached entry of an element (walking the tree first when the cache is stale).
    package func semanticsEntry(for identifier: Int) -> SemanticsEntry? {
        if !semanticsCacheIsValid { _ = semanticsTree() }
        return semanticsCache.first { $0.element.identifier == identifier }
    }

    /// Performs a custom action of an element by name (`HostedScene`), or an action of a kind
    /// by its kind name.
    public func performAccessibilityAction(semanticsIdentifier: Int, name: String) {
        guard let entry = semanticsEntry(for: semanticsIdentifier), let action = entry.actions.first(where: { $0.name == name }) else { return }
        action.run()
        requestLayout()
    }

    /// Runs the element's action of `kind`, if any; returns whether it had one.
    package func performAccessibilityAction(semanticsIdentifier: Int, kind: AccessibilityActionKind) -> Bool {
        guard let entry = semanticsEntry(for: semanticsIdentifier), let action = entry.actions.first(where: { $0.kind == .kind(kind) }) else { return false }
        action.run()
        requestLayout()
        return true
    }

    /// Runs the element's adjustable action, if any; returns whether it had one.
    package func performAdjustableAction(semanticsIdentifier: Int, increment: Bool) -> Bool {
        guard let entry = semanticsEntry(for: semanticsIdentifier), let adjustable = entry.adjustable else { return false }
        adjustable.run(increment ? .increment : .decrement)
        requestLayout()
        return true
    }
}

/// One element of the semantics tree with the node whose root frame it took: a frame that only
/// moved scrolled content refreshes the frames from the nodes instead of walking the tree again.
package struct SemanticsEntry {
    package let node: ViewNode
    package var element: SemanticsNode
    /// For an element inside a hosted tree: its frame relative to the node's, so a frame that
    /// only scrolled can move it with the node.
    package var relativeFrame: CGRect?
    /// The element's actions, adjustable action, sort priority and rotors (from its modifiers).
    package var actions: [_AccessibilityAction] = []
    package var adjustable: _AdjustableAction?
    package var sortPriority: Double?
    package var rotors: [_AccessibilityRotor] = []
    package var rotorEntry: _RotorEntryKey?

    package init(node: ViewNode, element: SemanticsNode, relativeFrame: CGRect? = nil) {
        self.node = node
        self.element = element
        self.relativeFrame = relativeFrame
    }
}

/// A node whose semantics are a list of elements of its own (a hosted tree).
@MainActor
package protocol _PlatformViewSemanticsProviding: AnyObject {
    var semanticsEntries: [SemanticsEntry] { get }
}

extension _PlatformViewHostNode: _PlatformViewSemanticsProviding {}

extension ViewNode {
    /// A stable identifier for elements that are not interactive nodes, from the node's identity.
    package var semanticsIdentifier: Int { 10_000_000 + (ObjectIdentifier(self).hashValue & 0x7FFFFF) }
}

extension TextNode: _SemanticsProviding {
    package var staticSemantics: SemanticsNode? {
        let string = view.resolvedString
        guard !string.isEmpty else { return nil }
        return SemanticsNode(role: .text, label: string, frame: frameInRoot, identifier: semanticsIdentifier)
    }
}

extension ImageNode: _SemanticsProviding {
    package var staticSemantics: SemanticsNode? {
        SemanticsNode(role: .image, label: view._accessibilityName, frame: frameInRoot, identifier: semanticsIdentifier)
    }
}
