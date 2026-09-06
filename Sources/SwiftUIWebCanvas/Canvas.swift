import SwiftUIWebCore
#if os(WASI)
import JavaScriptEventLoop
@_exported import WebGraphicsCanvas

/// A SwiftUI `Runtime` in the browser: the substrate's `CanvasSceneHost` (decision 0014) with the
/// runtime as its scene, the window background and chrome painted, links and share sheets wired
/// to the page, and the platform look chosen from the page's pointer (iOS on a touch device,
/// macOS elsewhere; `Docs/elements/iOS.md`) unless the page forces one.
@MainActor
public final class CanvasHost {
    public let runtime = Runtime()
    public let host: CanvasSceneHost

    /// Installs the JavaScript event loop, creates a host in `#app` (or `<body>`) and mounts.
    public static func launch(windows: [_WindowDescriptor] = [], _ root: @MainActor () -> AnyView) {
        JavaScriptEventLoop.installGlobalExecutor()
        let host = CanvasHost()
        host.runtime.installWindows(windows)
        host.mount(root())
        retained = host
    }

    nonisolated(unsafe) private static var retained: CanvasHost?

    public init() {
        runtime.paintsWindowBackground = true
        runtime.paintsWindowChrome = true
        host = CanvasSceneHost(scene: runtime)
        switch host.requestedPlatform {
        case "ios": runtime.hostPlatformProfile = .iOS
        case "macos": runtime.hostPlatformProfile = .macOS
        default: runtime.hostPlatformProfile = host.hasCoarsePointer ? .iOS : .macOS
        }
        // Links open in a new tab; share links use Web Share where the browser offers it.
        let host = self.host
        OpenURLAction.systemHandler = { url in host.openURL(url.absoluteString) }
        ShareAction.systemHandler = { items, subject in host.share(items: items, subject: subject) }
    }

    /// Mounts (or replaces) the root view and schedules a frame.
    public func mount(_ view: AnyView) {
        runtime.mount(view)
        host.invalidate()
    }
}

#else
/// The canvas host exists only on wasm; this keeps the module importable elsewhere.
public enum SwiftUIWebCanvas {}
#endif
