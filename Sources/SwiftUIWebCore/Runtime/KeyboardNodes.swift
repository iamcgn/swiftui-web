// Keyboard runtime (Docs/elements/Keyboard.md): general keyboard focus (any interactive or
// `focusable` view, mirrored with the host's focused overlay element), key dispatch from the
// focused view outwards through `onKeyPress` and command modifiers, then the open menu, then
// keyboard shortcuts, then Escape for presentations; the focus ring.

/// A node that takes key presses (lists, `onKeyPress`, commands).
@MainActor
package protocol _KeyHandling: AnyObject {
    /// Returns whether the press was consumed.
    func handleKey(_ press: KeyPress) -> Bool
}

@MainActor
private var nextKeyboardIdentifier = 7_000_000

/// `onKeyPress`: transparent to layout; handles presses of its keys on the way out.
@MainActor
package final class KeyPressNode<Content: View>: UnaryLayoutModifierNode<Content, _KeyPressModifier>, _KeyHandling {
    package func handleKey(_ press: KeyPress) -> Bool {
        guard modifier.phases.contains(press.phase) else { return false }
        if let keys = modifier.keys, !keys.contains(press.key) { return false }
        return modifier.action.action(press) == .handled
    }
}

/// `onMoveCommand`/`onExitCommand`/`onDeleteCommand`: transparent to layout.
@MainActor
package final class CommandNode<Content: View>: UnaryLayoutModifierNode<Content, _CommandModifier>, _KeyHandling {
    package func handleKey(_ press: KeyPress) -> Bool {
        guard press.modifiers.shortcutModifiers.isEmpty else { return false }
        switch modifier.kind {
        case .move(let box):
            let direction: MoveCommandDirection
            switch press.key {
            case .upArrow: direction = .up
            case .downArrow: direction = .down
            case .leftArrow: direction = .left
            case .rightArrow: direction = .right
            default: return false
            }
            box.action(direction)
        case .exit(let box):
            guard press.key == .escape else { return false }
            box.run()
        case .delete(let box):
            guard press.key == .delete || press.key == .deleteForward else { return false }
            box.run()
        }
        return true
    }
}

/// `keyboardShortcut`: transparent to layout; the runtime asks every shortcut node whether a
/// press matches and activates the first control inside.
@MainActor
package final class KeyboardShortcutNode<Content: View>: UnaryLayoutModifierNode<Content, _KeyboardShortcutModifier> {
    package func matches(_ press: KeyPress) -> Bool {
        guard environment.isEnabled, let shortcut = modifier.shortcut else { return false }
        return shortcut.matches(press)
    }

    package func activate() {
        guard let control = descendants(where: { $0 is _Interactive && !($0 is FocusableNode<Content>) }).first as? any _Interactive else { return }
        control.pressBegan()
        control.pressEnded(inside: true)
    }
}

/// `focusable`: transparent to layout; a focusable element in the overlay whose descendants stay
/// their own elements; a press focuses it.
@MainActor
package final class FocusableNode<Content: View>: UnaryLayoutModifierNode<Content, _FocusableModifier>, _Interactive {
    package let identifier: Int

    override package init(_ context: _NodeContext<ModifiedContent<Content, _FocusableModifier>>) {
        nextKeyboardIdentifier += 1
        identifier = nextKeyboardIdentifier
        super.init(context)
    }

    package func pressBegan() {}
    package func pressEnded(inside: Bool) {
        guard inside, modifier.isFocusable else { return }
        runtime.focus(semanticsIdentifier: identifier, keyboard: false)
    }

    package var semantics: SemanticsNode {
        let label = descendants(where: { $0 is TextNode }).compactMap { ($0 as? TextNode)?.view.resolvedString }.joined(separator: " ")
        var node = SemanticsNode(role: .group, label: label, frame: frameInRoot, identifier: identifier)
        node.isFocusable = modifier.isFocusable
        return node
    }
    package var exposesChildren: Bool { true }
}

extension Runtime {
    /// The interactive node with a semantics identifier, in the tree or a presentation.
    package func interactiveNode(semanticsIdentifier: Int) -> (ViewNode & _Interactive)? {
        interactiveNodes.first { $0.semantics.identifier == semanticsIdentifier }
    }

    /// Moves keyboard focus to the element with `semanticsIdentifier` (or nowhere). Text fields
    /// take the text-field path (the host focuses their input); `keyboard` says whether the
    /// focus ring shows (a click focuses without one, like `:focus-visible`).
    public func focus(semanticsIdentifier: Int?, keyboard: Bool = true) {
        if let semanticsIdentifier, interactiveNode(semanticsIdentifier: semanticsIdentifier) is TextFieldNode {
            focusTextField(semanticsIdentifier)
            return
        }
        guard focusedIdentifier != semanticsIdentifier || focusVisible != keyboard || focusedTextFieldIdentifier != nil else { return }
        focusedTextFieldIdentifier = nil
        focusedIdentifier = semanticsIdentifier
        focusVisible = keyboard
        notifyFocusChanged()
        setNeedsDisplay()
    }

    /// The element lost the host's focus.
    public func blur(semanticsIdentifier: Int) {
        if focusedIdentifier == semanticsIdentifier { focus(semanticsIdentifier: nil) }
    }

    /// A key went down. Dispatch: the focused view and its ancestors (`onKeyPress`, the move/
    /// exit/delete commands, list navigation), the open menu, keyboard shortcuts, then Escape
    /// dismissing the topmost presentation. Returns whether the press was consumed (hosts then
    /// prevent the browser's default).
    @discardableResult
    public func keyDown(_ event: KeyEvent) -> Bool {
        let press = KeyPress(phase: event.isRepeat ? .repeat : .down, key: event.key, characters: event.characters, modifiers: event.modifiers)
        if let focusedIdentifier, let focused = interactiveNode(semanticsIdentifier: focusedIdentifier) {
            var current: ViewNode? = focused
            while let node = current {
                if let handler = node as? any _KeyHandling, handler.handleKey(press) {
                    setNeedsDisplay()
                    return true
                }
                current = node.parent
            }
        }
        if let top = presentations.last, top.kind.isMenu, top.handleKey(press) { return true }
        // Shortcuts in presented content (a sheet's default and cancel buttons) come before
        // Escape closing the presentation, which comes before the window's shortcuts.
        let shortcuts = shortcutNodes
        if activateShortcut(in: shortcuts.presented, for: press) { return true }
        if press.key == .escape, press.modifiers.shortcutModifiers.isEmpty, dismissTopmostPresentation() { return true }
        return activateShortcut(in: shortcuts.window, for: press)
    }

    private func activateShortcut(in nodes: [any _ShortcutMatching], for press: KeyPress) -> Bool {
        guard let node = nodes.first(where: { $0.matches(press) }) else { return false }
        node.activate()
        setNeedsDisplay()
        return true
    }

    private var shortcutNodes: (presented: [any _ShortcutMatching], window: [any _ShortcutMatching]) {
        let window = root.descendants(where: { $0 is any _ShortcutMatching }).compactMap { $0 as? any _ShortcutMatching }
        var presented: [any _ShortcutMatching] = []
        for presentation in presentations.reversed() {
            for child in presentation.structuralChildren {
                presented += child.descendants(where: { $0 is any _ShortcutMatching }).compactMap { $0 as? any _ShortcutMatching }
            }
        }
        return (presented, window)
    }

    /// The focus ring around the focused element when focus came from the keyboard: text
    /// fields paint their own, lists show their selection in the accent colour.
    package func paintFocusRing(into list: inout DisplayList, context: PaintContext) {
        guard focusVisible, let focusedIdentifier, focusedTextFieldIdentifier == nil,
              let node = interactiveNode(semanticsIdentifier: focusedIdentifier), !(node is any _KeyHandling) else { return }
        let ring = context.absoluteRect(node.frameInRoot).insetBy(dx: -PlatformMetrics.focusRingWidth / 2, dy: -PlatformMetrics.focusRingWidth / 2)
        list.append(.strokePath(Path(roundedRect: ring, cornerRadius: PlatformMetrics.focusRingCornerRadius, style: .circular),
                                style: StrokeStyle(lineWidth: PlatformMetrics.focusRingWidth),
                                Color.accentColor.opacity(PlatformMetrics.focusRingOpacity).resolve(in: node.environment)))
    }
}

/// Type-erased access to shortcut nodes.
@MainActor
package protocol _ShortcutMatching: AnyObject {
    func matches(_ press: KeyPress) -> Bool
    func activate()
}

extension KeyboardShortcutNode: _ShortcutMatching {}
