// `@UIApplicationDelegateAdaptor` (decision 0021, uk-app-delegate-adaptor), as the Countries
// app uses it: one delegate per process made with the App value and put through UIKit's launch
// (its `configurationForConnecting` naming the scene delegate class), the delegate reachable
// from the app's body, an `ObservableObject` delegate in every window's environment, and the
// page's visibility and focus reaching the scene delegate.
import Testing
import SwiftUI
import SwiftUIWebCore
import SwiftUIWebHeadless
import UIKitWebCore

#if !os(WASI)
@Suite(.serialized) @MainActor struct UIApplicationDelegateAdaptorTests {
    @MainActor final class Log { static let shared = Log(); var events: [String] = [] }

    final class AppDelegate: UIResponder, UIApplicationDelegate, ObservableObject {
        @Published var title = "from the delegate"
        func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
            Log.shared.events.append("didFinishLaunching"); return true
        }
        func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
            let config = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
            config.delegateClass = SceneDelegate.self
            return config
        }
    }

    final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
        override init() { super.init() }
        func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) { Log.shared.events.append("connect") }
        func sceneDidBecomeActive(_ scene: UIScene) { Log.shared.events.append("active") }
        func sceneWillResignActive(_ scene: UIScene) { Log.shared.events.append("resign") }
    }

    struct Root: View {
        @EnvironmentObject var delegate: AppDelegate
        var body: some View { Text(delegate.title) }
    }

    struct CountriesLike: App {
        @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
        var body: some Scene {
            WindowGroup { Root() }
        }
    }

    private func reset() {
        CountriesLike._resetInstance()
        _UIApplicationDelegateRegistry._reset()
        _appEnvironmentObjects.removeAll()
        let scene = UIKitScene.shared
        scene.hostIsVisible = true; scene.hostIsFocused = true
        scene.sceneDelegateType = nil; scene.disconnectWindowScene(); scene.removeAllWindows()
        UIApplication.shared.delegate = nil
        Log.shared.events = []
    }

    @Test func theDelegateLaunchesOnceWithTheAppAndConfiguresItsScene() {
        reset()
        defer { reset() }
        let first = CountriesLike._instance.appDelegate
        let again = CountriesLike._instance.appDelegate
        #expect(first === again && UIApplication.shared.delegate === first)
        #expect(Log.shared.events == ["didFinishLaunching", "connect", "active"], "\(Log.shared.events)")
        #expect(UIKitScene.shared.sceneDelegate is SceneDelegate)
        // A second wrapper of the same type (another App value) shares the delegate and launches nothing more.
        let other = UIApplicationDelegateAdaptor(AppDelegate.self)
        #expect(other.wrappedValue === first && Log.shared.events.count == 3)
    }

    @Test func anObservableDelegateReachesTheWindowsEnvironment() {
        reset()
        defer { reset() }
        let runtime = Runtime()
        runtime.textEngine = RecordedTextEngine(entries: [:])
        runtime.mount(CountriesLike._rootView())
        runtime.layout(in: CGSize(width: 320, height: 200))
        let texts = { runtime.root.descendants(where: { $0 is TextNode }).compactMap { ($0 as? TextNode)?.view.resolvedString } }
        #expect(texts() == ["from the delegate"])
        CountriesLike._instance.appDelegate.title = "changed"
        runtime.flush()
        runtime.layout(in: CGSize(width: 320, height: 200))
        #expect(texts() == ["changed"])
    }

    @Test func thePagesVisibilityReachesTheSceneDelegate() {
        reset()
        defer { reset() }
        _ = CountriesLike._instance
        let runtime = Runtime()
        #expect(Log.shared.events.last == "active")
        runtime.hostIsFocused = false
        #expect(Log.shared.events.last == "resign" && UIApplication.shared.applicationState == .inactive)
        runtime.hostIsFocused = true
        #expect(Log.shared.events.last == "active" && UIApplication.shared.applicationState == .active)
    }
}
#endif
