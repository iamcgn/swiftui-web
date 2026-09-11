// The scene the substrate's hosts drive (WebGraphics `HostedScene`, decision 0014): the
// windows, one frame (layout, then the layer tree painted into the display list), touches from
// the host's pointer, and the semantics tree from the views' accessibility properties.

/// The UIKit app as a hosted scene. One per process, like `UIApplication.shared`.
@MainActor
public final class UIKitScene: HostedScene {
    public static let shared = UIKitScene()

    private init() {}

    // MARK: Windows

    public private(set) var windows: [UIWindow] = []
    /// The window the app delegate keeps (`UIApplicationDelegate.window`).
    var delegateWindow: UIWindow?
    /// The responder taking key input (a text field).
    var firstResponder: UIResponder? {
        didSet {
            guard firstResponder !== oldValue else { return }
            for entry in hostedTrees { entry.tree?.firstResponderDidChange(from: oldValue, to: firstResponder) }
        }
    }

    // MARK: Trees hosted in other scenes (decision 0014: SwiftUIWeb's representables)

    private struct WeakTree { weak var tree: UIKitHostedTree? }
    private var hostedTrees: [WeakTree] = []

    func register(_ tree: UIKitHostedTree) {
        hostedTrees.removeAll { $0.tree == nil }
        hostedTrees.append(WeakTree(tree: tree))
    }

    func unregister(_ tree: UIKitHostedTree) {
        hostedTrees.removeAll { $0.tree == nil || $0.tree === tree }
    }

    func add(_ window: UIWindow) {
        guard !windows.contains(where: { $0 === window }) else { return }
        windows.append(window)
        window.frame = UIScreen.main.bounds
        window.didJoinScene()
        setNeedsFrame()
    }

    func remove(_ window: UIWindow) {
        windows.removeAll { $0 === window }
        setNeedsFrame()
    }

    /// Drops every window, and the timers and animations they had running (tests mount one
    /// fixture after another in the shared scene).
    public func removeAllWindows() {
        for window in windows { window.rootViewController?.viewIfLoaded?.removeFromSuperview() }
        windows.removeAll()
        delegateWindow = nil
        firstResponder = nil
        timers.removeAll()
        animationGroups.removeAll()
        setNeedsFrame()
    }

    /// Modal presentation (Phase 3): the presented controller's view covers the window.
    func present(_ controller: UIViewController, from presenter: UIViewController) {
        guard let window = presenter.viewIfLoaded?.window ?? windows.first else { return }
        controller.window = window
        let view = controller.view!
        view.frame = window.bounds
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        controller.beginAppearanceTransition(true, animated: false)
        window.addSubview(view)
        controller.pendingAppearance = true
        setNeedsFrame()
    }

    func dismiss(_ controller: UIViewController) {
        controller.beginAppearanceTransition(false, animated: false)
        controller.viewIfLoaded?.removeFromSuperview()
        controller.endAppearanceTransition()
        controller.window = nil
        setNeedsFrame()
    }

    // MARK: Services the host installs

    public var textEngine: any TextEngine = PlaceholderTextEngine()
    public var assetCatalog: AssetCatalog = .empty { didSet { setNeedsFrame() } }
    public var imageLoader: (any _ImageLoading)?
    public var hostColorScheme: ColorScheme = .light {
        didSet {
            guard hostColorScheme != oldValue else { return }
            let previous = UIScreen.main.traitCollection
            UIScreen.main.traitCollection.userInterfaceStyle = hostColorScheme == .dark ? .dark : .light
            UITraitCollection.current = UIScreen.main.traitCollection
            for window in windows { window.propagateTraitChange(from: previous) }
            setNeedsFrame()
        }
    }
    public var clipboardWriter: ((String) -> Void)?
    public var onNeedsFrame: (@MainActor () -> Void)?
    /// The host's link opener (`UIApplication.open`).
    public var openURL: ((String) -> Void)?

    /// Sets the screen's size and scale (hosts do this before launching the app).
    public func configureScreen(size: CGSize, scale: CGFloat) {
        UIScreen.main.bounds = CGRect(origin: .zero, size: size)
        UIScreen.main.scale = scale
        UIScreen.main.traitCollection.displayScale = scale
        UIScreen.main.traitCollection.userInterfaceIdiom = size.width < 500 ? .phone : .pad
        UIScreen.main.traitCollection.horizontalSizeClass = size.width < 500 ? .compact : .regular
        UITraitCollection.current = UIScreen.main.traitCollection
    }

    // MARK: Frames

    public private(set) var needsFrame = false
    public var isAnimating: Bool { !animationGroups.isEmpty }
    /// The running `UIView.animate` groups (Layers/LayerAnimation.swift).
    var animationGroups: [UIViewAnimationGroup] = []
    public var windowTitle: String? { nil }
    public var probeFrames: [String: CGRect] { probes }
    /// Frames published under a name for tests (`UIView.publishFrame(as:)`).
    var probes: [String: CGRect] = [:]

    /// Asks the host for a frame (and every host of a tree hosted elsewhere).
    public func setNeedsFrame() {
        for entry in hostedTrees { entry.tree?.sceneNeedsFrame() }
        guard !needsFrame else { return }
        needsFrame = true
        onNeedsFrame?()
    }

    public func advanceFrame(elapsed: Double) -> Bool {
        runTimers(elapsed: elapsed)
        return advanceAnimations(elapsed: elapsed)
    }

    /// Advances the timers and animations for a host whose frame loop drives a hosted tree (the
    /// scene's own host goes through `advanceFrame`); returns whether either still runs.
    func advanceTimers(elapsed: Double) -> Bool {
        runTimers(elapsed: elapsed)
        let animating = advanceAnimations(elapsed: elapsed)
        return animating || !timers.isEmpty
    }

    public func layout(in size: CGSize) {
        needsFrame = false
        if UIScreen.main.bounds.size != size {
            UIScreen.main.bounds = CGRect(origin: .zero, size: size)
            for window in windows { window.frame = UIScreen.main.bounds }
        }
        for window in windows {
            window.layoutIfNeeded()
            window.completePendingAppearances()
        }
        // Appearance callbacks may have changed the tree.
        for window in windows { window.layoutIfNeeded() }
    }

    public func render(scale: CGFloat) -> DisplayList { render(scale: scale, background: true) }

    /// The frame's display list; `background` paints the black screen behind the windows (off
    /// for goldens, which are transparent outside the views).
    public func render(scale: CGFloat, background: Bool) -> DisplayList {
        var list = DisplayList()
        let context = PaintContext(origin: .zero, scale: scale)
        let style = UIScreen.main.traitCollection.userInterfaceStyle
        // The screen behind the windows is black, as on a device.
        if background { list.append(.fillRect(context.absoluteRect(UIScreen.main.bounds), .black)) }
        for window in windows where !window.isHidden {
            window.layer.paint(into: &list, context: context, style: style)
        }
        return list
    }

    public func imageLoadDidFinish() { setNeedsFrame() }

    // MARK: Timers (long presses; `Timer` does not fire on wasm)

    public final class Timer {
        var remaining: Double
        let action: @MainActor () -> Void
        var cancelled = false
        init(remaining: Double, action: @escaping @MainActor () -> Void) { self.remaining = remaining; self.action = action }
        public func cancel() { cancelled = true }
    }

    private var timers: [Timer] = []

    /// Runs `action` after `seconds` of frame time.
    @discardableResult
    public func schedule(after seconds: Double, _ action: @escaping @MainActor () -> Void) -> Timer {
        let timer = Timer(remaining: seconds, action: action)
        timers.append(timer)
        setNeedsFrame()
        return timer
    }

    private func runTimers(elapsed: Double) {
        guard !timers.isEmpty else { return }
        for timer in timers where !timer.cancelled {
            timer.remaining -= elapsed
        }
        let due = timers.filter { !$0.cancelled && $0.remaining <= 0 }
        timers.removeAll { $0.cancelled || $0.remaining <= 0 }
        for timer in due { timer.action() }
        if !timers.isEmpty { setNeedsFrame() }
    }

    // MARK: Touches

    private let touches = TouchRouter()

    public func pointerDown(at point: CGPoint, type: PointerType, time: Double) {
        guard let window = windows.last(where: { !$0.isHidden }) else { return }
        touches.pointerDown(at: point, in: window, type: type, time: time)
    }

    public func pointerMoved(to point: CGPoint, time: Double) {
        touches.pointerMoved(to: point, time: time)
    }

    public func pointerLeft() {}

    public func pointerUp(at point: CGPoint, time: Double) {
        touches.pointerUp(at: point, time: time, cancelled: point.x < 0 && point.y < 0)
    }

    public func secondaryPointerDown(at point: CGPoint) {}

    public func scrollWheel(by delta: CGSize, at point: CGPoint) {
        guard let window = windows.last(where: { !$0.isHidden }) else { return }
        var view = window.hitTest(point, with: nil)
        while let v = view {
            if let scroll = v as? UIScrollView, scroll.isScrollEnabled {
                if scroll.scroll(by: delta) { setNeedsFrame(); return }
            }
            view = v.superview
        }
    }

    public func keyDown(_ event: KeyEvent) -> Bool { false }
    public var pointerCursor: String? { nil }

    // MARK: Semantics

    /// Above every range SwiftUIWeb's own elements use (its static elements sit at
    /// 10_000_000 plus 23 bits), so a hosted tree's identifiers never collide with the host's.
    nonisolated(unsafe) private static var identifierCounter = 20_000_000

    static func nextSemanticsIdentifier() -> Int {
        identifierCounter += 1
        return identifierCounter
    }

    public func semanticsTree() -> [SemanticsNode] {
        var nodes: [SemanticsNode] = []
        for window in windows where !window.isHidden {
            window.collectSemantics(into: &nodes)
        }
        return nodes
    }

    private func view(withSemanticsIdentifier identifier: Int) -> UIView? {
        for window in windows {
            if let found = window.descendant(withSemanticsIdentifier: identifier) { return found }
        }
        return nil
    }

    public func activate(semanticsIdentifier: Int) {
        guard let view = view(withSemanticsIdentifier: semanticsIdentifier) else { return }
        view.accessibilityActivate()
        setNeedsFrame()
    }

    public func adjust(semanticsIdentifier: Int, increment: Bool) {
        guard let view = view(withSemanticsIdentifier: semanticsIdentifier) else { return }
        if increment { view.accessibilityIncrement() } else { view.accessibilityDecrement() }
        setNeedsFrame()
    }

    public func setValue(semanticsIdentifier: Int, value: Double) {
        guard let view = view(withSemanticsIdentifier: semanticsIdentifier) else { return }
        view.accessibilitySetValue(value)
        setNeedsFrame()
    }

    public func focus(semanticsIdentifier: Int?, keyboard: Bool) {
        guard let semanticsIdentifier, let view = view(withSemanticsIdentifier: semanticsIdentifier) else { return }
        if view.canBecomeFirstResponder { _ = view.becomeFirstResponder() }
    }

    public func blur(semanticsIdentifier: Int) {
        guard let view = view(withSemanticsIdentifier: semanticsIdentifier), view.isFirstResponder else { return }
        _ = view.resignFirstResponder()
    }

    public var focusedIdentifier: Int? { (firstResponder as? UIView)?.semanticsIdentifier }
    public var focusedTextFieldIdentifier: Int? { (firstResponder as? UITextField)?.semanticsIdentifier }

    public func textField(_ semanticsIdentifier: Int, didChange text: String) {
        (view(withSemanticsIdentifier: semanticsIdentifier) as? UITextField)?.hostDidChange(text)
        setNeedsFrame()
    }

    public func textFieldDidSubmit(_ semanticsIdentifier: Int) {
        (view(withSemanticsIdentifier: semanticsIdentifier) as? UITextField)?.hostDidSubmit()
        setNeedsFrame()
    }

    public func textField(_ semanticsIdentifier: Int, focused: Bool) {
        guard let field = view(withSemanticsIdentifier: semanticsIdentifier) as? UITextField else { return }
        if focused { _ = field.becomeFirstResponder() } else if field.isFirstResponder { _ = field.resignFirstResponder() }
        setNeedsFrame()
    }
}

/// The engine before a host installs one: nothing measures, so layout stays finite.
@MainActor
final class PlaceholderTextEngine: TextEngine {
    func layout(_ runs: [StyledRun], options: TextLayoutOptions, width: CGFloat?) -> TextLayout {
        TextLayout(size: .zero, firstBaseline: 0, lastBaseline: 0, lines: [])
    }
    func metrics(for font: ResolvedFont) -> FontMetrics { .plain }
}

extension UIView {
    /// Publishes this view's window frame under `name` in the scene's probe frames (tests and
    /// the gallery read them like SwiftUIWeb's `_probe`).
    public func publishFrame(as name: String) {
        UIKitScene.shared.probes[name] = convert(bounds, to: nil)
    }

    /// The semantics node for this view, or nil when it is not an accessibility element.
    func semanticsNode() -> SemanticsNode? {
        guard isAccessibilityElement else { return nil }
        let frame = convert(bounds, to: nil)
        let role: SemanticsNode.Role
        let traits = accessibilityTraits
        if traits.contains(.button) { role = .button }
        else if traits.contains(.link) { role = .link }
        else if traits.contains(.image) { role = .image }
        else if traits.contains(.header) { role = .heading }
        else if traits.contains(.adjustable) { role = .slider }
        else if self is UITextField { role = .textField }
        else if self is UISwitch { role = .switch }
        else { role = .text }
        var node = SemanticsNode(role: role, label: accessibilityLabel ?? "", frame: frame, identifier: semanticsIdentifier)
        node.value = accessibilityValue
        node.hint = accessibilityHint
        node.accessibilityIdentifier = accessibilityIdentifier
        node.isAdjustable = traits.contains(.adjustable)
        decorateSemantics(&node)
        return node
    }
}
