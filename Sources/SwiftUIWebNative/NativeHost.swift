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
#endif
