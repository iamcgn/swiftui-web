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

extension Runtime {
    /// Walks `node` (a layout node) and its subtree for elements.
    package func collectSemantics(_ node: ViewNode, attributes: AccessibilityAttributes?, into result: inout [SemanticsEntry]) {
        // Accessibility modifiers above this layout node, outermost first.
        var chain: [AccessibilityAttributes] = []
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
            apply(merged, to: &element)
            result.append(SemanticsEntry(node: node, element: element))
            return
        }
        var elements: [SemanticsEntry] = []
        collectElements(node, into: &elements)
        for var entry in elements {
            if !merged.isEmpty { apply(merged, to: &entry.element) }
            result.append(entry)
        }
    }

    /// The elements of a layout node's subtree with modifiers inside it applied.
    private func collectElements(_ node: ViewNode, into result: inout [SemanticsEntry]) {
        if let interactive = node as? any _Interactive {
            var element = interactive.semantics
            element.frame = node.frameInRoot
            result.append(SemanticsEntry(node: node, element: element))
            if interactive.exposesChildren {
                for child in node.paintedChildren { collectSemantics(child, attributes: nil, into: &result) }
            }
            return
        }
        if let provider = node as? any _SemanticsProviding, var element = provider.staticSemantics {
            element.frame = node.frameInRoot
            result.append(SemanticsEntry(node: node, element: element))
        }
        for child in node.paintedChildren { collectSemantics(child, attributes: nil, into: &result) }
    }

    private func apply(_ attributes: AccessibilityAttributes, to element: inout SemanticsNode) {
        if let label = attributes.label { element.label = label }
        if let hint = attributes.hint { element.hint = hint }
        if let value = attributes.value { element.value = value }
        if let identifier = attributes.identifier { element.accessibilityIdentifier = identifier }
        if attributes.addedTraits.contains(.isHeader) { element.role = .heading }
        if attributes.addedTraits.contains(.isButton), element.role == .text || element.role == .group { element.role = .button }
        if attributes.addedTraits.contains(.isLink) { element.role = .link }
        if attributes.addedTraits.contains(.isImage) { element.role = .image }
    }
}

/// One element of the semantics tree with the node whose root frame it took: a frame that only
/// moved scrolled content refreshes the frames from the nodes instead of walking the tree again.
package struct SemanticsEntry {
    package let node: ViewNode
    package var element: SemanticsNode
}

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
