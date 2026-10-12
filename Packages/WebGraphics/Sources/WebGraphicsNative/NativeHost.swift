#if canImport(AppKit)
import AppKit
import UniformTypeIdentifiers
import WebGraphics
import WebGraphicsHeadless

/// Hosts a `HostedScene` in an AppKit window: a flipped `NSView` lays out and paints the display
/// list with `CoreGraphicsPainter` in `draw(_:)`, forwards mouse, scroll and key events, takes
/// text input for the focused text field (`NSTextInputClient`), exposes the semantics tree to
/// accessibility, and keeps frames coming while the scene animates (decisions 0012 and 0014).
///
/// Environment for scripts: `SWIFTUIWEB_SCREENSHOT=out.png` writes the first frame and quits,
/// `SWIFTUIWEB_TIMEOUT=seconds` quits after that long, `SWIFTUIWEB_ASSETS=manifest.json` loads
/// an asset manifest (images relative to its directory), `SWIFTUIWEB_SIZE=WxH` sets the window.
@MainActor
public final class NativeSceneHost: NSObject, NSApplicationDelegate {
    public let scene: any HostedScene
    public let textEngine = CoreTextEngine()
    public let painter: CoreGraphicsPainter
    /// Runs once the view exists and the engine and assets are installed, before the first
    /// frame: where a framework mounts its root content.
    public var prepare: (@MainActor () -> Void)?
    private let size: CGSize
    private var window: NSWindow?
    /// The view's size in points and the window's pixel scale (2 before a window exists).
    public var viewportSize: CGSize { view?.bounds.size ?? size }
    public var pixelScale: CGFloat { window?.backingScaleFactor ?? 2 }
    public private(set) var view: RuntimeView!

    public init(size: CGSize, scene: any HostedScene) {
        self.scene = scene
        self.size = size
        painter = CoreGraphicsPainter(textEngine: textEngine)
        super.init()
        scene.imageLoader = NativeImageLoader(painter: painter) { [weak self] in
            self?.scene.imageLoadDidFinish()
            self?.scheduleFrame()
        }
    }

    /// The window size scripts ask for (`SWIFTUIWEB_SIZE=WxH`), else `size`.
    public static func windowSize(default size: CGSize) -> CGSize {
        if let text = ProcessInfo.processInfo.environment["SWIFTUIWEB_SIZE"], let x = text.firstIndex(of: "x"),
           let width = Double(text[..<x]), let height = Double(text[text.index(after: x)...]) {
            return CGSize(width: width, height: height)
        }
        return size
    }

    /// Runs the application with this host as its delegate. Never returns.
    public func run() -> Never {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        app.delegate = self
        app.run()
        exit(0)
    }

    /// Opens `url` with the system.
    public func openURL(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    /// Shows the sharing picker for `items` (URLs as URLs, anything else as text) over the view.
    public func share(items: [String], subject: String?) {
        share(items: items, subject: subject, message: nil, files: [])
    }

    /// Shows the sharing picker for links, texts, the message, and data (images as `NSImage`s,
    /// other data written to a temporary file named after the item).
    public func share(items: [String], subject: String?, message: String?, files: [(data: [UInt8], name: String, mimeType: String)]) {
        guard let view else { return }
        var objects: [Any] = []
        if let message { objects.append(message) }
        objects += items.map { item -> Any in URL(string: item).flatMap { $0.scheme != nil ? $0 : nil } ?? item }
        for file in files {
            let data = Data(file.data)
            if file.mimeType.hasPrefix("image/"), let image = NSImage(data: data) {
                objects.append(image)
            } else {
                let url = FileManager.default.temporaryDirectory.appendingPathComponent(file.name)
                if (try? data.write(to: url)) != nil { objects.append(url) }
            }
        }
        let picker = NSSharingServicePicker(items: objects)
        picker.show(relativeTo: NSRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1), of: view, preferredEdge: .minY)
    }

    /// Installs the text engine and assets, creates the view that paints the scene and runs
    /// `prepare` (no window: tests drive the view directly).
    @discardableResult
    public func makeView(assetManifest: URL? = nil) -> RuntimeView {
        if let view { return view }
        scene.textEngine = textEngine
        if let manifest = assetManifest {
            if let catalog = try? AssetCatalog(contentsOf: manifest) {
                CoreTextEngine.registerFonts(catalog, base: manifest.deletingLastPathComponent())
                scene.assetCatalog = catalog
                painter.assetBase = manifest.deletingLastPathComponent()
            } else {
                FileHandle.standardError.write(Data("SwiftUIWeb: could not read the asset manifest at \(manifest.path)\n".utf8))
            }
        }
        let view = RuntimeView(frame: NSRect(origin: .zero, size: size), host: self)
        self.view = view
        scene.onNeedsFrame = { [weak view] in view?.needsDisplay = true }
        // A colour well opens the shared colour panel, which targets the well until it closes
        // or another well takes it (sw-colorpicker; the panel's changes are continuous).
        scene.colorPanelHandler = { [weak self] request in self?.showColorPanel(request) ?? false }
        // The share sheet and the open and save panels (uk-system-sheets).
        scene.shareHandler = { [weak self] request in
            self?.share(items: request.items, subject: request.subject, message: request.message, files: request.files.map { (data: Array($0.data), name: $0.name, mimeType: $0.mimeType) })
        }
        scene.fileOpenHandler = { request, completion in
            let panel = NSOpenPanel()
            panel.allowsMultipleSelection = request.allowsMultiple
            panel.canChooseDirectories = false
            if request.imagesOnly {
                panel.allowedContentTypes = [.image]
            } else if !request.extensions.isEmpty {
                panel.allowedContentTypes = request.extensions.compactMap { UTType(filenameExtension: $0) }
            }
            guard panel.runModal() == .OK else { completion([]); return }
            let files = panel.urls.compactMap { url -> HostFile? in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return HostFile(data: data, name: url.lastPathComponent, mimeType: UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream", url: url)
            }
            completion(files)
        }
        scene.fileSaveHandler = { file in
            let panel = NSSavePanel()
            panel.nameFieldStringValue = file.name
            guard panel.runModal() == .OK, let url = panel.url else { return }
            try? file.data.write(to: url)
        }
        prepare?()
        return view
    }

    private var colorPanelRequest: ColorPanelRequest?
    private var colorPanelObserver: NSObjectProtocol?

    /// Shows `NSColorPanel` for a well (`HostedScene.colorPanelHandler`).
    private func showColorPanel(_ request: ColorPanelRequest) -> Bool {
        if let previous = colorPanelRequest, previous.identifier != request.identifier { scene.colorPanelDidClose(previous.identifier) }
        colorPanelRequest = request
        let panel = NSColorPanel.shared
        panel.showsAlpha = request.supportsOpacity
        panel.isContinuous = true
        panel.color = NSColor(srgbRed: request.color.red, green: request.color.green, blue: request.color.blue, alpha: request.color.alpha)
        panel.setTarget(self)
        panel.setAction(#selector(colorPanelDidChange(_:)))
        if colorPanelObserver == nil {
            colorPanelObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: panel, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, let request = self.colorPanelRequest else { return }
                    self.colorPanelRequest = nil
                    self.scene.colorPanelDidClose(request.identifier)
                    self.view?.needsDisplay = true
                }
            }
        }
        panel.orderFront(nil)
        return true
    }

    @objc private func colorPanelDidChange(_ sender: Any?) {
        guard let request = colorPanelRequest, let color = NSColorPanel.shared.color.usingColorSpace(.sRGB) else { return }
        scene.colorPanel(request.identifier, didPick: RGBA(red: color.redComponent, green: color.greenComponent, blue: color.blueComponent,
                                                            alpha: request.supportsOpacity ? color.alphaComponent : 1))
        view?.needsDisplay = true
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
        let animating = scene.advanceFrame(elapsed: elapsed)
        scene.layout(in: size)
        let scale = window?.backingScaleFactor ?? 2
        painter.paint(scene.render(scale: scale), into: ctx)
        if let windowTitle = scene.windowTitle { title(windowTitle) }
        if animating || scene.isAnimating || scene.needsFrame { scheduleFrame() }
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
        guard let id = scene.focusedTextFieldIdentifier else { return nil }
        return scene.semanticsTree().first { $0.identifier == id && $0.textInput != nil }
    }
}

/// The window's content: paints the scene and forwards input in the scene's coordinates
/// (points from the top left, which a flipped view gives directly).
@MainActor
public final class RuntimeView: NSView, @preconcurrency NSTextInputClient {
    unowned let host: NativeSceneHost

    init(frame: NSRect, host: NativeSceneHost) {
        self.host = host
        super.init(frame: frame)
        registerDragTypes()
    }

    required init?(coder: NSCoder) { nil }

    override public var isFlipped: Bool { true }
    override public var acceptsFirstResponder: Bool { true }

    override public func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        // The window follows the system appearance; the scene paints the background.
        host.scene.hostColorScheme = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .dark : .light
        host.scene.hostIncreasesContrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        host.paintFrame(into: ctx, size: bounds.size) { [weak self] title in self?.window?.title = title }
        drawCaret(in: ctx)
    }

    /// A caret after the focused text field's text (the scene paints the text itself).
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
        host.scene.pointerDown(at: point(event), type: .mouse, time: event.timestamp)
        needsDisplay = true
    }

    override public func mouseDragged(with event: NSEvent) {
        host.scene.pointerMoved(to: point(event), time: event.timestamp)
        // The scene lifted a payload: the system carries it from here (sw-dragdrop-os).
        if draggingSession == nil { beginSystemDrag(with: event) }
        if host.scene.needsFrame { needsDisplay = true }
    }

    // MARK: Drags across the app boundary (sw-dragdrop-os)

    private var draggingSession: NSDraggingSession?

    /// The pasteboard types the view takes from other apps: text, URLs, files, images and
    /// whatever uniform type a scene's destination names (every drag is offered; the scene
    /// decides by its types).
    fileprivate func registerDragTypes() {
        registerForDraggedTypes([.string, .URL, .fileURL, .png, .tiff, .html, .rtf, .pdf, NSPasteboard.PasteboardType("public.data"), NSPasteboard.PasteboardType("public.json")])
    }

    /// Starts an `NSDraggingSession` with the scene's items: a pasteboard item carrying the
    /// text, URL, bytes and file URLs, and the lifted preview as the drag image.
    private func beginSystemDrag(with event: NSEvent) {
        let items = host.scene.externalDragItems()
        guard !items.isEmpty else { return }
        let pasteboardItem = NSPasteboardItem()
        var fileURLs: [URL] = []
        for item in items {
            let type = Self.pasteboardType(for: item.type)
            if let text = item.text, item.type == "text/uri-list", let url = URL(string: text) {
                pasteboardItem.setString(url.absoluteString, forType: .URL)
                if url.isFileURL { fileURLs.append(url) }
            } else if let text = item.text {
                pasteboardItem.setString(text, forType: type)
            } else if let data = item.data {
                pasteboardItem.setData(data, forType: type)
            }
            if item.fileName != nil, let data = item.data {
                // A file: written to a temporary file the other app can read.
                let directory = FileManager.default.temporaryDirectory.appendingPathComponent("swiftui-web-drags", isDirectory: true)
                try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let url = directory.appendingPathComponent(item.fileName ?? "file")
                if (try? data.write(to: url)) != nil { fileURLs.append(url) }
            }
        }
        if let file = fileURLs.first { pasteboardItem.setString(file.absoluteString, forType: .fileURL) }
        let draggingItem = NSDraggingItem(pasteboardWriter: pasteboardItem)
        let location = point(event)
        if let preview = host.scene.externalDragPreview(), let image = dragImage(for: preview) {
            draggingItem.setDraggingFrame(CGRect(x: location.x - preview.grab.x, y: location.y - preview.grab.y, width: preview.size.width, height: preview.size.height), contents: image)
        } else {
            draggingItem.setDraggingFrame(CGRect(x: location.x - 8, y: location.y - 8, width: 16, height: 16), contents: nil)
        }
        draggingSession = beginDraggingSession(with: [draggingItem], event: event, source: self)
    }

    /// The lifted preview rendered through the host's painter.
    private func dragImage(for preview: ExternalDragPreview) -> NSImage? {
        let scale = window?.backingScaleFactor ?? 2
        let width = Int((preview.size.width * scale).rounded()), height = Int((preview.size.height * scale).rounded())
        guard width > 0, height > 0,
              let bitmap = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                     space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        // The painter draws top-down: flip the bitmap's space.
        bitmap.translateBy(x: 0, y: CGFloat(height))
        bitmap.scaleBy(x: scale, y: -scale)
        host.painter.paint(preview.list, into: bitmap)
        guard let image = bitmap.makeImage() else { return nil }
        return NSImage(cgImage: image, size: preview.size)
    }

    private static func pasteboardType(for type: String) -> NSPasteboard.PasteboardType {
        switch type {
        case "text/plain": return .string
        case "text/uri-list": return .URL
        case "text/html": return .html
        case "text/rtf": return .rtf
        case "image/png": return .png
        case "image/jpeg": return NSPasteboard.PasteboardType("public.jpeg")
        case "application/json": return NSPasteboard.PasteboardType("public.json")
        case "application/pdf": return .pdf
        case "application/octet-stream": return NSPasteboard.PasteboardType("public.data")
        default: return NSPasteboard.PasteboardType(type)
        }
    }

    private static func mime(for type: NSPasteboard.PasteboardType) -> String {
        switch type {
        case .string: return "text/plain"
        case .URL: return "text/uri-list"
        case .fileURL: return "text/uri-list"
        case .html: return "text/html"
        case .rtf: return "text/rtf"
        case .png: return "image/png"
        case .tiff: return "image/tiff"
        case .pdf: return "application/pdf"
        default: return type.rawValue
        }
    }

    /// The items of a dragging pasteboard: strings and URLs as text, files with their bytes
    /// and names, everything else as data under its type.
    private static func items(of pasteboard: NSPasteboard) -> [ExternalDragItem] {
        var items: [ExternalDragItem] = []
        for pasteboardItem in pasteboard.pasteboardItems ?? [] {
            for type in pasteboardItem.types {
                if type == .fileURL, let string = pasteboardItem.string(forType: .fileURL), let url = URL(string: string) {
                    let data = try? Data(contentsOf: url)
                    let mime = Self.mimeType(forExtension: url.pathExtension)
                    items.append(ExternalDragItem(type: mime, text: url.absoluteString, data: data, fileName: url.lastPathComponent))
                } else if let string = pasteboardItem.string(forType: type) {
                    items.append(ExternalDragItem(type: mime(for: type), text: string, data: Data(string.utf8)))
                } else if let data = pasteboardItem.data(forType: type) {
                    items.append(ExternalDragItem(type: mime(for: type), data: data))
                }
            }
        }
        return items
    }

    private static func mimeType(forExtension ext: String) -> String {
        switch ext.lowercased() {
        case "txt", "text": return "text/plain"
        case "json": return "application/json"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "html", "htm": return "text/html"
        case "csv": return "text/csv"
        case "xml": return "application/xml"
        case "rtf": return "text/rtf"
        case "pdf": return "application/pdf"
        default: return "application/octet-stream"
        }
    }

    private func dragPoint(_ sender: NSDraggingInfo) -> CGPoint { convert(sender.draggingLocation, from: nil) }

    override public func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        draggingUpdated(sender)
    }

    override public func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        let types = (sender.draggingPasteboard.types ?? []).map { Self.mime(for: $0) }
        let accepted = host.scene.externalDragUpdated(types: types, at: dragPoint(sender))
        needsDisplay = true
        return accepted ? .copy : []
    }

    override public func draggingExited(_ sender: NSDraggingInfo?) {
        host.scene.externalDragExited()
        needsDisplay = true
    }

    override public func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let accepted = host.scene.externalDrop(items: Self.items(of: sender.draggingPasteboard), at: dragPoint(sender))
        needsDisplay = true
        return accepted
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
        host.scene.pointerMoved(to: point(event), time: event.timestamp)
        applyPointerStyle()
        if host.scene.needsFrame { needsDisplay = true }
    }

    override public func mouseExited(with event: NSEvent) {
        host.scene.pointerLeft()
        applyPointerStyle()
        if host.scene.needsFrame { needsDisplay = true }
    }

    private func applyPointerStyle() {
        let cursor: NSCursor
        switch host.scene.pointerCursor {
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
        host.scene.pointerUp(at: point(event), time: event.timestamp)
        needsDisplay = true
    }

    override public func rightMouseDown(with event: NSEvent) {
        host.scene.secondaryPointerDown(at: point(event))
        needsDisplay = true
    }

    override public func scrollWheel(with event: NSEvent) {
        // AppKit's deltas are positive when the content should move down; the runtime scrolls
        // the content up for a positive delta (wheel semantics), so flip them.
        let factor: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 16
        let delta = CGSize(width: -event.scrollingDeltaX * factor, height: -event.scrollingDeltaY * factor)
        host.scene.scrollWheel(by: delta, at: point(event))
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
        if host.scene.keyDown(Self.keyEvent(event, key: key)) { needsDisplay = true } else { super.keyDown(with: event) }
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
        host.scene.textField(field.identifier, didChange: text)
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
            host.scene.textFieldDidSubmit(field.identifier)
            needsDisplay = true
        case #selector(NSResponder.cancelOperation(_:)):
            _ = host.scene.keyDown(KeyEvent(key: .escape))
            needsDisplay = true
        case #selector(NSResponder.moveUp(_:)): _ = host.scene.keyDown(KeyEvent(key: .upArrow))
        case #selector(NSResponder.moveDown(_:)): _ = host.scene.keyDown(KeyEvent(key: .downArrow))
        case #selector(NSResponder.insertTab(_:)): _ = host.scene.keyDown(KeyEvent(key: .tab))
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
        host.scene.semanticsTree().map { node in
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
/// actions that go back to the scene.
@MainActor
public final class RuntimeAccessibilityElement: NSAccessibilityElement {
    unowned let host: NativeSceneHost
    public let node: SemanticsNode

    init(host: NativeSceneHost, node: SemanticsNode) {
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
            host.scene.activate(semanticsIdentifier: node.identifier)
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
        host.scene.adjust(semanticsIdentifier: node.identifier, increment: true)
        host.view?.needsDisplay = true
        return true
    }

    override public nonisolated func accessibilityPerformDecrement() -> Bool {
        nonisolated(unsafe) let element = self
        return MainActor.assumeIsolated { element.accessibilityPerformDecrementOnMain() }
    }

    private func accessibilityPerformDecrementOnMain() -> Bool {
        guard node.isAdjustable else { return false }
        host.scene.adjust(semanticsIdentifier: node.identifier, increment: false)
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

extension RuntimeView: NSDraggingSource {
    public func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }

    public func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        draggingSession = nil
        host.scene.externalDragEnded(dropped: operation != [])
        needsDisplay = true
    }
}
#endif
