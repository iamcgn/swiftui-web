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

    /// The Countries app's shape (decision 0021): an app delegate whose
    /// `configurationForConnecting` names the scene delegate class, launched with an instance
    /// the caller made (`launchApplication`, what `@UIApplicationDelegateAdaptor` does): the
    /// launch callbacks, the scene connected to a `SceneDelegate` instance, activation through
    /// it, the window scene delegate's default `window`, and remote-notification registration
    /// failing through the delegate.
    final class CountriesLikeDelegate: UIResponder, UIApplicationDelegate {
        var launched: [String] = []
        var registrationError: Error?
        func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
            launched.append("didFinish"); return true
        }
        func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
            launched.append("configure")
            let config = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
            config.delegateClass = TestSceneDelegate.self
            return config
        }
        func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) { registrationError = error }
    }
    final class WindowlessSceneDelegate: UIResponder, UIWindowSceneDelegate {
        override init() { super.init() }
        func sceneDidBecomeActive(_ scene: UIScene) { LifecycleLog.current.events.append("windowless active") }
    }

    @Test func anAppDelegateLaunchesAndConfiguresItsSceneDelegate() async {
        let scene = UIKitScene.shared
        scene.removeAllWindows()
        scene.hostIsVisible = true; scene.hostIsFocused = true
        scene.sceneDelegateType = nil; scene.disconnectWindowScene()
        LifecycleLog.current.events = []
        defer { scene.sceneDelegateType = nil; scene.disconnectWindowScene(); UIApplication.shared.delegate = nil }
        let delegate = CountriesLikeDelegate()
        scene.launchApplication(delegate: delegate)
        #expect(delegate.launched == ["didFinish", "configure"])
        #expect(UIApplication.shared.delegate === delegate)
        #expect(scene.sceneDelegate is TestSceneDelegate && scene.windowScene.delegate is TestSceneDelegate)
        // The scene connected and, the page being visible and focused, became active through its delegate.
        #expect(LifecycleLog.current.events.first == "connect" && LifecycleLog.current.events.contains("active"), "\(LifecycleLog.current.events)")
        // Push registration has no service in a page: the delegate hears the failure.
        UIApplication.shared.registerForRemoteNotifications()
        await Task.yield(); await Task.yield()
        #expect(delegate.registrationError != nil && !UIApplication.shared.isRegisteredForRemoteNotifications)
        // The settings URL opens nothing.
        var opened: Bool?
        UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!) { opened = $0 }
        #expect(opened == false && !UIApplication.shared.canOpenURL(URL(string: UIApplication.openSettingsURLString)!))
    }

    @Test func aSceneDelegateWithoutAWindowPropertyKeepsItOnTheScene() {
        let scene = UIKitScene.shared
        scene.removeAllWindows()
        scene.sceneDelegateType = nil; scene.disconnectWindowScene()
        LifecycleLog.current.events = []
        defer { scene.sceneDelegateType = nil; scene.disconnectWindowScene(); scene.removeAllWindows() }
        scene.sceneDelegateType = WindowlessSceneDelegate.self
        scene.connectWindowScene()
        let delegate = scene.sceneDelegate as? WindowlessSceneDelegate
        #expect(delegate != nil && delegate?.window == nil)
        let window = UIWindow(frame: UIScreen.main.bounds)
        delegate?.window = window
        #expect(delegate?.window === window && scene.sceneDelegateWindow === window)
    }

    /// The keyboard notifications a host drives through `keyboardFrame` (the Countries app
    /// reads the end frame from `keyboardFrameEndUserInfoKey`).
    @Test func keyboardFrameChangesPostTheNotifications() {
        let scene = UIKitScene.shared
        scene.keyboardFrame = nil
        var seen: [(Notification.Name, CGRect)] = []
        let center = NotificationCenter.default
        let tokens = [UIResponder.keyboardWillShowNotification, UIResponder.keyboardWillHideNotification, UIApplication.keyboardWillChangeFrameNotification].map { name in
            center.addObserver(forName: name, object: nil, queue: nil) { note in
                let end = (note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue ?? .null
                let posted = note.name
                MainActor.assumeIsolated { seen.append((posted, end)) }
            }
        }
        defer { for token in tokens { center.removeObserver(token) }; scene.keyboardFrame = nil }
        let screen = UIScreen.main.bounds
        let keyboard = CGRect(x: 0, y: screen.height - 300, width: screen.width, height: 300)
        scene.keyboardFrame = keyboard
        scene.keyboardFrame = keyboard   // unchanged: nothing posted
        scene.keyboardFrame = nil
        #expect(seen.map(\.0) == [UIResponder.keyboardWillChangeFrameNotification, UIResponder.keyboardWillShowNotification,
                                  UIResponder.keyboardWillChangeFrameNotification, UIResponder.keyboardWillHideNotification], "\(seen.map(\.0))")
        #expect(seen[1].1 == keyboard && seen[3].1 == CGRect(x: 0, y: screen.maxY, width: screen.width, height: 300))
    }
}
