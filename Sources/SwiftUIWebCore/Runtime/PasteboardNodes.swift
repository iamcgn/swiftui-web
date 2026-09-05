// Runtime pasteboard: items copied or cut in the app, the handlers ⌘C / ⌘X / ⌘V reach through
// the focused node's ancestors and descendants, and the host's clipboard writer for text.

@MainActor
package protocol _CopyHandling: AnyObject {
    func copyItems() -> [_TransferItem]
}

@MainActor
package protocol _CutHandling: AnyObject {
    func cutItems() -> [_TransferItem]
}

@MainActor
package protocol _PasteHandling: AnyObject {
    /// Takes what it can of `items`; returns whether anything was pasted.
    func paste(_ items: [_TransferItem]) -> Bool
}

@MainActor
package final class CopyableNode<Content: View, T: Transferable>: UnaryLayoutModifierNode<Content, _CopyableModifier<T>>, _CopyHandling {
    package func copyItems() -> [_TransferItem] { modifier.payload().map { _TransferItem($0) } }
    override package var nodeDescription: String { "Copyable" }
}

@MainActor
package final class CuttableNode<Content: View, T: Transferable>: UnaryLayoutModifierNode<Content, _CuttableModifier<T>>, _CutHandling {
    package func cutItems() -> [_TransferItem] { modifier.action().map { _TransferItem($0) } }
    override package var nodeDescription: String { "Cuttable" }
}

@MainActor
package final class PasteDestinationNode<Content: View, T: Transferable>: UnaryLayoutModifierNode<Content, _PasteDestinationModifier<T>>, _PasteHandling {
    package func paste(_ items: [_TransferItem]) -> Bool {
        let values = modifier.validator(items.compactMap { $0.load(as: T.self) })
        guard !values.isEmpty else { return false }
        modifier.action(values)
        return true
    }
    override package var nodeDescription: String { "PasteDestination" }
}

extension Runtime {
    /// Installs the pasteboard probe in the root environment (done at init).
    package func installPasteboard() {
        rootEnvironment._pasteboardProbe = _PasteboardProbe(items: { [weak self] in self?.pasteboard ?? [] })
        root.environment = rootEnvironment
    }

    /// Puts `items` on the pasteboard and hands their text to the host's clipboard.
    public func setPasteboard(_ items: [_TransferItem]) {
        pasteboard = items
        rootEnvironment._pasteboardGeneration += 1
        root.environment = rootEnvironment
        root.reapply?(rootEnvironment)
        if let writer = clipboardWriter, let text = items.compactMap({ $0.load(as: String.self) }).first { writer(text) }
        requestLayout()
    }

    /// Text on the pasteboard, if any (hosts paste it into text fields).
    public var pasteboardText: String? { pasteboard.compactMap { $0.load(as: String.self) }.first }

    /// The handler of `type` nearest the focused node: itself, its ancestors, then its descendants.
    private func pasteboardHandler<H>(_ type: H.Type) -> H? {
        guard let focusedIdentifier, let focused = interactiveNode(semanticsIdentifier: focusedIdentifier) else { return nil }
        var current: ViewNode? = focused
        while let node = current {
            if let handler = node as? H { return handler }
            current = node.parent
        }
        return focused.descendants(where: { $0 is H }).first as? H
    }

    /// ⌘C, ⌘X and ⌘V for the focused chain; returns whether the press was taken.
    package func handlePasteboardKey(_ press: KeyPress) -> Bool {
        guard press.modifiers.shortcutModifiers == [.command] else { return false }
        switch press.key {
        case KeyEquivalent("c"):
            guard let handler = pasteboardHandler((any _CopyHandling).self) else { return false }
            let items = handler.copyItems()
            guard !items.isEmpty else { return false }
            setPasteboard(items)
            return true
        case KeyEquivalent("x"):
            guard let handler = pasteboardHandler((any _CutHandling).self) else { return false }
            let items = handler.cutItems()
            guard !items.isEmpty else { return false }
            setPasteboard(items)
            requestLayout()
            return true
        case KeyEquivalent("v"):
            guard !pasteboard.isEmpty, let handler = pasteboardHandler((any _PasteHandling).self), handler.paste(pasteboard) else { return false }
            requestLayout()
            return true
        default:
            return false
        }
    }
}
