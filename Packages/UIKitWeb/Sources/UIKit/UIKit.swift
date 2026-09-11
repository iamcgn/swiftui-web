// Thin module: apps write `import UIKit` and get the UIKitWeb implementation. Foundation and
// Observation are re-exported because real UIKit does the same (CGFloat/CGRect, @Observable)
// and unmodified app sources depend on it.
@_exported import UIKitWebCore
@_exported import Observation
#if canImport(CoreGraphics)
@_exported import Foundation
@_exported import CoreGraphics
#elseif os(WASI)
// wasm: Foundation would add 12 MB of ICU data and a second CGRect (decision 0006).
@_exported import FoundationEssentials
#else
@_exported import Foundation
#endif

#if os(WASI)
import JavaScriptEventLoop
import WebGraphicsCanvas
#elseif canImport(AppKit)
import WebGraphicsNative
#endif

#if os(WASI)
/// On wasm there is no CoreGraphics: the recording context is what `CGContext` names, so
/// `UIGraphicsGetCurrentContext()` and `draw(_:)` code type-checks as on iOS. On Apple platforms
/// CoreGraphics keeps the name and the recording context is `UIGraphicsRecordingContext`.
public typealias CGContext = UIGraphicsRecordingContext
#endif

/// Marker used by the module-shadowing check (decision 0014).
public struct UIKitWebMarker: Sendable {
    public init() {}
    public static let implementation = "UIKitWeb"
}

extension UIApplicationDelegate {
    /// Launches the app: creates the delegate, sizes the screen from the host, calls the
    /// launch callbacks and shows the delegate's window (or the key window it made). In the
    /// browser the app runs in a canvas host; on macOS in an AppKit window painted with
    /// CoreGraphics; elsewhere (CLIs) it lays out once headlessly and returns.
    public static func main() {
        #if os(WASI)
        JavaScriptEventLoop.installGlobalExecutor()
        let scene = UIKitScene.shared
        let host = CanvasSceneHost(scene: scene)
        scene.configureScreen(size: host.viewportSize, scale: host.pixelScale)
        scene.openURL = { url in host.openURL(url) }
        UIKitLaunch.launch(Self.self)
        host.invalidate()
        UIKitLaunch.retainedHost = host
        #elseif canImport(AppKit)
        let scene = UIKitScene.shared
        let size = NativeSceneHost.windowSize(default: CGSize(width: 390, height: 844))
        let host = NativeSceneHost(size: size, scene: scene)
        scene.configureScreen(size: size, scale: 2)
        scene.openURL = { url in if let parsed = URL(string: url) { host.openURL(parsed) } }
        host.prepare = { UIKitLaunch.launch(Self.self) }
        UIKitLaunch.retainedHost = host
        host.run()
        #else
        MainActor.assumeIsolated {
            UIKitScene.shared.configureScreen(size: CGSize(width: 390, height: 844), scale: 2)
            UIKitLaunch.launch(Self.self)
            UIKitScene.shared.layout(in: CGSize(width: 390, height: 844))
            print("UIKitWeb: no window host on this platform; laid out \(Self.self) headlessly.")
        }
        #endif
    }
}

/// The launch sequence shared by the hosts.
@MainActor
enum UIKitLaunch {
    nonisolated(unsafe) static var retainedHost: AnyObject?

    static func launch<Delegate: UIApplicationDelegate>(_ type: Delegate.Type) {
        let application = UIApplication.shared
        let delegate = Delegate()
        application.delegate = delegate
        _ = delegate.application(application, willFinishLaunchingWithOptions: nil)
        _ = delegate.application(application, didFinishLaunchingWithOptions: nil)
        if let window = delegate.window, !UIKitScene.shared.windows.contains(where: { $0 === window }) {
            window.makeKeyAndVisible()
        }
        delegate.applicationDidBecomeActive(application)
    }
}
