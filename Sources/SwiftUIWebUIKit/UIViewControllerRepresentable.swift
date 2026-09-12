// `UIViewControllerRepresentable` (decision 0014, Phase 2): a UIKit view controller as a
// SwiftUI view, hosted like a representable view with the appearance callbacks a window's root
// controller gets.
import SwiftUIWebCore
import UIKitWebCore

/// A view that represents a UIKit view controller.
@MainActor @preconcurrency
public protocol UIViewControllerRepresentable: View where Body == Never {
    /// The type of view controller to present.
    associatedtype UIViewControllerType: UIViewController

    /// A type to coordinate with the view controller.
    associatedtype Coordinator = Void

    typealias Context = UIViewControllerRepresentableContext<Self>

    /// Creates the view controller object and configures its initial state.
    @MainActor @preconcurrency func makeUIViewController(context: Context) -> UIViewControllerType

    /// Updates the state of the specified view controller with new information from SwiftUI.
    @MainActor @preconcurrency func updateUIViewController(_ uiViewController: UIViewControllerType, context: Context)

    /// Cleans up the presented view controller (and coordinator) in anticipation of their removal.
    @MainActor @preconcurrency static func dismantleUIViewController(_ uiViewController: UIViewControllerType, coordinator: Coordinator)

    /// Creates the custom instance that you use to communicate changes from your view controller
    /// to other parts of your SwiftUI interface.
    @MainActor @preconcurrency func makeCoordinator() -> Coordinator

    /// Given a proposed size, returns the preferred size of the composite view.
    @MainActor @preconcurrency func sizeThatFits(_ proposal: ProposedViewSize, uiViewController: UIViewControllerType, context: Context) -> CGSize?

    typealias LayoutOptions = _PlatformViewRepresentableLayoutOptions

    /// How the controller's view is laid out; the default propagates the safe area.
    @MainActor @preconcurrency static func _layoutOptions(_ provider: UIViewControllerType) -> LayoutOptions
}

extension UIViewControllerRepresentable {
    public static func dismantleUIViewController(_ uiViewController: UIViewControllerType, coordinator: Coordinator) {}

    public static func _layoutOptions(_ provider: UIViewControllerType) -> LayoutOptions { [.propagatesSafeArea] }

    /// The default returns nil: SwiftUI sizes the controller's view from its intrinsic content
    /// size and priorities.
    public func sizeThatFits(_ proposal: ProposedViewSize, uiViewController: UIViewControllerType, context: Context) -> CGSize? { nil }
}

extension UIViewControllerRepresentable where Coordinator == Void {
    public func makeCoordinator() -> Coordinator { () }
}

/// Contextual information about the state of the system that you use to create and update your
/// UIKit view controller.
public struct UIViewControllerRepresentableContext<Representable: UIViewControllerRepresentable> {
    public let coordinator: Representable.Coordinator
    public let transaction: Transaction
    public let environment: EnvironmentValues

    init(coordinator: Representable.Coordinator, transaction: Transaction, environment: EnvironmentValues) {
        self.coordinator = coordinator
        self.transaction = transaction
        self.environment = environment
    }
}

extension UIViewControllerRepresentable {
    public static func _makeNode(_ context: _NodeContext<Self>) -> TypedNode<Self> {
        let coordinator = context.view.makeCoordinator()
        let makeContext = { (environment: EnvironmentValues) in
            Context(coordinator: coordinator, transaction: Transaction._current ?? Transaction(), environment: environment)
        }
        // The scene measures with the runtime's engine from the start: a controller that sizes
        // labels in viewDidLoad would otherwise measure them with the placeholder engine.
        let tree = RepresentableTree()
        tree.prepare(textEngine: context.runtime.textEngine, assetCatalog: context.runtime.assetCatalog)
        let controller = context.view.makeUIViewController(context: makeContext(context.environment))
        tree.hosted.setRootViewController(controller)
        tree.dismantleContent = { Self.dismantleUIViewController(controller, coordinator: coordinator) }
        return _PlatformViewHostNode(
            context, tree: tree, propagatesSafeArea: Self._layoutOptions(controller).contains(.propagatesSafeArea),
            sizing: { proposal, representable, environment in
                representable.sizeThatFits(proposal, uiViewController: controller, context: makeContext(environment))
                    ?? RepresentableSizing.size(for: proposal, of: controller)
            },
            update: { representable, environment in
                representable.updateUIViewController(controller, context: makeContext(environment))
            })
    }
}
