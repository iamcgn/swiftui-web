// Custom transitions (Docs/elements/UIKit/Presentation.md, Navigation.md): a presented
// controller's `transitioningDelegate` or a navigation controller's delegate hands back an
// animator that moves the views itself, given a context with the container, the controllers,
// their frames and `completeTransition`. Interaction controllers and presentation controllers
// are accepted and ignored.

/// The keys identifying the controllers and views a transition moves between.
public struct UITransitionContextViewControllerKey: Hashable, Sendable {
    package let name: String
    public static let from = UITransitionContextViewControllerKey(name: "from")
    public static let to = UITransitionContextViewControllerKey(name: "to")
}

public struct UITransitionContextViewKey: Hashable, Sendable {
    package let name: String
    public static let from = UITransitionContextViewKey(name: "from")
    public static let to = UITransitionContextViewKey(name: "to")
}

/// What an animator learns about and reports on a transition.
@MainActor
public protocol UIViewControllerContextTransitioning: AnyObject {
    var containerView: UIView { get }
    var isAnimated: Bool { get }
    var isInteractive: Bool { get }
    var transitionWasCancelled: Bool { get }
    var presentationStyle: UIModalPresentationStyle { get }
    func viewController(forKey key: UITransitionContextViewControllerKey) -> UIViewController?
    func view(forKey key: UITransitionContextViewKey) -> UIView?
    func initialFrame(for vc: UIViewController) -> CGRect
    func finalFrame(for vc: UIViewController) -> CGRect
    func completeTransition(_ didComplete: Bool)
}

/// An object that moves the views of a transition.
@MainActor
public protocol UIViewControllerAnimatedTransitioning: AnyObject {
    func transitionDuration(using transitionContext: (any UIViewControllerContextTransitioning)?) -> Double
    func animateTransition(using transitionContext: any UIViewControllerContextTransitioning)
    func animationEnded(_ transitionCompleted: Bool)
}

extension UIViewControllerAnimatedTransitioning {
    public func animationEnded(_ transitionCompleted: Bool) {}
}

/// An interaction controller (accepted: transitions here run to completion).
@MainActor
public protocol UIViewControllerInteractiveTransitioning: AnyObject {
    func startInteractiveTransition(_ transitionContext: any UIViewControllerContextTransitioning)
}

/// A presentation controller (accepted: the container lays presented views out itself).
@MainActor
open class UIPresentationController {
    public let presentedViewController: UIViewController
    public let presentingViewController: UIViewController?
    public init(presentedViewController: UIViewController, presenting presentingViewController: UIViewController?) {
        self.presentedViewController = presentedViewController
        self.presentingViewController = presentingViewController
    }
}

/// The object a presented controller names to supply the animators of its presentation.
@MainActor
public protocol UIViewControllerTransitioningDelegate: AnyObject {
    func animationController(forPresented presented: UIViewController, presenting: UIViewController, source: UIViewController) -> (any UIViewControllerAnimatedTransitioning)?
    func animationController(forDismissed dismissed: UIViewController) -> (any UIViewControllerAnimatedTransitioning)?
    func interactionControllerForPresentation(using animator: any UIViewControllerAnimatedTransitioning) -> (any UIViewControllerInteractiveTransitioning)?
    func interactionControllerForDismissal(using animator: any UIViewControllerAnimatedTransitioning) -> (any UIViewControllerInteractiveTransitioning)?
    func presentationController(forPresented presented: UIViewController, presenting: UIViewController?, source: UIViewController) -> UIPresentationController?
}

extension UIViewControllerTransitioningDelegate {
    public func animationController(forPresented presented: UIViewController, presenting: UIViewController, source: UIViewController) -> (any UIViewControllerAnimatedTransitioning)? { nil }
    public func animationController(forDismissed dismissed: UIViewController) -> (any UIViewControllerAnimatedTransitioning)? { nil }
    public func interactionControllerForPresentation(using animator: any UIViewControllerAnimatedTransitioning) -> (any UIViewControllerInteractiveTransitioning)? { nil }
    public func interactionControllerForDismissal(using animator: any UIViewControllerAnimatedTransitioning) -> (any UIViewControllerInteractiveTransitioning)? { nil }
    public func presentationController(forPresented presented: UIViewController, presenting: UIViewController?, source: UIViewController) -> UIPresentationController? { nil }
}

/// The context the scene and navigation controllers hand to custom animators.
@MainActor
final class TransitionContext: UIViewControllerContextTransitioning {
    let containerView: UIView
    let isAnimated = true
    let isInteractive = false
    private(set) var transitionWasCancelled = false
    let presentationStyle: UIModalPresentationStyle
    private let from: UIViewController?
    private let to: UIViewController?
    private let initialFrames: [ObjectIdentifier: CGRect]
    private let finalFrames: [ObjectIdentifier: CGRect]
    private var onComplete: ((Bool) -> Void)?

    init(containerView: UIView, from: UIViewController?, to: UIViewController?, presentationStyle: UIModalPresentationStyle = .none,
         initialFrames: [ObjectIdentifier: CGRect], finalFrames: [ObjectIdentifier: CGRect], onComplete: @escaping (Bool) -> Void) {
        self.containerView = containerView
        self.from = from
        self.to = to
        self.presentationStyle = presentationStyle
        self.initialFrames = initialFrames
        self.finalFrames = finalFrames
        self.onComplete = onComplete
    }

    func viewController(forKey key: UITransitionContextViewControllerKey) -> UIViewController? { key == .from ? from : to }
    func view(forKey key: UITransitionContextViewKey) -> UIView? { key == .from ? from?.viewIfLoaded : to?.viewIfLoaded }
    func initialFrame(for vc: UIViewController) -> CGRect { initialFrames[ObjectIdentifier(vc)] ?? .zero }
    func finalFrame(for vc: UIViewController) -> CGRect { finalFrames[ObjectIdentifier(vc)] ?? .zero }

    /// Ends the transition: the animator calls it when its animations finish (once).
    func completeTransition(_ didComplete: Bool) {
        transitionWasCancelled = !didComplete
        let complete = onComplete
        onComplete = nil
        complete?(didComplete)
    }
}
