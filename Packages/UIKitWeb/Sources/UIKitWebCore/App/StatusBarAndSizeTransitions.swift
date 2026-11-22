// The status bar and size transitions (Docs/elements/UIKit/UIViewController.md). A page has no
// status bar: its styles and the scene's status bar manager answer for the strip above the
// safe area, which is what an app positions content against. A window resize is a size
// transition: the root controller hears `viewWillTransition(to:with:)` before the new size is
// laid out, and the coordinator runs the app's alongside blocks and completions after.

import WebFoundation

#if canImport(ObjectiveC)
/// The status bar's look.
@objc public enum UIStatusBarStyle: Int, Sendable {
    case `default` = 0, lightContent = 1, darkContent = 3
}
/// How the status bar animates showing or hiding.
@objc public enum UIStatusBarAnimation: Int, Sendable {
    case none = 0, fade, slide
}
#else
/// The status bar's look.
public enum UIStatusBarStyle: Int, Sendable {
    case `default` = 0, lightContent = 1, darkContent = 3
}
/// How the status bar animates showing or hiding.
public enum UIStatusBarAnimation: Int, Sendable {
    case none = 0, fade, slide
}
#endif

/// The scene's status bar: the strip above the safe area (empty on a page with no inset).
@preconcurrency @MainActor
public final class UIStatusBarManager {
    unowned let scene: UIWindowScene
    init(scene: UIWindowScene) { self.scene = scene }
    public var statusBarFrame: CGRect {
        CGRect(x: 0, y: 0, width: scene.screen.bounds.width, height: scene.screen.safeAreaInsets.top)
    }
    public var statusBarStyle: UIStatusBarStyle { .default }
    public var isStatusBarHidden: Bool { statusBarFrame.height == 0 }
}

extension UIWindowScene {
    /// The scene's status bar manager.
    public var statusBarManager: UIStatusBarManager? {
        if let manager = _statusBarManagers[ObjectIdentifier(self)] { return manager }
        let manager = UIStatusBarManager(scene: self)
        _statusBarManagers[ObjectIdentifier(self)] = manager
        return manager
    }
}

@MainActor private var _statusBarManagers: [ObjectIdentifier: UIStatusBarManager] = [:]

// MARK: Size transitions

/// What a coordinator tells the blocks it runs about the transition.
@preconcurrency @MainActor
public protocol UIViewControllerTransitionCoordinatorContext: AnyObject {
    var isAnimated: Bool { get }
    var presentationStyle: UIModalPresentationStyle { get }
    var initiallyInteractive: Bool { get }
    var isInterruptible: Bool { get }
    var isInteractive: Bool { get }
    var isCancelled: Bool { get }
    var transitionDuration: TimeInterval { get }
    var percentComplete: CGFloat { get }
    var completionVelocity: CGFloat { get }
    var targetTransform: CGAffineTransform { get }
    var containerView: UIView { get }
    func viewController(forKey key: UITransitionContextViewControllerKey) -> UIViewController?
    func view(forKey key: UITransitionContextViewKey) -> UIView?
}

/// Runs work alongside a transition and after it.
@preconcurrency @MainActor
public protocol UIViewControllerTransitionCoordinator: UIViewControllerTransitionCoordinatorContext {
    @discardableResult
    func animate(alongsideTransition animation: ((any UIViewControllerTransitionCoordinatorContext) -> Void)?,
                 completion: ((any UIViewControllerTransitionCoordinatorContext) -> Void)?) -> Bool
    @discardableResult
    func animateAlongsideTransition(in view: UIView?,
                                    animation: ((any UIViewControllerTransitionCoordinatorContext) -> Void)?,
                                    completion: ((any UIViewControllerTransitionCoordinatorContext) -> Void)?) -> Bool
    func notifyWhenInteractionChanges(_ handler: @escaping (any UIViewControllerTransitionCoordinatorContext) -> Void)
}

/// A window resize as a size transition: immediate (a browser resize is not animated), never
/// interactive or cancelled. The scene makes one per resize (`UIKitScene.layout(in:)`).
@preconcurrency @MainActor
final class _UISizeTransitionCoordinator: UIViewControllerTransitionCoordinator {
    /// The coordinator of the resize under way (`UIViewController.transitionCoordinator`).
    static var current: _UISizeTransitionCoordinator?

    let containerView: UIView
    private var alongside: [(any UIViewControllerTransitionCoordinatorContext) -> Void] = []
    private var completions: [(any UIViewControllerTransitionCoordinatorContext) -> Void] = []

    init(containerView: UIView) { self.containerView = containerView }

    var isAnimated: Bool { false }
    var presentationStyle: UIModalPresentationStyle { .none }
    var initiallyInteractive: Bool { false }
    var isInterruptible: Bool { false }
    var isInteractive: Bool { false }
    var isCancelled: Bool { false }
    var transitionDuration: TimeInterval { 0 }
    var percentComplete: CGFloat { 0 }
    var completionVelocity: CGFloat { 1 }
    var targetTransform: CGAffineTransform { .identity }
    func viewController(forKey key: UITransitionContextViewControllerKey) -> UIViewController? { nil }
    func view(forKey key: UITransitionContextViewKey) -> UIView? { nil }

    @discardableResult
    func animate(alongsideTransition animation: ((any UIViewControllerTransitionCoordinatorContext) -> Void)?,
                 completion: ((any UIViewControllerTransitionCoordinatorContext) -> Void)?) -> Bool {
        if let animation { alongside.append(animation) }
        if let completion { completions.append(completion) }
        return true
    }

    @discardableResult
    func animateAlongsideTransition(in view: UIView?,
                                    animation: ((any UIViewControllerTransitionCoordinatorContext) -> Void)?,
                                    completion: ((any UIViewControllerTransitionCoordinatorContext) -> Void)?) -> Bool {
        animate(alongsideTransition: animation, completion: completion)
    }

    func notifyWhenInteractionChanges(_ handler: @escaping (any UIViewControllerTransitionCoordinatorContext) -> Void) {}

    /// The new size is set: the alongside blocks run (each may add more), then the completions.
    func finish() {
        Self.current = self
        defer { Self.current = nil }
        while !alongside.isEmpty {
            let blocks = alongside
            alongside = []
            for block in blocks { block(self) }
        }
        let blocks = completions
        completions = []
        for block in blocks { block(self) }
    }
}
