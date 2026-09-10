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
    var firstResponder: UIResponder?

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

    /// Drops every window (tests mount one fixture after another in the shared scene).
    public func removeAllWindows() {
        for window in windows { window.rootViewController?.viewIfLoaded?.removeFromSuperview() }
        windows.removeAll()
        delegateWindow = nil
        firstResponder = nil
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
    public var isAnimating: Bool { false }
    public var windowTitle: String? { nil }
    public var probeFrames: [String: CGRect] { probes }
    /// Frames published under a name for tests (`UIView.publishFrame(as:)`).
    var probes: [String: CGRect] = [:]

    /// Asks the host for a frame.
    public func setNeedsFrame() {
        guard !needsFrame else { return }
        needsFrame = true
        onNeedsFrame?()
    }

    public func advanceFrame(elapsed: Double) -> Bool {
        runTimers(elapsed: elapsed)
        return false
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

    private var activeTouch: UITouch?
    private var activeEvent: UIEvent?
    private var lastTapTime: Double = 0
    private var lastTapLocation = CGPoint.zero

    public func pointerDown(at point: CGPoint, type: PointerType, time: Double) {
        guard let window = windows.last(where: { !$0.isHidden }) else { return }
        let hit = window.hitTest(window.convert(point, from: nil), with: nil)
        let touch = UITouch(at: point, in: window, view: hit, type: type == .touch ? .direct : .indirectPointer, timestamp: time)
        if time - lastTapTime < 0.35, abs(point.x - lastTapLocation.x) < 20, abs(point.y - lastTapLocation.y) < 20 { touch.tapCount = 2 }
        lastTapTime = time
        lastTapLocation = point
        let event = UIEvent(type: .touches, timestamp: time)
        event.touches = [touch]
        activeTouch = touch
        activeEvent = event
        // Gesture recognizers on the hit view and its ancestors see the touch first.
        var recognizers: [UIGestureRecognizer] = []
        var view: UIView? = hit
        while let v = view {
            recognizers += (v.gestureRecognizers ?? []).filter { $0.isEnabled && ($0.delegate?.gestureRecognizer($0, shouldReceive: touch) ?? true) }
            view = v.superview
        }
        touch.gestureRecognizers = recognizers
        for recognizer in recognizers { recognizer.touchesBegan([touch], with: event) }
        if !recognizers.contains(where: { $0.hasRecognized && $0.cancelsTouchesInView }) {
            hit?.touchesBegan([touch], with: event)
        }
        // A press outside the first responder ends its editing.
        if let responder = firstResponder as? UIView, hit !== responder, !(hit?.isDescendant(of: responder) ?? false) {
            _ = responder.resignFirstResponder()
        }
        setNeedsFrame()
    }

    public func pointerMoved(to point: CGPoint, time: Double) {
        guard let touch = activeTouch, let event = activeEvent else { return }
        touch.previousWindowLocation = touch.windowLocation
        touch.windowLocation = point
        touch.timestamp = time
        touch.phase = .moved
        let wasRecognized = touch.gestureRecognizers?.contains { $0.hasRecognized && $0.cancelsTouchesInView } ?? false
        for recognizer in touch.gestureRecognizers ?? [] { recognizer.touchesMoved([touch], with: event) }
        let recognized = touch.gestureRecognizers?.contains { $0.hasRecognized && $0.cancelsTouchesInView } ?? false
        if recognized, !wasRecognized {
            touch.phase = .cancelled
            touch.view?.touchesCancelled([touch], with: event)
            touch.phase = .moved
        } else if !recognized {
            touch.view?.touchesMoved([touch], with: event)
        }
        setNeedsFrame()
    }

    public func pointerLeft() {}

    public func pointerUp(at point: CGPoint, time: Double) {
        guard let touch = activeTouch, let event = activeEvent else { return }
        touch.previousWindowLocation = touch.windowLocation
        touch.windowLocation = point
        touch.timestamp = time
        let recognized = touch.gestureRecognizers?.contains { $0.hasRecognized && $0.cancelsTouchesInView } ?? false
        touch.phase = point.x < 0 && point.y < 0 ? .cancelled : .ended
        if touch.phase == .cancelled {
            for recognizer in touch.gestureRecognizers ?? [] { recognizer.touchesCancelled([touch], with: event) }
            if !recognized { touch.view?.touchesCancelled([touch], with: event) }
        } else {
            for recognizer in touch.gestureRecognizers ?? [] { recognizer.touchesEnded([touch], with: event) }
            let nowRecognized = touch.gestureRecognizers?.contains { $0.cancelsTouchesInView && $0.hasRecognizedThisFrame } ?? false
            if !recognized {
                if nowRecognized { touch.view?.touchesCancelled([touch], with: event) } else { touch.view?.touchesEnded([touch], with: event) }
            }
        }
        for recognizer in touch.gestureRecognizers ?? [] { recognizer.hasRecognizedThisFrame = false }
        activeTouch = nil
        activeEvent = nil
        setNeedsFrame()
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

    nonisolated(unsafe) private static var identifierCounter = 0

    static func nextSemanticsIdentifier() -> Int {
        identifierCounter += 1
        return identifierCounter
    }

    public func semanticsTree() -> [SemanticsNode] {
        var nodes: [SemanticsNode] = []
        for window in windows where !window.isHidden {
            collectSemantics(of: window, into: &nodes)
        }
        return nodes
    }

    private func collectSemantics(of view: UIView, into nodes: inout [SemanticsNode]) {
        guard !view.isHidden, view.alpha > 0.01, !view.accessibilityElementsHidden else { return }
        if let node = view.semanticsNode() {
            nodes.append(node)
            if !(view is UIControl) { for subview in view.subviews { collectSemantics(of: subview, into: &nodes) } }
            return
        }
        for subview in view.subviews { collectSemantics(of: subview, into: &nodes) }
    }

    private func view(withSemanticsIdentifier identifier: Int) -> UIView? {
        for window in windows {
            if let found = find(in: window, identifier: identifier) { return found }
        }
        return nil
    }

    private func find(in view: UIView, identifier: Int) -> UIView? {
        if view.semanticsIdentifier == identifier { return view }
        for subview in view.subviews {
            if let found = find(in: subview, identifier: identifier) { return found }
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
