// Scenes and the app lifecycle (uk-scenes): the host's visibility and focus drive the
// application and scene states, the delegates' callbacks and the notifications; a registered
// scene delegate connects with its window; UIWindow(windowScene:) joins the scene; feedback
// generators do nothing.
import Testing
import UIKitWebCore
#if os(WASI)
import WebFoundation
#else
import Foundation
#endif

@MainActor final class LifecycleLog {
    var events: [String] = []
    static let current = LifecycleLog()
}

final class TestSceneDelegate: UIWindowSceneDelegate {
    var window: UIWindow?
    init() {}
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = UIViewController()
        self.window = window
        LifecycleLog.current.events.append("connect")
    }
    func sceneDidBecomeActive(_ scene: UIScene) { LifecycleLog.current.events.append("active") }
    func sceneWillResignActive(_ scene: UIScene) { LifecycleLog.current.events.append("resign") }
    func sceneWillEnterForeground(_ scene: UIScene) { LifecycleLog.current.events.append("foreground") }
    func sceneDidEnterBackground(_ scene: UIScene) { LifecycleLog.current.events.append("background") }
}

@Suite @MainActor struct SceneLifecycleTests {
    @Test func visibilityAndFocusDriveTheStates() {
        let scene = UIKitScene.shared
        scene.removeAllWindows()
        scene.hostIsVisible = true; scene.hostIsFocused = true
        let log = LifecycleLog.current
        log.events = []
        let application = UIApplication.shared
        #expect(application.applicationState == .active && scene.windowScene.activationState == .foregroundActive)
        #expect(application.connectedScenes.contains(scene.windowScene))
        var notes: [String] = []
        let tokens = [
            NotificationCenter.default.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: nil) { _ in MainActor.assumeIsolated { notes.append("app resign") } },
            NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: nil) { _ in MainActor.assumeIsolated { notes.append("app background") } },
            NotificationCenter.default.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: nil) { _ in MainActor.assumeIsolated { notes.append("app foreground") } },
            NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: nil) { _ in MainActor.assumeIsolated { notes.append("app active") } },
            NotificationCenter.default.addObserver(forName: UIScene.didActivateNotification, object: nil, queue: nil) { _ in MainActor.assumeIsolated { notes.append("scene active") } },
        ]
        defer { for token in tokens { NotificationCenter.default.removeObserver(token) } }
        // The scene delegate connects: its window joins the scene, the scene activates.
        scene.sceneDelegateType = TestSceneDelegate.self
        defer { scene.sceneDelegateType = nil; scene.disconnectWindowScene() }
        scene.connectWindowScene()
        #expect(log.events == ["connect", "active"])
        #expect(scene.windows.count == 1 && scene.windowScene.windows.count == 1 && scene.windowScene.keyWindow === scene.windows.first)
        #expect(scene.windows.first?.windowScene === scene.windowScene)
        // Losing focus: inactive; hiding the page: background; back: foreground then active.
        scene.hostIsFocused = false
        #expect(application.applicationState == .inactive && scene.windowScene.activationState == .foregroundInactive)
        #expect(log.events.last == "resign" && notes.last == "app resign")
        scene.hostIsVisible = false
        #expect(application.applicationState == .background && scene.windowScene.activationState == .background)
        #expect(log.events.last == "background" && notes.last == "app background")
        scene.hostIsVisible = true
        #expect(application.applicationState == .inactive && log.events.last == "foreground" && notes.last == "app foreground")
        scene.hostIsFocused = true
        #expect(application.applicationState == .active && log.events.last == "active")
        #expect(notes.suffix(2) == ["scene active", "app active"])
        // Feedback generators are no-ops that can be called.
        let impact = UIImpactFeedbackGenerator(style: .light)
        impact.prepare(); impact.impactOccurred(); impact.impactOccurred(intensity: 0.5)
        UISelectionFeedbackGenerator().selectionChanged()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        scene.removeAllWindows()
    }
}
