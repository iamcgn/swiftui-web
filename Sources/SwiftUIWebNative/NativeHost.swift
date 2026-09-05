#if canImport(AppKit)
import AppKit
import SwiftUIWebCore
import SwiftUIWebHeadless

/// Hosts a `Runtime` in an AppKit window: a flipped `NSView` lays out and paints the display
/// list with `CoreGraphicsPainter` in `draw(_:)`, forwards mouse, scroll and key events, takes
/// text input for the focused text field (`NSTextInputClient`), exposes the semantics tree to
/// accessibility, and keeps frames coming while the runtime animates (decision 0012).
///
/// Environment for scripts: `SWIFTUIWEB_SCREENSHOT=out.png` writes the first frame and quits,
/// `SWIFTUIWEB_TIMEOUT=seconds` quits after that long, `SWIFTUIWEB_ASSETS=manifest.json` loads
/// an asset manifest (images relative to its directory), `SWIFTUIWEB_SIZE=WxH` sets the window.
@MainActor
public final class NativeHost: NSObject, NSApplicationDelegate {
    public let runtime: Runtime = {
        let runtime = Runtime()
        runtime.paintsWindowBackground = true
        // The window has its own title bar: the toolbar items are painted, the title is not.
        runtime.paintsWindowChrome = true
        runtime.chromeShowsTitle = false
        return runtime
    }()
    public let textEngine = CoreTextEngine()
    public let painter: CoreGraphicsPainter
    private let root: @MainActor () -> AnyView
    private let size: CGSize
    private var window: NSWindow?
    public private(set) var view: RuntimeView!

    public init(size: CGSize, root: @escaping @MainActor () -> AnyView) {
        self.root = root
        self.size = size
        painter = CoreGraphicsPainter(textEngine: textEngine)
        super.init()
        runtime.imageLoader = NativeImageLoader(painter: painter) { [weak self] in
            self?.runtime.imageLoadDidFinish()
            self?.scheduleFrame()
        }
    }

    /// Runs the application with `root` as the window's content. Never returns.
    public static func launch(size: CGSize = CGSize(width: 800, height: 600), _ root: @escaping @MainActor () -> AnyView) -> Never {
        let environment = ProcessInfo.processInfo.environment
        var windowSize = size
        if let text = environment["SWIFTUIWEB_SIZE"], let x = text.firstIndex(of: "x"),
           let width = Double(text[..<x]), let height = Double(text[text.index(after: x)...]) {
            windowSize = CGSize(width: width, height: height)
        }
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let host = NativeHost(size: windowSize, root: root)
        app.delegate = host
        app.run()
        exit(0)
    }

    /// Installs the text engine and assets, mounts the root view and creates the view that
    /// paints it (no window: tests drive the view directly).
    @discardableResult
    public func makeView(assetManifest: URL? = nil) -> RuntimeView {
        if let view { return view }
        runtime.textEngine = textEngine
        if let manifest = assetManifest {
            if let catalog = try? AssetCatalog(contentsOf: manifest) {
                runtime.assetCatalog = catalog
                painter.assetBase = manifest.deletingLastPathComponent()
            } else {
                FileHandle.standardError.write(Data("SwiftUIWeb: could not read the asset manifest at \(manifest.path)\n".utf8))
            }
        }
        let view = RuntimeView(frame: NSRect(origin: .zero, size: size), host: self)
        self.view = view
        runtime.scheduler.onNeedsFlush = { [weak view] in view?.needsDisplay = true }
        OpenURLAction.systemHandler = { url in NSWorkspace.shared.open(url) }
        ShareAction.systemHandler = { [weak view] items, _ in
            guard let view else { return }
            let objects: [Any] = items.map { item -> Any in URL(string: item).flatMap { $0.scheme != nil ? $0 : nil } ?? item }
            let picker = NSSharingServicePicker(items: objects)
            picker.show(relativeTo: NSRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1), of: view, preferredEdge: .minY)
        }
        runtime.mount(root())
        return view
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        let environment = ProcessInfo.processInfo.environment
        let view = makeView(assetManifest: environment["SWIFTUIWEB_ASSETS"].map { URL(fileURLWithPath: $0) })
        let window = NSWindow(contentRect: view.frame, styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = ProcessInfo.processInfo.processName
        window.contentView = view
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(view)
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        view.needsDisplay = true
        if let text = environment["SWIFTUIWEB_TIMEOUT"], let seconds = Double(text) {
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { exit(0) }
        }
        if let path = environment["SWIFTUIWEB_SCREENSHOT"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.screenshot(to: URL(fileURLWithPath: path)) }
        }
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// Renders the view into a bitmap at the window's scale and writes a PNG, then quits.
    private func screenshot(to url: URL) {
        guard let representation = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { exit(70) }
        view.cacheDisplay(in: view.bounds, to: representation)
        guard let png = representation.representation(using: .png, properties: [:]) else { exit(70) }
        do {
            try png.write(to: url)
            print("SwiftUIWeb: wrote \(url.path)")
            exit(0)
        } catch {
            FileHandle.standardError.write(Data("SwiftUIWeb: could not write \(url.path): \(error)\n".utf8))
            exit(73)
        }
    }

    // MARK: Frames

    private var lastFrameTime: TimeInterval?
    private var frameScheduled = false

    /// Lays out and paints one frame into `ctx` (the view's flipped context), then keeps frames
    /// coming while animations run.
    fileprivate func paintFrame(into ctx: CGContext, size: CGSize, title: (String) -> Void) {
        let time = ProcessInfo.processInfo.systemUptime
        let elapsed = lastFrameTime.map { min(0.1, time - $0) } ?? 0
        lastFrameTime = time
        var animating = runtime.advanceScrollAnimations(elapsed: elapsed)
        animating = runtime.advanceAnimations(elapsed: elapsed) || animating
        runtime.layout(in: size)
        let scale = window?.backingScaleFactor ?? 2
        painter.paint(runtime.render(scale: scale), into: ctx)
        if let navigationTitle = runtime.navigationTitle { title(navigationTitle) }
        if animating || runtime.isAnimating || runtime.needsFrame { scheduleFrame() }
    }

    fileprivate func scheduleFrame() {
        guard !frameScheduled else { return }
        frameScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1 / 60) { [weak self] in
            guard let self else { return }
            self.frameScheduled = false
            self.view.needsDisplay = true
        }
    }

    // MARK: Text fields

    /// The focused text field's semantics, if a text field has focus.
    fileprivate var focusedTextField: SemanticsNode? {
        guard let id = runtime.focusedTextFieldIdentifier else { return nil }
        return runtime.semanticsTree().first { $0.identifier == id && $0.textInput != nil }
    }
}

/// The window's content: paints the runtime and forwards input in the runtime's coordinates
/// (points from the top left, which a flipped view gives directly).
@MainActor
public final class RuntimeView: NSView, @preconcurrency NSTextInputClient {
    unowned let host: NativeHost

    init(frame: NSRect, host: NativeHost) {
        self.host = host
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { nil }

    override public var isFlipped: Bool { true }
    override public var acceptsFirstResponder: Bool { true }

    override public func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        // The window follows the system appearance; the runtime paints the background.
        host.runtime.hostColorScheme = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .dark : .light
        host.paintFrame(into: ctx, size: bounds.size) { [weak self] title in self?.window?.title = title }
        drawCaret(in: ctx)
    }

    /// A caret after the focused text field's text (the runtime paints the text itself).
    private func drawCaret(in ctx: CGContext) {
        guard let field = host.focusedTextField, let input = field.textInput, input.isEnabled else { return }
        let shown = input.isSecure ? String(repeating: "•", count: input.text.count) : input.text
        ctx.setFillColor(NSColor.controlAccentColor.cgColor)
        if input.isMultiline {
            // After the last line of the editor (lines are the text's newlines; wrapping is not tracked).
            let lines = shown.split(separator: "\n", omittingEmptySubsequences: false)
            let x = input.textRect.minX + host.textEngine.advance(of: String(lines.last ?? ""), font: input.font)
            let baseline = input.textRect.minY + input.firstBaseline + CGFloat(lines.count - 1) * input.lineHeight
            ctx.fill(CGRect(x: x.rounded(), y: baseline - input.font.size, width: 1, height: input.font.size * 1.2))
        } else {
            let x = input.textRect.minX + host.textEngine.advance(of: shown, font: input.font)
            ctx.fill(CGRect(x: x.rounded(), y: input.textRect.minY, width: 1, height: input.textRect.height))
        }
    }

    override public func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsDisplay = true
    }

    // MARK: Pointer

    private func point(_ event: NSEvent) -> CGPoint { convert(event.locationInWindow, from: nil) }

    override public func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        host.runtime.pointerDown(at: point(event), type: .mouse, time: event.timestamp)
        needsDisplay = true
    }

    override public func mouseDragged(with event: NSEvent) {
        host.runtime.pointerMoved(to: point(event), time: event.timestamp)
        if host.runtime.needsFrame { needsDisplay = true }
    }

    // Hovering: a tracking area delivers moves between presses and the exit.
    private var trackingArea: NSTrackingArea?

    override public func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override public func mouseMoved(with event: NSEvent) {
        host.runtime.pointerMoved(to: point(event), time: event.timestamp)
        applyPointerStyle()
        if host.runtime.needsFrame { needsDisplay = true }
    }

    override public func mouseExited(with event: NSEvent) {
        host.runtime.pointerLeft()
        applyPointerStyle()
        if host.runtime.needsFrame { needsDisplay = true }
    }

    private func applyPointerStyle() {
        let cursor: NSCursor
        switch host.runtime.pointerStyle?.css {
        case "pointer": cursor = .pointingHand
        case "text": cursor = .iBeam
        case "vertical-text": cursor = .iBeamCursorForVerticalLayout
        case "grab": cursor = .openHand
        case "grabbing": cursor = .closedHand
        case "crosshair": cursor = .crosshair
        case "col-resize", "ew-resize": cursor = .resizeLeftRight
        case "row-resize", "ns-resize": cursor = .resizeUpDown
        case "w-resize": cursor = .resizeLeft
        case "e-resize": cursor = .resizeRight
        case "n-resize": cursor = .resizeUp
        case "s-resize": cursor = .resizeDown
        default: cursor = .arrow
        }
        if NSCursor.current != cursor { cursor.set() }
    }

    override public func mouseUp(with event: NSEvent) {
        host.runtime.pointerUp(at: point(event), time: event.timestamp)
        needsDisplay = true
    }

    override public func rightMouseDown(with event: NSEvent) {
        host.runtime.secondaryPointerDown(at: point(event))
        needsDisplay = true
    }

    override public func scrollWheel(with event: NSEvent) {
        // AppKit's deltas are positive when the content should move down; the runtime scrolls
        // the content up for a positive delta (wheel semantics), so flip them.
        let factor: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 16
        let delta = CGSize(width: -event.scrollingDeltaX * factor, height: -event.scrollingDeltaY * factor)
        host.runtime.scrollWheel(by: delta, at: point(event))
        needsDisplay = true
    }

    // MARK: Keys

    override public func keyDown(with event: NSEvent) {
        // A focused text field takes typing through the input context (dead keys, IME); the
        // commands it produces (newline, delete, arrows, escape) come back through `doCommand`.
        if host.focusedTextField != nil, !event.modifierFlags.contains(.command) {
            interpretKeyEvents([event])
            needsDisplay = true
            return
        }
        guard let key = Self.keyEquivalent(event) else { return super.keyDown(with: event) }
        if host.runtime.keyDown(Self.keyEvent(event, key: key)) { needsDisplay = true } else { super.keyDown(with: event) }
    }

    static func keyEvent(_ event: NSEvent, key: KeyEquivalent) -> KeyEvent {
        var modifiers: EventModifiers = []
        if event.modifierFlags.contains(.shift) { modifiers.insert(.shift) }
        if event.modifierFlags.contains(.control) { modifiers.insert(.control) }
        if event.modifierFlags.contains(.option) { modifiers.insert(.option) }
        if event.modifierFlags.contains(.command) { modifiers.insert(.command) }
        if event.modifierFlags.contains(.capsLock) { modifiers.insert(.capsLock) }
        if event.modifierFlags.contains(.numericPad) { modifiers.insert(.numericPad) }
        if event.modifierFlags.contains(.function) { modifiers.insert(.function) }
        let characters = event.charactersIgnoringModifiers ?? ""
        let printable = characters.count == 1 && (key.character.isLetter || key.character.isNumber || key.character.isPunctuation || key.character.isSymbol)
        return KeyEvent(key: key, characters: printable ? characters : "", modifiers: modifiers, isRepeat: event.isARepeat)
    }

    /// The key equivalent of a key event: special keys by their function-key code, others by
    /// their character.
    static func keyEquivalent(_ event: NSEvent) -> KeyEquivalent? {
        if let special = event.specialKey {
            switch special {
            case .upArrow: return .upArrow
            case .downArrow: return .downArrow
            case .leftArrow: return .leftArrow
            case .rightArrow: return .rightArrow
            case .home: return .home
            case .end: return .end
            case .pageUp: return .pageUp
            case .pageDown: return .pageDown
            case .delete, .backspace: return .delete
            case .deleteForward: return .deleteForward
            case .clearLine, .clearDisplay: return .clear
            case .tab, .backTab: return .tab
            case .enter, .carriageReturn, .newline: return .return
            default: return nil
            }
        }
        switch event.keyCode {
        case 53: return .escape
        case 36, 76: return .return
        case 48: return .tab
        case 51: return .delete
        case 117: return .deleteForward
        default: break
        }
        guard let characters = event.charactersIgnoringModifiers, let first = characters.first else { return nil }
        if first == " " { return .space }
        return KeyEquivalent(Character(first.lowercased()))
    }

    // MARK: NSTextInputClient (the focused text field's editor: typing at the end of the text)

    private func setFocusedText(_ text: String) {
        guard let field = host.focusedTextField else { return }
        host.runtime.textField(field.identifier, didChange: text)
        needsDisplay = true
    }

    public func insertText(_ string: Any, replacementRange: NSRange) {
        guard let field = host.focusedTextField, let input = field.textInput else { return }
        let inserted = (string as? NSAttributedString)?.string ?? (string as? String) ?? ""
        setFocusedText(input.text + inserted)
    }

    override public func doCommand(by selector: Selector) {
        guard let field = host.focusedTextField, let input = field.textInput else { return }
        switch selector {
        case #selector(NSResponder.deleteBackward(_:)), #selector(NSResponder.deleteWordBackward(_:)):
            setFocusedText(String(input.text.dropLast(selector == #selector(NSResponder.deleteWordBackward(_:)) ? input.text.split(separator: " ").last?.count ?? 1 : 1)))
        case #selector(NSResponder.insertNewline(_:)):
            host.runtime.textFieldDidSubmit(field.identifier)
            needsDisplay = true
        case #selector(NSResponder.cancelOperation(_:)):
            _ = host.runtime.keyDown(KeyEvent(key: .escape))
            needsDisplay = true
        case #selector(NSResponder.moveUp(_:)): _ = host.runtime.keyDown(KeyEvent(key: .upArrow))
        case #selector(NSResponder.moveDown(_:)): _ = host.runtime.keyDown(KeyEvent(key: .downArrow))
        case #selector(NSResponder.insertTab(_:)): _ = host.runtime.keyDown(KeyEvent(key: .tab))
        default: break
        }
    }

    public func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {}
    public func unmarkText() {}
    public func selectedRange() -> NSRange {
        let count = host.focusedTextField?.textInput?.text.utf16.count ?? 0
        return NSRange(location: count, length: 0)
    }
    public func markedRange() -> NSRange { NSRange(location: NSNotFound, length: 0) }
    public func hasMarkedText() -> Bool { false }
    public func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? { nil }
    public func validAttributesForMarkedText() -> [NSAttributedString.Key] { [] }
    public func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        guard let input = host.focusedTextField?.textInput else { return .zero }
        let rect = convert(input.textRect, to: nil)
        return window?.convertToScreen(rect) ?? rect
    }
    public func characterIndex(for point: NSPoint) -> Int { 0 }

    // MARK: Accessibility (the semantics tree as accessibility elements)

    override public func isAccessibilityElement() -> Bool { false }
    override public func accessibilityRole() -> NSAccessibility.Role? { .group }
    override public func accessibilityLabel() -> String? { "SwiftUI content" }

    override public func accessibilityChildren() -> [Any]? {
        accessibilityElements()
    }

    /// One `NSAccessibilityElement` per semantics node, positioned on screen when the view is in
    /// a window (in the view otherwise).
    public func accessibilityElements() -> [RuntimeAccessibilityElement] {
        host.runtime.semanticsTree().map { node in
            let frameInView = node.frame
            let frameInWindow = convert(frameInView, to: nil)
            let frame = window?.convertToScreen(frameInWindow) ?? frameInWindow
            let element = RuntimeAccessibilityElement(host: host, node: node)
            element.setAccessibilityFrame(frame)
            element.setAccessibilityParent(self)
            return element
        }
    }
}

/// An accessibility element for one semantics node: role, label, value, and press/adjust
/// actions that go back to the runtime.
@MainActor
public final class RuntimeAccessibilityElement: NSAccessibilityElement {
    unowned let host: NativeHost
    public let node: SemanticsNode

    init(host: NativeHost, node: SemanticsNode) {
        self.host = host
        self.node = node
        super.init()
        setAccessibilityRole(Self.role(for: node.role))
        setAccessibilityLabel(node.label)
        setAccessibilityElement(true)
        if let hint = node.hint { setAccessibilityHelp(hint) }
        if let identifier = node.accessibilityIdentifier { setAccessibilityIdentifier(identifier) }
        switch node.role {
        case .checkbox, .switch: setAccessibilityValue(node.isOn == true ? 1 : 0)
        case .slider, .stepper:
            if let range = node.range { setAccessibilityValue(range.value) } else if let value = node.value { setAccessibilityValue(value) }
        case .textField: setAccessibilityValue(node.textInput?.text ?? node.value ?? "")
        default: if let value = node.value { setAccessibilityValue(value) }
        }
        setAccessibilityEnabled(node.textInput?.isEnabled ?? true)
    }

    static func role(for role: SemanticsNode.Role) -> NSAccessibility.Role {
        switch role {
        case .button: return .button
        case .checkbox, .switch: return .checkBox
        case .textField: return .textField
        case .text: return .staticText
        case .heading: return .staticText
        case .image: return .image
        case .group: return .group
        case .link: return .link
        case .slider: return .slider
        case .stepper: return .incrementor
        case .popUpButton: return .popUpButton
        case .radioGroup, .segmented: return .radioGroup
        case .list: return .list
        }
    }

    override public nonisolated func accessibilityPerformPress() -> Bool {
        nonisolated(unsafe) let element = self
        return MainActor.assumeIsolated { element.accessibilityPerformPressOnMain() }
    }

    private func accessibilityPerformPressOnMain() -> Bool {
        switch node.role {
        case .text, .heading, .image, .group, .list: return false
        default:
            host.runtime.activate(semanticsIdentifier: node.identifier)
            host.view?.needsDisplay = true
            return true
        }
    }

    override public nonisolated func accessibilityPerformIncrement() -> Bool {
        nonisolated(unsafe) let element = self
        return MainActor.assumeIsolated { element.accessibilityPerformIncrementOnMain() }
    }

    private func accessibilityPerformIncrementOnMain() -> Bool {
        guard node.isAdjustable else { return false }
        host.runtime.adjust(semanticsIdentifier: node.identifier, increment: true)
        host.view?.needsDisplay = true
        return true
    }

    override public nonisolated func accessibilityPerformDecrement() -> Bool {
        nonisolated(unsafe) let element = self
        return MainActor.assumeIsolated { element.accessibilityPerformDecrementOnMain() }
    }

    private func accessibilityPerformDecrementOnMain() -> Bool {
        guard node.isAdjustable else { return false }
        host.runtime.adjust(semanticsIdentifier: node.identifier, increment: false)
        host.view?.needsDisplay = true
        return true
    }
}

/// Loads `AsyncImage` URLs off the main thread and hands the decoded images to the painter.
@MainActor
final class NativeImageLoader: _ImageLoading {
    private let painter: CoreGraphicsPainter
    private let didFinish: @MainActor () -> Void
    private var states: [String: _ImageLoadState] = [:]

    init(painter: CoreGraphicsPainter, didFinish: @escaping @MainActor () -> Void) {
        self.painter = painter
        self.didFinish = didFinish
    }

    func state(for url: String) -> _ImageLoadState {
        if let known = states[url] { return known }
        states[url] = .loading
        guard let parsed = URL(string: url) else { states[url] = .failed; return .failed }
        Task.detached { [weak self] in
            let data = try? Data(contentsOf: parsed)
            let image = data.flatMap { CGImageSourceCreateWithData($0 as CFData, nil) }.flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }
            await MainActor.run { [weak self] in
                guard let self else { return }
                if let image {
                    self.painter.register(image, for: url)
                    self.states[url] = .loaded(pixelSize: CGSize(width: image.width, height: image.height))
                } else {
                    self.states[url] = .failed
                }
                self.didFinish()
            }
        }
        return .loading
    }
}
#endif
