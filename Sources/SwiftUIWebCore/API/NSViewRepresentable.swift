// `NSViewRepresentable` and `NSViewControllerRepresentable` (ix-appkit, decision 0018): the
// protocols compile everywhere, so sources written for the macOS profile build unchanged. The
// native macOS host puts the real `NSView` in its window over the painted content at the
// node's frame (`Runtime.nativeViewHost`, installed by SwiftUIWebNative); every other host —
// the browser, Linux, the headless runtime of the goldens — lays the representable out as an
// empty view of the size the representable says (its `sizeThatFits`, else the proposal) and
// paints nothing there. There is no AppKitWeb: the AppKit view itself exists only where
// AppKit does, so an app guards the view class with `#if canImport(AppKit)` and gives the
// representable a stand-in there, or leaves the conformance under the same guard.
#if os(WASI)
import WebFoundation
#else
import Foundation
#endif

/// A wrapper for an AppKit view that you use to integrate that view into your SwiftUI view hierarchy.
@MainActor @preconcurrency
public protocol NSViewRepresentable: View where Body == Never {
    associatedtype NSViewType: AnyObject
    associatedtype Coordinator = Void
    typealias Context = NSViewRepresentableContext<Self>

    @MainActor @preconcurrency func makeNSView(context: Context) -> NSViewType
    @MainActor @preconcurrency func updateNSView(_ nsView: NSViewType, context: Context)
    @MainActor @preconcurrency static func dismantleNSView(_ nsView: NSViewType, coordinator: Coordinator)
    @MainActor @preconcurrency func makeCoordinator() -> Coordinator
    @MainActor @preconcurrency func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSViewType, context: Context) -> CGSize?
}

extension NSViewRepresentable {
    public static func dismantleNSView(_ nsView: NSViewType, coordinator: Coordinator) {}
    /// The default returns nil: the native host sizes the view from its fitting size, other
    /// hosts give it the proposal.
    public func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSViewType, context: Context) -> CGSize? { nil }
}

extension NSViewRepresentable where Coordinator == Void {
    public func makeCoordinator() -> Coordinator { () }
}

/// Contextual information about the state of the system that you use to create and update
/// your AppKit view.
public struct NSViewRepresentableContext<Representable: NSViewRepresentable> {
    public let coordinator: Representable.Coordinator
    public let transaction: Transaction
    public let environment: EnvironmentValues
    init(coordinator: Representable.Coordinator, transaction: Transaction, environment: EnvironmentValues) {
        self.coordinator = coordinator
        self.transaction = transaction
        self.environment = environment
    }
}

/// A wrapper that you use to integrate an AppKit view controller into your SwiftUI interface.
@MainActor @preconcurrency
public protocol NSViewControllerRepresentable: View where Body == Never {
    associatedtype NSViewControllerType: AnyObject
    associatedtype Coordinator = Void
    typealias Context = NSViewControllerRepresentableContext<Self>

    @MainActor @preconcurrency func makeNSViewController(context: Context) -> NSViewControllerType
    @MainActor @preconcurrency func updateNSViewController(_ nsViewController: NSViewControllerType, context: Context)
    @MainActor @preconcurrency static func dismantleNSViewController(_ nsViewController: NSViewControllerType, coordinator: Coordinator)
    @MainActor @preconcurrency func makeCoordinator() -> Coordinator
    @MainActor @preconcurrency func sizeThatFits(_ proposal: ProposedViewSize, nsViewController: NSViewControllerType, context: Context) -> CGSize?
}

extension NSViewControllerRepresentable {
    public static func dismantleNSViewController(_ nsViewController: NSViewControllerType, coordinator: Coordinator) {}
    public func sizeThatFits(_ proposal: ProposedViewSize, nsViewController: NSViewControllerType, context: Context) -> CGSize? { nil }
}

extension NSViewControllerRepresentable where Coordinator == Void {
    public func makeCoordinator() -> Coordinator { () }
}

public struct NSViewControllerRepresentableContext<Representable: NSViewControllerRepresentable> {
    public let coordinator: Representable.Coordinator
    public let transaction: Transaction
    public let environment: EnvironmentValues
    init(coordinator: Representable.Coordinator, transaction: Transaction, environment: EnvironmentValues) {
        self.coordinator = coordinator
        self.transaction = transaction
        self.environment = environment
    }
}

// MARK: - The host's seam

/// What the native host does with an AppKit view (or a controller's view) a representable
/// made: puts it in the window at a frame in the scene's coordinates, moves it, sizes it and
/// takes it out. The object is the `NSView`; the runtime never names AppKit's types.
@MainActor
public protocol _NativeViewHosting: AnyObject {
    func attach(_ object: AnyObject, frame: CGRect)
    func move(_ object: AnyObject, to frame: CGRect)
    func detach(_ object: AnyObject)
    /// The view's own size for a proposal (its fitting size clamped to the proposal).
    func fittingSize(of object: AnyObject, proposal: ProposedViewSize) -> CGSize?
    /// A controller's view, for a view-controller representable.
    func view(of controller: AnyObject) -> AnyObject?
}

extension NSViewRepresentable {
    public static func _makeNode(_ context: _NodeContext<Self>) -> TypedNode<Self> {
        let coordinator = context.view.makeCoordinator()
        let makeContext = { (environment: EnvironmentValues, transaction: Transaction) in
            Context(coordinator: coordinator, transaction: transaction, environment: environment)
        }
        let view = context.view.makeNSView(context: makeContext(context.environment, Transaction._current ?? Transaction()))
        return NativeViewHostNode(
            context, object: view, isController: false,
            sizing: { proposal, representable, environment in representable.sizeThatFits(proposal, nsView: view, context: makeContext(environment, Transaction())) },
            update: { representable, environment, transaction in representable.updateNSView(view, context: makeContext(environment, transaction)) },
            dismantle: { Self.dismantleNSView(view, coordinator: coordinator) })
    }
}

extension NSViewControllerRepresentable {
    public static func _makeNode(_ context: _NodeContext<Self>) -> TypedNode<Self> {
        let coordinator = context.view.makeCoordinator()
        let makeContext = { (environment: EnvironmentValues, transaction: Transaction) in
            Context(coordinator: coordinator, transaction: transaction, environment: environment)
        }
        let controller = context.view.makeNSViewController(context: makeContext(context.environment, Transaction._current ?? Transaction()))
        return NativeViewHostNode(
            context, object: controller, isController: true,
            sizing: { proposal, representable, environment in representable.sizeThatFits(proposal, nsViewController: controller, context: makeContext(environment, Transaction())) },
            update: { representable, environment, transaction in representable.updateNSViewController(controller, context: makeContext(environment, transaction)) },
            dismantle: { Self.dismantleNSViewController(controller, coordinator: coordinator) })
    }
}

/// The leaf that stands for an AppKit view: sized by the representable, else by the host's
/// fitting size, else the proposal; the host (when there is one) keeps the real view at the
/// node's frame in the window.
@MainActor
package final class NativeViewHostNode<V: View>: LeafNode<V> {
    private let object: AnyObject
    private let isController: Bool
    private let sizing: (ProposedViewSize, V, EnvironmentValues) -> CGSize?
    private let updateView: (V, EnvironmentValues, Transaction) -> Void
    private let dismantle: () -> Void
    private var attached = false
    private var lastFrame: CGRect?

    package init(_ context: _NodeContext<V>, object: AnyObject, isController: Bool,
                 sizing: @escaping (ProposedViewSize, V, EnvironmentValues) -> CGSize?,
                 update: @escaping (V, EnvironmentValues, Transaction) -> Void,
                 dismantle: @escaping () -> Void) {
        self.object = object
        self.isController = isController
        self.sizing = sizing
        updateView = update
        self.dismantle = dismantle
        super.init(context)
        context.runtime.registerNativeView(self)
        updateView(context.view, context.environment, Transaction._current ?? Transaction())
    }

    /// The view the host places: a controller's view, or the view itself.
    private var hostedObject: AnyObject? {
        isController ? runtime.nativeViewHost?.view(of: object) : object
    }

    override package func update(view: V, environment: EnvironmentValues, force: Bool) {
        self.view = view
        self.environment = environment
        clearNeedsUpdate()
        updateView(view, environment, Transaction._current ?? Transaction())
        runtime.invalidateSizeMemos()
    }

    override package func performUpdate() { update(view: view, environment: environment, force: false) }

    override package func computeSizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
        if let size = sizing(proposal, view, environment) { return size }
        if let host = runtime.nativeViewHost, let hosted = hostedObject, let size = host.fittingSize(of: hosted, proposal: proposal) { return size }
        return proposal.replacingUnspecifiedDimensions(by: .zero)
    }

    /// After a layout the host moves the view to the node's frame in the window.
    package func syncNativeView() {
        guard let host = runtime.nativeViewHost, let hosted = hostedObject else { return }
        let frame = frameInRoot
        if !attached {
            host.attach(hosted, frame: frame)
            attached = true
        } else if frame != lastFrame {
            host.move(hosted, to: frame)
        }
        lastFrame = frame
    }

    override package func unmount() {
        if attached, let host = runtime.nativeViewHost, let hosted = hostedObject { host.detach(hosted) }
        attached = false
        runtime.forgetNativeView(self)
        dismantle()
        super.unmount()
    }

    override package var nodeDescription: String { "NativeView(\(_shortTypeName(V.self)))" }
}

extension Runtime {
    /// The host that places AppKit views (SwiftUIWebNative installs one); nil elsewhere.
    public var nativeViewHost: (any _NativeViewHosting)? {
        get { nativeViewHostStorage }
        set { nativeViewHostStorage = newValue; syncNativeViews() }
    }

    package func registerNativeView(_ node: any _NativeViewSyncing) {
        nativeViews.removeAll { $0.node == nil }
        nativeViews.append(WeakNativeView(node: node))
    }

    package func forgetNativeView(_ node: any _NativeViewSyncing) {
        nativeViews.removeAll { $0.node == nil || $0.node === node }
    }

    /// Moves every hosted AppKit view to its node's frame (after each layout).
    package func syncNativeViews() {
        guard nativeViewHost != nil else { return }
        for entry in nativeViews { entry.node?.syncNativeView() }
    }
}

@MainActor
package protocol _NativeViewSyncing: AnyObject {
    func syncNativeView()
}

extension NativeViewHostNode: _NativeViewSyncing {}

package struct WeakNativeView {
    weak var node: (any _NativeViewSyncing)?
}
