// A UIKit view tree hosted as one element of another framework's scene: SwiftUIWeb's
// `UIViewRepresentable` and `UIViewControllerRepresentable` (decision 0014, Phase 2). The host
// gives the tree a size, asks it to paint at a position in its own display list, forwards the
// pointer while a press is inside it, and mirrors its semantics into its own tree; the hosted
// tree gives the views a window so `window`, `convert(_:to: nil)`, first responders and the
// controller appearance callbacks work as they do in a UIKit app.

/// A window the scene does not show on its own: the root of a tree hosted elsewhere.
@MainActor
final class HostedWindow: UIWindow {
    weak var tree: UIKitHostedTree?
    /// The host's safe area, not the screen's.
    override var safeAreaInsets: UIEdgeInsets { tree?.safeAreaInsets ?? .zero }
}

/// A UIKit view or view controller hosted inside another scene. Points are in the tree's own
/// coordinates, with the origin at the top left of the space the host gives it.
@MainActor
public final class UIKitHostedTree {
    /// The window at the root of the tree (never registered with the scene).
    public let window: UIWindow
    private let touches = TouchRouter()
    private(set) var rootView: UIView?
    private(set) var rootViewController: UIViewController?
    /// Whether the tree is laying out or painting for its host: changes it makes to itself
    /// then are not reported back as new frame requests.
    private var isBusy = false

    /// Called when a view in the tree changed something the host must lay out or paint again for.
    public var onNeedsFrame: (@MainActor () -> Void)?
    /// Called when the text field with keyboard focus in this tree changed (nil: none).
    public var onFocusedTextFieldChange: (@MainActor (Int?) -> Void)?

    public init() {
        let window = HostedWindow(frame: .zero)
        self.window = window
        window.tree = self
        UIKitScene.shared.register(self)
    }

    /// The appearance the tree draws in (`unspecified`: the scene's).
    public var overrideUserInterfaceStyle: UIUserInterfaceStyle {
        get { window.overrideUserInterfaceStyle }
        set {
            guard window.overrideUserInterfaceStyle != newValue else { return }
            let previous = window.traitCollection
            window.overrideUserInterfaceStyle = newValue
            window.propagateTraitChange(from: previous)
        }
    }

    /// The traits the host sets for the tree (SwiftUI's environment: the appearance, the
    /// dynamic type size, the layout direction, the size classes).
    public var traitOverrides: UITraitOverrides {
        get { window.traitOverrides }
        set { window.traitOverrides = newValue }
    }

    /// The safe area the host gives the tree (the part of its frame under a SwiftUI bar or
    /// inset): the window's insets, so every view's `safeAreaInsets` and layout guide follow.
    public var safeAreaInsets = UIEdgeInsets.zero {
        didSet {
            guard safeAreaInsets != oldValue else { return }
            for view in window.subviews { view.safeAreaDidChange() }
            rootViewController?.viewSafeAreaInsetsDidChange()
            UIKitScene.shared.setNeedsFrame()
        }
    }

    // MARK: Content

    /// Shows `view` as the tree's content, filling the window.
    public func setRootView(_ view: UIView) {
        guard rootView !== view else { return }
        rootView?.removeFromSuperview()
        rootView = view
        view.frame = window.bounds
        window.addSubview(view)
    }

    /// Shows `controller`'s view as the tree's content, with the appearance callbacks a window
    /// gives its root controller.
    public func setRootViewController(_ controller: UIViewController) {
        guard rootViewController !== controller else { return }
        if let old = rootViewController { end(old) }
        rootViewController = controller
        controller.window = window
        let view = controller.view!
        view.frame = window.bounds
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        controller.beginAppearanceTransition(true, animated: false)
        window.addSubview(view)
        controller.pendingAppearance = true
    }

    private func end(_ controller: UIViewController) {
        controller.beginAppearanceTransition(false, animated: false)
        controller.viewIfLoaded?.removeFromSuperview()
        controller.endAppearanceTransition()
        controller.window = nil
    }

    /// Takes the tree down: the content leaves the window, a controller disappears, and the
    /// scene forgets the tree.
    public func dismantle() {
        if let controller = rootViewController { end(controller) }
        rootViewController = nil
        rootView?.removeFromSuperview()
        rootView = nil
        if let responder = UIKitScene.shared.firstResponder as? UIView, responder.window === window { _ = responder.resignFirstResponder() }
        UIKitScene.shared.unregister(self)
    }

    /// Advances the scene's timers (long presses) by `elapsed` seconds for the host's frame
    /// loop; returns whether any are still pending, so the host keeps frames coming.
    public func advanceFrame(elapsed: Double) -> Bool {
        UIKitScene.shared.advanceTimers(elapsed: elapsed)
    }

    // MARK: Layout and painting

    /// Lays the tree out in `size`: the window and its content take it, then the needs-layout
    /// cycle runs and controllers that were about to appear did.
    public func layout(size: CGSize) {
        isBusy = true
        defer { isBusy = false }
        if window.bounds.size != size {
            window.frame = CGRect(origin: .zero, size: size)
        }
        // The host laid out the content's alignment rect: the frame is that rect outset by the
        // view's alignment insets (a UISwitch's 66 × 30 is a 68 × 30 frame).
        if let rootView {
            let frame = rootView.frame(forAlignmentRect: window.bounds)
            if rootView.frame != frame { rootView.frame = frame }
        }
        if let view = rootViewController?.viewIfLoaded {
            let frame = view.frame(forAlignmentRect: window.bounds)
            if view.frame != frame { view.frame = frame }
        }
        window.layoutIfNeeded()
        rootViewController?.completeAppearanceIfPending()
        // Appearance callbacks may have changed the tree.
        window.layoutIfNeeded()
    }

    /// The text baselines of the content when laid out in `size`, from its top: a label's
    /// first and last line; a view without text has both at its top (`ios/representable/sizing`).
    public func baselines(in size: CGSize) -> (first: CGFloat, last: CGFloat) {
        guard let content = rootView ?? rootViewController?.viewIfLoaded else { return (0, size.height) }
        return content.textBaselines(in: size)
    }

    /// Paints the tree; `context.origin` is where the tree's origin sits in the host's space.
    public func paint(into list: inout DisplayList, context: PaintContext) {
        isBusy = true
        defer { isBusy = false }
        if UIScreen.main.scale != context.scale { UIScreen.main.scale = context.scale }
        window.layer.paint(into: &list, context: context, style: window.traitCollection.userInterfaceStyle)
    }

    // MARK: Pointer

    public func pointerDown(at point: CGPoint, type: PointerType, time: Double) {
        touches.pointerDown(at: point, in: window, type: type, time: time)
    }

    public func pointerMoved(to point: CGPoint, time: Double) {
        touches.pointerMoved(to: point, time: time)
    }

    public func pointerUp(at point: CGPoint, time: Double) {
        touches.pointerUp(at: point, time: time)
    }

    /// The host's own scrolling took the touch.
    public func pointerCancelled(at point: CGPoint, time: Double) {
        touches.pointerUp(at: point, time: time, cancelled: true)
    }

    /// The axes a scroll view under the pressed point moves on: a press that starts moving along
    /// one stays with the tree instead of panning the host's scroll views.
    public func scrollAxes(at point: CGPoint) -> (horizontal: Bool, vertical: Bool) {
        (window.hitTest(point, with: nil) ?? window).enclosingScrollAxes
    }

    /// A wheel scroll at `point`; returns whether a scroll view in the tree moved.
    public func scrollWheel(by delta: CGSize, at point: CGPoint) -> Bool {
        var view = window.hitTest(point, with: nil)
        while let v = view {
            if let scroll = v as? UIScrollView, scroll.isScrollEnabled, scroll.scroll(by: delta) {
                UIKitScene.shared.setNeedsFrame()
                return true
            }
            view = v.superview
        }
        return false
    }

    // MARK: Semantics

    /// The tree's accessibility elements, frames in the tree's coordinates.
    public func semantics() -> [SemanticsNode] {
        var nodes: [SemanticsNode] = []
        window.collectSemantics(into: &nodes)
        return nodes
    }

    private func view(_ identifier: Int) -> UIView? { window.descendant(withSemanticsIdentifier: identifier) }

    public func contains(semanticsIdentifier: Int) -> Bool { view(semanticsIdentifier) != nil }

    public func activate(semanticsIdentifier: Int) {
        view(semanticsIdentifier)?.accessibilityActivate()
        UIKitScene.shared.setNeedsFrame()
    }

    public func adjust(semanticsIdentifier: Int, increment: Bool) {
        guard let view = view(semanticsIdentifier) else { return }
        if increment { view.accessibilityIncrement() } else { view.accessibilityDecrement() }
        UIKitScene.shared.setNeedsFrame()
    }

    public func setValue(semanticsIdentifier: Int, value: Double) {
        view(semanticsIdentifier)?.accessibilitySetValue(value)
        UIKitScene.shared.setNeedsFrame()
    }

    public func focus(semanticsIdentifier: Int) {
        guard let view = view(semanticsIdentifier), view.canBecomeFirstResponder else { return }
        _ = view.becomeFirstResponder()
    }

    public func blur(semanticsIdentifier: Int) {
        guard let view = view(semanticsIdentifier), view.isFirstResponder else { return }
        _ = view.resignFirstResponder()
    }

    /// The text field in this tree with keyboard focus, by semantics identifier.
    public var focusedTextFieldIdentifier: Int? {
        guard let field = UIKitScene.shared.firstResponder as? any HostTextInput, field.window === window else { return nil }
        return field.semanticsIdentifier
    }

    /// Keyboard focus moved out of the tree: its first responder resigns.
    public func resignFocus() {
        guard let responder = UIKitScene.shared.firstResponder as? UIView, responder.window === window else { return }
        _ = responder.resignFirstResponder()
    }

    public func textField(_ semanticsIdentifier: Int, didChange text: String) {
        (view(semanticsIdentifier) as? any HostTextInput)?.hostDidChange(text)
        UIKitScene.shared.setNeedsFrame()
    }

    public func textFieldDidSubmit(_ semanticsIdentifier: Int) {
        (view(semanticsIdentifier) as? any HostTextInput)?.hostDidSubmit()
        UIKitScene.shared.setNeedsFrame()
    }

    public func textField(_ semanticsIdentifier: Int, focused: Bool) {
        guard let field = view(semanticsIdentifier) as? any HostTextInput else { return }
        if focused { _ = field.becomeFirstResponder() } else if field.isFirstResponder { _ = field.resignFirstResponder() }
        UIKitScene.shared.setNeedsFrame()
    }

    // MARK: Scene callbacks

    /// The scene was asked for a frame: the host hears about it unless the tree is doing the
    /// host's own layout or painting.
    func sceneNeedsFrame() {
        guard !isBusy else { return }
        onNeedsFrame?()
    }

    func firstResponderDidChange(from previous: UIResponder?, to current: UIResponder?) {
        let wasHere = (previous as? UIView)?.window === window
        let isHere = (current as? UIView)?.window === window
        guard wasHere || isHere else { return }
        onFocusedTextFieldChange?(focusedTextFieldIdentifier)
    }
}

extension UIView {
    /// The safe area over this subtree changed: every view hears it and lays out again.
    func safeAreaDidChange() {
        safeAreaInsetsDidChange()
        setNeedsLayout()
        for subview in subviews { subview.safeAreaDidChange() }
    }
}
