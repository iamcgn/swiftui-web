// `UIViewRepresentable` (decision 0014, Phase 2): a UIKit view as a SwiftUI view. The
// representable's UIKit view lives in a `UIKitHostedTree`; a `_PlatformViewHostNode` gives it a
// slot in the layout, paints it into the same display list and routes the pointer and the
// semantics (Docs/elements/Representable.md).
import SwiftUIWebCore
import UIKitWebCore

/// A wrapper for a UIKit view that you use to integrate that view into your SwiftUI view
/// hierarchy.
@MainActor @preconcurrency
public protocol UIViewRepresentable: View where Body == Never {
    /// The type of view to present.
    associatedtype UIViewType: UIView

    /// A type to coordinate with the view.
    associatedtype Coordinator = Void

    typealias Context = UIViewRepresentableContext<Self>

    /// Creates the view object and configures its initial state.
    @MainActor @preconcurrency func makeUIView(context: Context) -> UIViewType

    /// Updates the state of the specified view with new information from SwiftUI.
    @MainActor @preconcurrency func updateUIView(_ uiView: UIViewType, context: Context)

    /// Cleans up the presented UIKit view (and coordinator) in anticipation of their removal.
    @MainActor @preconcurrency static func dismantleUIView(_ uiView: UIViewType, coordinator: Coordinator)

    /// Creates the custom instance that you use to communicate changes from your view to other
    /// parts of your SwiftUI interface.
    @MainActor @preconcurrency func makeCoordinator() -> Coordinator

    /// Given a proposed size, returns the preferred size of the composite view.
    @MainActor @preconcurrency func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIViewType, context: Context) -> CGSize?
}

extension UIViewRepresentable {
    public static func dismantleUIView(_ uiView: UIViewType, coordinator: Coordinator) {}

    /// The default returns nil: SwiftUI sizes the view from its intrinsic content size and its
    /// content hugging and compression resistance priorities.
    public func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIViewType, context: Context) -> CGSize? { nil }
}

extension UIViewRepresentable where Coordinator == Void {
    public func makeCoordinator() -> Coordinator { () }
}

/// Contextual information about the state of the system that you use to create and update your
/// UIKit view.
public struct UIViewRepresentableContext<Representable: UIViewRepresentable> {
    /// The view's associated coordinator.
    public let coordinator: Representable.Coordinator
    /// The current transaction.
    public let transaction: Transaction
    /// The current environment.
    public let environment: EnvironmentValues

    init(coordinator: Representable.Coordinator, transaction: Transaction, environment: EnvironmentValues) {
        self.coordinator = coordinator
        self.transaction = transaction
        self.environment = environment
    }
}

extension UIViewRepresentable {
    /// The runtime hook: the coordinator, the UIKit view, a hosted tree around it, and the host
    /// node that stands for it in the SwiftUI tree.
    public static func _makeNode(_ context: _NodeContext<Self>) -> TypedNode<Self> {
        let coordinator = context.view.makeCoordinator()
        let makeContext = { (environment: EnvironmentValues) in
            Context(coordinator: coordinator, transaction: Transaction._current ?? Transaction(), environment: environment)
        }
        let view = context.view.makeUIView(context: makeContext(context.environment))
        let tree = RepresentableTree()
        tree.hosted.setRootView(view)
        tree.dismantleContent = { Self.dismantleUIView(view, coordinator: coordinator) }
        return _PlatformViewHostNode(
            context, tree: tree,
            sizing: { proposal, representable, environment in
                representable.sizeThatFits(proposal, uiView: view, context: makeContext(environment))
                    ?? RepresentableSizing.size(for: proposal, of: view)
            },
            update: { representable, environment in
                representable.updateUIView(view, context: makeContext(environment))
            })
    }
}
