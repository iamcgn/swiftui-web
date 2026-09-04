#if canImport(AppKit)
import AppKit
import SwiftUIWebCore
import SwiftUIWebHeadless

/// Hosts a `Runtime` in an AppKit window: a flipped `NSView` lays out and paints the display
/// list with `CoreGraphicsPainter` in `draw(_:)`, forwards mouse, scroll and key events, and
/// keeps frames coming while the runtime animates (Docs/ROADMAP.md, Phase 4.2).
///
/// Environment for scripts: `SWIFTUIWEB_SCREENSHOT=out.png` writes the first frame and quits,
/// `SWIFTUIWEB_TIMEOUT=seconds` quits after that long, `SWIFTUIWEB_ASSETS=manifest.json` loads
/// an asset manifest (images relative to its directory), `SWIFTUIWEB_SIZE=WxH` sets the window.
@MainActor
public final class NativeHost: NSObject, NSApplicationDelegate {
    public let runtime = Runtime()
    public let textEngine = CoreTextEngine()
    public let painter: CoreGraphicsPainter
    private let root: @MainActor () -> AnyView
    private let size: CGSize
    private var window: NSWindow!
    private var view: RuntimeView!

    public init(size: CGSize, root: @escaping @MainActor () -> AnyView) {
        self.root = root
        self.size = size
        painter = CoreGraphicsPainter(textEngine: textEngine)
        super.init()
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

    public func applicationDidFinishLaunching(_ notification: Notification) {
        runtime.textEngine = textEngine
        let environment = ProcessInfo.processInfo.environment
        if let manifest = environment["SWIFTUIWEB_ASSETS"] {
            let url = URL(fileURLWithPath: manifest)
            if let catalog = try? AssetCatalog(contentsOf: url) {
                runtime.assetCatalog = catalog
                painter.assetBase = url.deletingLastPathComponent()
            } else {
                FileHandle.standardError.write(Data("SwiftUIWeb: could not read the asset manifest at \(manifest)\n".utf8))
            }
        }
        view = RuntimeView(frame: NSRect(origin: .zero, size: size), host: self)
        window = NSWindow(contentRect: view.frame, styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = ProcessInfo.processInfo.processName
        window.contentView = view
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(view)
        NSApp.activate(ignoringOtherApps: true)
        runtime.scheduler.onNeedsFlush = { [weak self] in self?.view.needsDisplay = true }
        runtime.mount(root())
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
}

/// The window's content: paints the runtime and forwards input in the runtime's coordinates
/// (points from the top left, which a flipped view gives directly).
@MainActor
final class RuntimeView: NSView {
    unowned let host: NativeHost
    private var trackingArea: NSTrackingArea?

    init(frame: NSRect, host: NativeHost) {
        self.host = host
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        NSColor.white.setFill()
        bounds.fill()
        host.paintFrame(into: ctx, size: bounds.size) { [weak self] title in self?.window?.title = title }
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsDisplay = true
    }

    private func point(_ event: NSEvent) -> CGPoint { convert(event.locationInWindow, from: nil) }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        host.runtime.pointerDown(at: point(event), type: .mouse, time: event.timestamp)
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        host.runtime.pointerMoved(to: point(event), time: event.timestamp)
        if host.runtime.needsFrame { needsDisplay = true }
    }

    override func mouseUp(with event: NSEvent) {
        host.runtime.pointerUp(at: point(event), time: event.timestamp)
        needsDisplay = true
    }

    override func rightMouseDown(with event: NSEvent) {
        host.runtime.secondaryPointerDown(at: point(event))
        needsDisplay = true
    }

    override func scrollWheel(with event: NSEvent) {
        // AppKit's deltas are positive when the content should move down; the runtime scrolls
        // the content up for a positive delta (wheel semantics), so flip them.
        let factor: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 16
        let delta = CGSize(width: -event.scrollingDeltaX * factor, height: -event.scrollingDeltaY * factor)
        host.runtime.scrollWheel(by: delta, at: point(event))
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        guard let key = Self.keyEquivalent(event) else { return super.keyDown(with: event) }
        var modifiers: EventModifiers = []
        if event.modifierFlags.contains(.shift) { modifiers.insert(.shift) }
        if event.modifierFlags.contains(.control) { modifiers.insert(.control) }
        if event.modifierFlags.contains(.option) { modifiers.insert(.option) }
        if event.modifierFlags.contains(.command) { modifiers.insert(.command) }
        if event.modifierFlags.contains(.capsLock) { modifiers.insert(.capsLock) }
        if event.modifierFlags.contains(.numericPad) { modifiers.insert(.numericPad) }
        if event.modifierFlags.contains(.function) { modifiers.insert(.function) }
        let characters = event.charactersIgnoringModifiers ?? ""
        let keyEvent = KeyEvent(key: key, characters: characters.count == 1 && key.character.isLetter || key.character.isNumber ? characters : "",
                                modifiers: modifiers, isRepeat: event.isARepeat)
        if host.runtime.keyDown(keyEvent) { needsDisplay = true } else { super.keyDown(with: event) }
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
}
#endif
