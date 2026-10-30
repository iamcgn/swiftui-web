// The window a SwiftUI app's scene stands behind in UIKit (decision 0021): an app whose `@main`
// is an `App` has no `UIWindow` of its own, but reaches for one through
// `UIApplication.shared.connectedScenes` — Ember applies its appearance setting as
// `window.overrideUserInterfaceStyle` on every window of every window scene, as the reliable
// way to make System follow the device again after a forced Light or Dark. Without a window
// the loop finds nothing and the setting shows only in Settings. So the app's launch registers
// one key window with the UIKit scene (no root view controller: the runtime paints the scene),
// and its override drives the runtime's colour scheme, as the window's trait does a UIKit tree.
import SwiftUIWebCore
import UIKitWebCore

@MainActor
public final class _SwiftUISceneWindow: UIWindow {
    weak var runtime: Runtime?

    public override var overrideUserInterfaceStyle: UIUserInterfaceStyle {
        didSet {
            switch overrideUserInterfaceStyle {
            case .light: runtime?.interfaceStyleOverride = .light
            case .dark: runtime?.interfaceStyleOverride = .dark
            case .unspecified: runtime?.interfaceStyleOverride = nil
            }
        }
    }

    /// Registers the scene's window for `runtime` unless the app brought a window of its own
    /// (an app delegate's, made during the launch the app's body ran).
    public static func install(for runtime: Runtime) {
        let scene = UIKitScene.shared
        guard scene.windows.isEmpty else { return }
        let window = _SwiftUISceneWindow(windowScene: scene.windowScene)
        window.runtime = runtime
        window.makeKeyAndVisible()
    }
}
