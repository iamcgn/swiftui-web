// Focus runtime: `focused` modifier nodes register with their focus state box and report the
// text field they cover; the runtime tells every box when its focused field changes.

@MainActor
package final class FocusedNode<Content: View, Value: Hashable>: UnaryLayoutModifierNode<Content, _FocusedModifier<Value>>, _FocusTargetProviding {
    override package init(_ context: _NodeContext<ModifiedContent<Content, _FocusedModifier<Value>>>) {
        super.init(context)
        register()
        runtime.registerFocusBox(modifier.box)
        // Focus already on this value (set before the view existed) takes effect now.
        if let box = modifier.box, box.value == modifier.value, let id = focusTargetIdentifier { runtime.focus(semanticsIdentifier: id) }
    }

    override package func update(view: ModifiedContent<Content, _FocusedModifier<Value>>, environment: EnvironmentValues, force: Bool) {
        super.update(view: view, environment: environment, force: force)
        register()
    }

    private func register() {
        guard let box = modifier.box else { return }
        if !box.targets.contains(where: { $0.node.node === self }) {
            box.targets.append((modifier.value, WeakNode(node: self)))
        }
        box.targets.removeAll { $0.node.node == nil }
    }

    /// The first text field in the subtree, else its first interactive or focusable view.
    package var focusTargetIdentifier: Int? {
        if let field = descendants(where: { $0 is TextFieldNode }).first as? TextFieldNode { return field.identifier }
        return (descendants(where: { $0 is _Interactive }).first as? any _Interactive)?.semantics.identifier
    }
}

/// Type-erased access to a focus state box for the runtime's notifications.
@MainActor
package protocol _FocusBoxObserving: AnyObject {
    func focusDidChange(to identifier: Int?)
}

extension _FocusStateBox: _FocusBoxObserving {}

extension Runtime {
    package func registerFocusBox(_ box: (any _FocusBoxObserving)?) {
        guard let box, !focusBoxes.contains(where: { $0.box === box }) else { return }
        focusBoxes.append(WeakFocusBox(box: box))
    }

    /// Moves keyboard focus to a text field (or nowhere) and tells the host and the focus states.
    package func focusTextField(_ identifier: Int?) {
        guard focusedTextFieldIdentifier != identifier || focusedIdentifier != identifier else { return }
        focusedTextFieldIdentifier = identifier
        focusedIdentifier = identifier
        focusVisible = true
        notifyFocusChanged()
        setNeedsDisplay()
    }

    package func notifyFocusChanged() {
        focusBoxes.removeAll { $0.box == nil }
        for entry in focusBoxes { entry.box?.focusDidChange(to: focusedIdentifier) }
    }
}

package struct WeakFocusBox {
    package weak var box: (any _FocusBoxObserving)?
}
