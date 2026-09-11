#if os(WASI)
import FoundationEssentials   // never full Foundation on wasm: it links ICU (decision 0006)
#else
import Foundation
#endif

// The window, the screen and the application: what the scene owns and the app touches first.

/// The backdrop for the app's user interface and the object that dispatches events to views.
@MainActor
open class UIWindow: UIView {
    /// The root view controller, whose view fills the window.
    open var rootViewController: UIViewController? {
        didSet {
            guard rootViewController !== oldValue else { return }
            if let old = oldValue {
                old.viewIfLoaded?.removeFromSuperview()
                old.window = nil
            }
            if let controller = rootViewController {
                controller.window = self
                install(controller)
            }
        }
    }

    /// The window level (all windows share one plane in a browser page).
    open var windowLevel: Level = .normal
    open var screen: UIScreen { UIScreen.main }
    open var canResizeToFitContent = false

    public override init(frame: CGRect) {
        super.init(frame: frame)
        // A window is opaque black behind whatever it shows, like the screen it fills.
        isOpaque = true
    }

    public convenience init() {
        self.init(frame: UIScreen.main.bounds)
    }

    override open var next: UIResponder? { UIApplication.shared }
    override open var traitCollection: UITraitCollection {
        var traits = UIScreen.main.traitCollection
        if overrideUserInterfaceStyle != .unspecified { traits.userInterfaceStyle = overrideUserInterfaceStyle }
        return traits
    }
    override open var safeAreaInsets: UIEdgeInsets { UIScreen.main.safeAreaInsets }

    public private(set) var isKeyWindow = false

    /// Makes the window key and shows it: registers it with the scene.
    open func makeKeyAndVisible() {
        isHidden = false
        makeKey()
        UIKitScene.shared.add(self)
    }

    open func makeKey() {
        for window in UIKitScene.shared.windows where window !== self { window.isKeyWindow = false }
        isKeyWindow = true
        becomeKey()
    }

    open func becomeKey() {}
    open func resignKey() {}

    /// Adds a controller's view as the window's content, filling it with autoresizing.
    private func install(_ controller: UIViewController) {
        let view = controller.view!
        view.frame = bounds
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        if UIKitScene.shared.windows.contains(where: { $0 === self }) { controller.beginAppearanceTransition(true, animated: false) }
        addSubview(view)
        if UIKitScene.shared.windows.contains(where: { $0 === self }) { controller.pendingAppearance = true }
    }

    /// Called by the scene when the window joins it: the root controller appears.
    func didJoinScene() {
        guard let controller = rootViewController, !controller.hasAppeared else { return }
        controller.beginAppearanceTransition(true, animated: false)
        controller.pendingAppearance = true
    }

    /// After the first layout of a joined window, controllers that were about to appear did.
    func completePendingAppearances() {
        var controller = rootViewController
        while let current = controller {
            current.completeAppearanceIfPending()
            controller = current.presentedViewController
        }
    }

    public struct Level: Hashable, Sendable, RawRepresentable, Comparable {
        public let rawValue: CGFloat
        public init(rawValue: CGFloat) { self.rawValue = rawValue }
        public static let normal = Level(rawValue: 0)
        public static let statusBar = Level(rawValue: 1000)
        public static let alert = Level(rawValue: 2000)
        public static func < (lhs: Level, rhs: Level) -> Bool { lhs.rawValue < rhs.rawValue }
    }
}

/// The screen the app draws on: its bounds and scale come from the host.
@MainActor
public final class UIScreen {
    public static let main = UIScreen()

    /// The screen's size in points, set by the host before the app launches and on resize.
    public internal(set) var bounds = CGRect(x: 0, y: 0, width: 390, height: 844)
    public var nativeBounds: CGRect { CGRect(x: 0, y: 0, width: bounds.width * scale, height: bounds.height * scale) }
    public internal(set) var scale: CGFloat = 2
    public var nativeScale: CGFloat { scale }
    public internal(set) var traitCollection = UITraitCollection()
    public internal(set) var safeAreaInsets = UIEdgeInsets.zero
    public var brightness: CGFloat = 1
    public var maximumFramesPerSecond: Int { 60 }
}

/// The centralized point of control and coordination for apps.
@MainActor
public final class UIApplication: UIResponder {
    public static let shared = UIApplication()

    public var delegate: (any UIApplicationDelegate)?
    public var windows: [UIWindow] { UIKitScene.shared.windows }
    public var keyWindow: UIWindow? { UIKitScene.shared.windows.first { $0.isKeyWindow } }
    public var isIdleTimerDisabled = false
    public var applicationState: State = .active
    public var applicationIconBadgeNumber = 0

    /// Opens a URL with the host (a new tab in the browser).
    public func open(_ url: URL, options: [OpenExternalURLOptionsKey: Any] = [:], completionHandler: ((Bool) -> Void)? = nil) {
        UIKitScene.shared.openURL?(url.absoluteString)
        completionHandler?(true)
    }

    public func canOpenURL(_ url: URL) -> Bool { UIKitScene.shared.openURL != nil }

    public enum State: Int, Sendable {
        case active = 0, inactive, background
    }

    public struct LaunchOptionsKey: Hashable, Sendable, RawRepresentable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public static let url = LaunchOptionsKey(rawValue: "UIApplicationLaunchOptionsURLKey")
    }

    public struct OpenExternalURLOptionsKey: Hashable, Sendable, RawRepresentable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
    }
}

/// The methods the app object calls on its delegate.
@MainActor
public protocol UIApplicationDelegate: AnyObject {
    init()
    var window: UIWindow? { get set }
    func application(_ application: UIApplication, willFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool
    func applicationDidBecomeActive(_ application: UIApplication)
    func applicationWillResignActive(_ application: UIApplication)
    func applicationDidEnterBackground(_ application: UIApplication)
    func applicationWillEnterForeground(_ application: UIApplication)
    func applicationWillTerminate(_ application: UIApplication)
}

extension UIApplicationDelegate {
    public var window: UIWindow? {
        get { UIKitScene.shared.delegateWindow }
        set { UIKitScene.shared.delegateWindow = newValue }
    }
    public func application(_ application: UIApplication, willFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool { true }
    public func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool { true }
    public func applicationDidBecomeActive(_ application: UIApplication) {}
    public func applicationWillResignActive(_ application: UIApplication) {}
    public func applicationDidEnterBackground(_ application: UIApplication) {}
    public func applicationWillEnterForeground(_ application: UIApplication) {}
    public func applicationWillTerminate(_ application: UIApplication) {}
}
