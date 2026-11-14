// The responder chain: views, view controllers, the window and the application. Touch events
// walk it from the hit view outwards; the first responder takes keyboard input.
import WebFoundation   // Foundation everywhere, and the Selector stand-in where ObjectiveC is absent

#if canImport(ObjectiveC)
/// The responder chain's root: with an Objective-C runtime (decision 0023) it is `NSObject`,
/// as UIKit's is, so `#selector`, `responds(to:)`, `perform(_:with:)` and target-action work
/// on every responder.
public typealias UIResponderBase = NSObject
#else
/// The responder chain's root without an Objective-C runtime.
@preconcurrency @MainActor
open class UIResponderBase {
    public init() {}

    // NSObject's sends by selector, as UIKit's responders inherit them. Without the runtime no
    // method is registered under a selector, so a responder responds to none and a send
    // returns nothing: Kingfisher's `UIApplication.responds(to: "sharedApplication")` check
    // takes its branch for an app extension. Nonisolated, as NSObject's are.
    nonisolated open func responds(to aSelector: Selector!) -> Bool { false }
    nonisolated open class func responds(to aSelector: Selector!) -> Bool { false }
    nonisolated open class func instancesRespond(to aSelector: Selector!) -> Bool { false }
    nonisolated open func perform(_ aSelector: Selector!) -> Unmanaged<AnyObject>! { nil }
    nonisolated open func perform(_ aSelector: Selector!, with object: Any!) -> Unmanaged<AnyObject>! { nil }
    nonisolated open func perform(_ aSelector: Selector!, with object1: Any!, with object2: Any!) -> Unmanaged<AnyObject>! { nil }
    nonisolated open class func perform(_ aSelector: Selector!) -> Unmanaged<AnyObject>! { nil }
    nonisolated open class func perform(_ aSelector: Selector!, with object: Any!) -> Unmanaged<AnyObject>! { nil }
    nonisolated open class func perform(_ aSelector: Selector!, with object1: Any!, with object2: Any!) -> Unmanaged<AnyObject>! { nil }

    // NSObject's equality: identity, unless a class overrides `isEqual(_:)` and `hash` as
    // UIKit's subclasses may. Every responder, and every layer (CALayerBase), is then Hashable,
    // as UIKit's are: a dictionary keyed by view controllers (SwiftUIExperiments' walk charts)
    // or a set of views.
    nonisolated open func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? UIResponderBase else { return false }
        return other === self
    }
    nonisolated open var hash: Int { ObjectIdentifier(self).hashValue }
}

extension UIResponderBase: Hashable {
    nonisolated public static func == (lhs: UIResponderBase, rhs: UIResponderBase) -> Bool { lhs.isEqual(rhs) }
    nonisolated public func hash(into hasher: inout Hasher) { hasher.combine(hash) }
}
#endif

/// An abstract interface for responding to and handling events.
@preconcurrency @MainActor
open class UIResponder: UIResponderBase {
    public override init() { super.init() }

    /// The next object in the responder chain, or nil at the end.
    open var next: UIResponder? { nil }

    /// The standard edit actions (`UIResponderStandardEditActions`): the defaults do nothing;
    /// text fields and text views act on their text and `UIPasteboard.general`
    /// (App/UIPasteboard.swift).
    #if canImport(ObjectiveC)
    @objc open func copy(_ sender: Any?) {}
    @objc open func cut(_ sender: Any?) {}
    @objc open func paste(_ sender: Any?) {}
    @objc open func delete(_ sender: Any?) {}
    @objc open func select(_ sender: Any?) {}
    @objc open func selectAll(_ sender: Any?) {}
    #else
    open func copy(_ sender: Any?) {}
    open func cut(_ sender: Any?) {}
    open func paste(_ sender: Any?) {}
    open func delete(_ sender: Any?) {}
    open func select(_ sender: Any?) {}
    open func selectAll(_ sender: Any?) {}
    #endif

    // MARK: Commands and menus (Events/Keyboard.swift, Containers/MenuBuilder.swift)

    /// Whether this responder handles `action` (`UIResponderStandardEditActions` and
    /// target-action): with the runtime, whether it responds to the selector.
    open func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        #if canImport(ObjectiveC)
        return responds(to: action)
        #else
        return false
        #endif
    }

    /// The responder from this one up the chain that handles `action`.
    open func target(forAction action: Selector, withSender sender: Any?) -> Any? {
        var responder: UIResponder? = self
        while let current = responder {
            if current.canPerformAction(action, withSender: sender) { return current }
            responder = current.next
        }
        return nil
    }

    /// Adds, removes or replaces the app's menus (`UIMenuSystem.main`); the default changes
    /// nothing. Called on the application and the app delegate when the menu system rebuilds.
    open func buildMenu(with builder: any UIMenuBuilder) {}

    /// Adjusts a command's state before it is shown; the default changes nothing.
    open func validate(_ command: UICommand) {}

    // MARK: Input views (Controls/UIInputView.swift)

    /// The view shown in place of the keyboard while this responder is first responder (none:
    /// the system keyboard). Text fields and text views take one; the web shows none.
    open var inputView: UIView? { nil }
    /// The view shown above the keyboard while this responder is first responder, along the
    /// bottom of the window. Text fields and text views take one.
    open var inputAccessoryView: UIView? { nil }

    /// Shows this responder's input views again after they changed, when it is first responder.
    open func reloadInputViews() {
        if isFirstResponder { UIKitScene.shared.updateInputAccessory() }
    }

    open var canBecomeFirstResponder: Bool { false }
    open var canResignFirstResponder: Bool { true }

    /// Whether this responder is the window's first responder.
    open var isFirstResponder: Bool { UIKitScene.shared.firstResponder === self }

    // `@objc` with the runtime, so `#selector(UIResponder.resignFirstResponder)` names them, as
    // apps' keyboard-dismissing `sendAction` calls do.
    #if canImport(ObjectiveC)
    @discardableResult
    @objc open func becomeFirstResponder() -> Bool { _becomeFirstResponder() }
    @discardableResult
    @objc open func resignFirstResponder() -> Bool { _resignFirstResponder() }
    #else
    @discardableResult
    open func becomeFirstResponder() -> Bool { _becomeFirstResponder() }
    @discardableResult
    open func resignFirstResponder() -> Bool { _resignFirstResponder() }
    #endif

    private func _becomeFirstResponder() -> Bool {
        guard canBecomeFirstResponder else { return false }
        let scene = UIKitScene.shared
        if let current = scene.firstResponder, current !== self {
            guard current.resignFirstResponder() else { return false }
        }
        scene.firstResponder = self
        scene.setNeedsFrame()
        return true
    }

    private func _resignFirstResponder() -> Bool {
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

    // MARK: Keys (Events/Keyboard.swift)

    /// The key commands this responder handles; the chain is searched from the first responder up.
    open var keyCommands: [UIKeyCommand]? { nil }
    open func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) { next?.pressesBegan(presses, with: event) }
    open func pressesChanged(_ presses: Set<UIPress>, with event: UIPressesEvent?) { next?.pressesChanged(presses, with: event) }
    open func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) { next?.pressesEnded(presses, with: event) }
    open func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) { next?.pressesCancelled(presses, with: event) }
}
