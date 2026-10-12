#if canImport(AppKit)
import AppKit
import ImageIO
import SwiftUIWebCore
import UniformTypeIdentifiers
@_exported import WebGraphicsNative

/// A SwiftUI `Runtime` in an AppKit window: the substrate's `NativeSceneHost` (decision 0014)
/// with the runtime as its scene, the window background painted, the toolbar painted without
/// its title (the window has a title bar), and links and share sheets wired to the system.
@MainActor
public final class NativeHost {
    public let runtime: Runtime = {
        let runtime = Runtime()
        runtime.paintsWindowBackground = true
        // The window has its own title bar: the toolbar items are painted, the title is not.
        runtime.paintsWindowChrome = true
        runtime.chromeShowsTitle = false
        return runtime
    }()
    public let host: NativeSceneHost
    private let root: @MainActor () -> AnyView

    public var textEngine: CoreTextEngine { host.textEngine }
    public var painter: CoreGraphicsPainter { host.painter }
    /// The real windows for the runtime's window presentations (pf-native-text).
    public private(set) var realWindows: RealWindowHost?
    public var view: RuntimeView! { host.view }

    public init(size: CGSize, root: @escaping @MainActor () -> AnyView) {
        self.root = root
        host = NativeSceneHost(size: size, scene: runtime)
        let host = self.host
        // A recorded drawing becomes PNG data through the painter (`UIImage.pngData()`).
        runtime.imageRasterizer = { list, size, scale in Self.png(of: list, size: size, scale: scale, painter: host.painter) }
        host.prepare = { [weak self] in
            guard let self else { return }
            OpenURLAction.systemHandler = { url in host.openURL(url) }
            ShareAction.systemHandler = { request in host.share(items: request.strings, subject: request.subject, message: request.message, files: request.files) }
            // AppKit representables' views live in the window over the painted content (ix-appkit).
            self.runtime.nativeViewHost = AppKitViewHost(view: host.view)
            // Window presentations open as windows of their own (pf-native-text).
            let windows = RealWindowHost(runtime: self.runtime, host: host)
            self.realWindows = windows
            self.runtime.realWindowHost = windows
            host.onFrame = { [weak windows] in windows?.redisplay() }
            // Open windows are remembered in the defaults and reopened at the next launch; the
            // app's menu commands make the menu bar (sw-windows).
            self.runtime.windowStateStore = (get: { UserDefaults.standard.string(forKey: "swiftuiweb.windows") },
                                             set: { UserDefaults.standard.set($0, forKey: "swiftuiweb.windows") })
            // Documents go through the open and save panels (sw-windows).
            self.runtime.documentOpenHandler = { types, completion in
                let panel = NSOpenPanel()
                panel.allowedContentTypes = types.compactMap { type in
                    UniformTypeIdentifiers.UTType(type.identifier) ?? type.preferredFilenameExtension.flatMap { UniformTypeIdentifiers.UTType(filenameExtension: $0) }
                }
                panel.allowsMultipleSelection = false
                guard panel.runModal() == .OK, let url = panel.url, let data = try? Data(contentsOf: url) else { return }
                completion(data, url.lastPathComponent, url)
            }
            self.runtime.documentSaveHandler = { data, name, _, existing in
                let url: URL
                if let existing {
                    url = existing
                } else {
                    let panel = NSSavePanel()
                    panel.nameFieldStringValue = name
                    guard panel.runModal() == .OK, let chosen = panel.url else { return nil }
                    url = chosen
                }
                return (try? data.write(to: url)) != nil ? url : nil
            }
            self.runtime.mount(self.root())
            self.runtime.restoreWindows()
            self.installMenuBar()
        }
    }

    // MARK: Menu bar (sw-windows)

    private var menuSignature: [String] = []

    /// Builds `NSApp.mainMenu` from the app's command menus: the app menu (Quit), the standard
    /// File, Edit, View, Window and Help menus a `CommandGroup` placement names (created when
    /// one does), and each `CommandMenu` in order. Items run their controls through the
    /// runtime; the bar is rebuilt when the items' labels or states change.
    func installMenuBar() {
        // Only a running application has a menu bar (tests host views without one).
        guard let app = NSApp as NSApplication? else { return }
        let menus = runtime.commandMenus
        let signature = menus.flatMap { menu in [menu.title] + menu.items.map { "\($0.label ?? "-")|\($0.isEnabled)|\($0.isOn.map(String.init) ?? "")" } }
        guard signature != menuSignature || app.mainMenu == nil else { return }
        menuSignature = signature
        let main = NSMenu()
        let appName = ProcessInfo.processInfo.processName
        let appMenu = NSMenu(title: appName)
        appMenu.addItem(withTitle: "Quit \(appName)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let appItem = NSMenuItem(); appItem.submenu = appMenu; main.addItem(appItem)
        var standard: [String: NSMenu] = [:]
        func standardMenu(_ title: String) -> NSMenu {
            if title == "App" { return appMenu }
            if let menu = standard[title] { return menu }
            let menu = NSMenu(title: title)
            standard[title] = menu
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: ""); item.submenu = menu; main.addItem(item)
            return menu
        }
        for menu in menus {
            let target: NSMenu
            if menu.placement != nil {
                target = standardMenu(menu.title)
                if !target.items.isEmpty { target.addItem(.separator()) }
            } else {
                target = NSMenu(title: menu.title)
                let item = NSMenuItem(title: menu.title, action: nil, keyEquivalent: ""); item.submenu = target; main.addItem(item)
            }
            for entry in menu.items {
                guard let label = entry.label else { target.addItem(.separator()); continue }
                let item = NSMenuItem(title: label, action: #selector(runMenuCommand(_:)), keyEquivalent: entry.shortcut.map { String($0.key.character) } ?? "")
                if let shortcut = entry.shortcut {
                    var flags: NSEvent.ModifierFlags = []
                    if shortcut.modifiers.contains(.command) { flags.insert(.command) }
                    if shortcut.modifiers.contains(.shift) { flags.insert(.shift) }
                    if shortcut.modifiers.contains(.option) { flags.insert(.option) }
                    if shortcut.modifiers.contains(.control) { flags.insert(.control) }
                    item.keyEquivalentModifierMask = flags
                }
                item.target = self
                item.tag = entry.identifier
                item.isEnabled = entry.isEnabled
                if let on = entry.isOn { item.state = on ? .on : .off }
                target.addItem(item)
            }
        }
        app.mainMenu = main
    }

    @objc private func runMenuCommand(_ sender: NSMenuItem) {
        runtime.performCommand(identifier: sender.tag)
        view?.needsDisplay = true
        installMenuBar()
    }

    /// The display list painted into an sRGB bitmap of `size` points at `scale`, as PNG data.
    static func png(of list: DisplayList, size: CGSize, scale: CGFloat, painter: CoreGraphicsPainter) -> Data? {
        let width = Int((size.width * scale).rounded()), height = Int((size.height * scale).rounded())
        guard width > 0, height > 0,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: scale, y: -scale)
        painter.paint(list, into: context)
        guard let image = context.makeImage() else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    /// Runs the application with `root` as the window's content. Never returns.
    public static func launch(size: CGSize = CGSize(width: 800, height: 600), windows: [_WindowDescriptor] = [],
                              _ root: @escaping @MainActor () -> AnyView) -> Never {
        let host = NativeHost(size: NativeSceneHost.windowSize(default: size), root: root)
        host.runtime.installWindows(windows)
        retained = host
        host.host.run()
    }

    nonisolated(unsafe) private static var retained: NativeHost?

    /// Installs the text engine and assets, mounts the root view and creates the view that
    /// paints it (no window: tests drive the view directly).
    @discardableResult
    public func makeView(assetManifest: URL? = nil) -> RuntimeView {
        host.makeView(assetManifest: assetManifest)
    }
}

/// Places the `NSView`s AppKit representables make as subviews of the runtime's view at their
/// nodes' frames (the view is flipped, so the scene's coordinates are its own), sizes them by
/// their fitting size, and removes them when their nodes unmount (ix-appkit, decision 0018).
@MainActor
final class AppKitViewHost: _NativeViewHosting {
    private weak var view: NSView?
    init(view: NSView) { self.view = view }

    func attach(_ object: AnyObject, frame: CGRect) {
        guard let subview = object as? NSView, let view else { return }
        subview.frame = frame
        subview.autoresizingMask = []
        view.addSubview(subview)
    }

    func move(_ object: AnyObject, to frame: CGRect) {
        guard let subview = object as? NSView else { return }
        if subview.superview == nil, let view { view.addSubview(subview) }
        subview.frame = frame
    }

    func detach(_ object: AnyObject) { (object as? NSView)?.removeFromSuperview() }

    func fittingSize(of object: AnyObject, proposal: ProposedViewSize) -> CGSize? {
        guard let subview = object as? NSView else { return nil }
        var size = subview.fittingSize
        if size.width <= 0 || size.height <= 0 { size = subview.intrinsicContentSize }
        guard size.width > 0 || size.height > 0 else { return nil }
        if let width = proposal.width, size.width <= 0 || size.width > width { size.width = width }
        if let height = proposal.height, size.height <= 0 || size.height > height { size.height = height }
        return CGSize(width: max(0, size.width), height: max(0, size.height))
    }

    func view(of controller: AnyObject) -> AnyObject? { (controller as? NSViewController)?.view }
}


/// The runtime's `.window` presentations as real `NSWindow`s (pf-native-text): one per
/// presentation, opened where the presentation would sit (cascaded from the main window),
/// its content view painting the presentation's content through
/// `Runtime.render(hostedWindow:scale:)`, its pointer and key events reaching the runtime
/// in root coordinates, closing dismissing the presentation and resizing following it.
@MainActor
public final class RealWindowHost: NSObject, _RealWindowHosting, NSWindowDelegate {
    private unowned let runtime: Runtime
    private unowned let host: NativeSceneHost
    private var windows: [Int: (window: NSWindow, view: HostedWindowView)] = [:]
    private var closing: Set<Int> = []
    /// The windows the runtime has, by identity, as last synced.
    public var openWindowIdentifiers: [Int] { Array(windows.keys) }

    init(runtime: Runtime, host: NativeSceneHost) {
        self.runtime = runtime
        self.host = host
    }

    public func syncWindows(_ list: [_HostedWindow]) {
        let wanted = Set(list.map(\.id))
        for (id, entry) in windows where !wanted.contains(id) {
            closing.insert(id)
            entry.window.orderOut(nil)
            entry.window.delegate = nil
            windows[id] = nil
            closing.remove(id)
        }
        for (index, description) in list.enumerated() {
            if let entry = windows[description.id] {
                entry.view.hosted = description
                if entry.window.title != (description.title ?? "") { entry.window.title = description.title ?? "" }
                if entry.window.contentView?.bounds.size != description.contentSize { entry.window.setContentSize(description.contentSize) }
                entry.view.needsDisplay = true
                continue
            }
            let style: NSWindow.StyleMask = description.resizable ? [.titled, .closable, .miniaturizable, .resizable] : [.titled, .closable, .miniaturizable]
            let window = NSWindow(contentRect: CGRect(origin: .zero, size: description.contentSize), styleMask: style, backing: .buffered, defer: false)
            window.title = description.title ?? ""
            window.isReleasedWhenClosed = false
            if description.hidesTitleBar { window.titlebarAppearsTransparent = true; window.titleVisibility = .hidden }
            let view = HostedWindowView(runtime: runtime, host: host, description: description)
            window.contentView = view
            window.delegate = self
            // Cascaded from the main window's origin.
            if let main = host.view.window {
                let origin = CGPoint(x: main.frame.minX + 24 * CGFloat(index + 1), y: main.frame.maxY - description.contentSize.height - 24 * CGFloat(index + 1) - 28)
                window.setFrameOrigin(origin)
            } else {
                window.center()
            }
            windows[description.id] = (window, view)
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(view)
        }
    }

    /// Every hosted window repaints with the main view's frame.
    func redisplay() {
        for entry in windows.values { entry.view.needsDisplay = true }
    }

    private func identifier(of window: NSWindow) -> Int? { windows.first { $0.value.window === window }?.key }

    public func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, let id = identifier(of: window), !closing.contains(id) else { return }
        windows[id] = nil
        runtime.hostedWindowDidClose(id)
        host.requestFrame()
    }

    public func windowDidResize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, let id = identifier(of: window), let content = window.contentView else { return }
        runtime.hostedWindow(id, didResizeTo: content.bounds.size)
        host.requestFrame()
    }

    public func windowDidBecomeKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, let id = identifier(of: window) else { return }
        runtime.hostedWindowDidBecomeKey(id)
    }
}

/// A hosted window's content: the presentation painted at its content origin, events into
/// the runtime at root coordinates, keys through the main view's input client (the focused
/// field is the scene's).
@MainActor
final class HostedWindowView: NSView {
    private unowned let runtime: Runtime
    private unowned let host: NativeSceneHost
    var hosted: _HostedWindow

    init(runtime: Runtime, host: NativeSceneHost, description: _HostedWindow) {
        self.runtime = runtime
        self.host = host
        hosted = description
        super.init(frame: CGRect(origin: .zero, size: description.contentSize))
        wantsLayer = true
    }
    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        host.painter.paint(runtime.render(hostedWindow: hosted.id, scale: window?.backingScaleFactor ?? 2), into: ctx)
    }

    private func rootPoint(_ event: NSEvent) -> CGPoint {
        let local = convert(event.locationInWindow, from: nil)
        return CGPoint(x: local.x + hosted.contentOrigin.x, y: local.y + hosted.contentOrigin.y)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        runtime.pointerDown(at: rootPoint(event), type: .mouse, time: event.timestamp)
        host.requestFrame()
    }
    override func mouseDragged(with event: NSEvent) { runtime.pointerMoved(to: rootPoint(event), time: event.timestamp); host.requestFrame() }
    override func mouseUp(with event: NSEvent) { runtime.pointerUp(at: rootPoint(event), time: event.timestamp); host.requestFrame() }
    override func mouseMoved(with event: NSEvent) { runtime.pointerMoved(to: rootPoint(event), time: event.timestamp); host.requestFrame() }
    override func scrollWheel(with event: NSEvent) {
        runtime.scrollWheel(by: CGSize(width: -event.scrollingDeltaX, height: -event.scrollingDeltaY), at: rootPoint(event))
        host.requestFrame()
    }
    /// Keys go to the main view, whose input client edits the scene's focused field.
    override func keyDown(with event: NSEvent) { host.view.keyDown(with: event); host.requestFrame() }
    override func keyUp(with event: NSEvent) { host.view.keyUp(with: event) }
}
#endif
