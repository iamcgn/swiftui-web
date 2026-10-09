// The responder chain: views, view controllers, the window and the application. Touch events
// walk it from the hit view outwards; the first responder takes keyboard input.

/// An abstract interface for responding to and handling events.
@MainActor
open class UIResponder {
    public init() {}

    /// The next object in the responder chain, or nil at the end.
    open var next: UIResponder? { nil }

    /// The standard edit actions (`UIResponderStandardEditActions`): the defaults do nothing;
    /// text fields and text views act on their text and `UIPasteboard.general`
    /// (App/UIPasteboard.swift).
    open func copy(_ sender: Any?) {}
    open func cut(_ sender: Any?) {}
    open func paste(_ sender: Any?) {}
    open func delete(_ sender: Any?) {}
    open func select(_ sender: Any?) {}
    open func selectAll(_ sender: Any?) {}

    open var canBecomeFirstResponder: Bool { false }
    open var canResignFirstResponder: Bool { true }

    /// Whether this responder is the window's first responder.
    open var isFirstResponder: Bool { UIKitScene.shared.firstResponder === self }

    @discardableResult
    open func becomeFirstResponder() -> Bool {
        guard canBecomeFirstResponder else { return false }
        let scene = UIKitScene.shared
        if let current = scene.firstResponder, current !== self {
            guard current.resignFirstResponder() else { return false }
        }
        scene.firstResponder = self
        scene.setNeedsFrame()
        return true
    }

    @discardableResult
    open func resignFirstResponder() -> Bool {
        guard canResignFirstResponder else { return false }
        let scene = UIKitScene.shared
        if scene.firstResponder === self { scene.firstResponder = nil }
        scene.setNeedsFrame()
        return true
    }

    // MARK: Touches (the default forwards to the next responder)

    open func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) { next?.touchesBegan(touches, with: event) }
    open func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) { next?.touchesMoved(touches, with: event) }
    open func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { next?.touchesEnded(touches, with: event) }
    open func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { next?.touchesCancelled(touches, with: event) }

    // MARK: Keys

    open func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) { next?.pressesBegan(presses, with: event) }
    open func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) { next?.pressesEnded(presses, with: event) }
}
