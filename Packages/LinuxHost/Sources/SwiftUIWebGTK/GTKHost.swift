// The SwiftUI runtime in a GTK window (pf-linux): `GTKHost.launch(size:title:root:)` mounts the
// root view in a `Runtime` driven by `GTKSceneHost`; links open with `xdg-open`.
#if canImport(CGtk)
import Foundation
import SwiftUI
import WebGraphicsGTK

@MainActor
public enum GTKHost {
    /// Runs the app: the window stays until it is closed; returns the application's status.
    @discardableResult
    public static func launch(size: CGSize = CGSize(width: 800, height: 600), title: String = "SwiftUIWeb", root: @MainActor () -> AnyView) -> Int32 {
        make(size: size, title: title, root: root).run()
    }

    /// The host with the root mounted, not yet running (tests paint and drive it headlessly).
    public static func make(size: CGSize = CGSize(width: 800, height: 600), title: String = "SwiftUIWeb", root: @MainActor () -> AnyView) -> GTKSceneHost {
        let runtime = Runtime()
        runtime.paintsWindowBackground = true
        runtime.paintsWindowChrome = true
        runtime.hostPlatformProfile = .macOS
        let host = GTKSceneHost(size: size, title: title, scene: runtime)
        OpenURLAction.systemHandler = { url in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["xdg-open", url.absoluteString]
            try? process.run()
        }
        runtime.mount(root())
        return host
    }
}
#endif
