#if canImport(AppKit)
import AppKit
import SwiftUIWebCore
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
        host.prepare = { [weak self] in
            guard let self else { return }
            OpenURLAction.systemHandler = { url in host.openURL(url) }
            ShareAction.systemHandler = { items, subject in host.share(items: items, subject: subject) }
            self.runtime.mount(self.root())
        }
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
