// Host elements (sw-frameworks, decision 0018): a view whose content the host shows with a
// platform element over the painted content — the browser's `<video>` and `<iframe>` for
// `VideoPlayer` and `WebView`. The view itself paints nothing and fills its proposal; the
// framework stand-in views put their painted placeholder underneath (what goldens, the
// headless runtime and hosts without elements show). Each render collects the anchors that
// were painted, with their frames and the clip they are visible through, for
// `HostedScene.hostElements()`.
#if os(WASI)
import WebFoundation
#else
import Foundation
#endif

/// The anchor a framework view places where the host's element goes.
public struct _HostElementAnchor: View {
    public let kind: HostElement.Kind
    /// Identifies the element across frames (the view's own identity: a player object, a page).
    public let identity: ObjectIdentifier?

    public init(kind: HostElement.Kind, identity: ObjectIdentifier? = nil) {
        self.kind = kind
        self.identity = identity
    }

    public typealias Body = Never

    public static func _makeNode(_ context: _NodeContext<_HostElementAnchor>) -> TypedNode<_HostElementAnchor> {
        _HostElementNode(context)
    }
}

@MainActor
package final class _HostElementNode: LeafNode<_HostElementAnchor> {
    package let identifier: Int

    package override init(_ context: _NodeContext<_HostElementAnchor>) {
        identifier = context.runtime.nextHostElementIdentifier()
        super.init(context)
    }

    override package func update(view: _HostElementAnchor, environment: EnvironmentValues, force: Bool) {
        let changed = view.kind != self.view.kind
        self.view = view
        self.environment = environment
        clearNeedsUpdate()
        if changed { runtime.hostElementsDidChange() }
    }

    override package func performUpdate() { update(view: view, environment: environment, force: false) }

    override package func computeSizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
        proposal.replacingUnspecifiedDimensions(by: .zero)
    }

    /// Painting registers the element: a node a scroll view culled is not painted and so not
    /// shown, one inside a clip shows through the clip's visible rect.
    override package func paintSelf(into list: inout DisplayList, context: PaintContext) {
        let bounds = absoluteBounds(context)
        let visible = context.clipRect.map { bounds.intersection($0) } ?? bounds
        runtime.hostElementsThisFrame.append(HostElement(identifier: identifier, kind: view.kind, frame: bounds, visibleFrame: visible.isNull ? .zero : visible))
    }

    override package var nodeDescription: String { "HostElement" }
}

extension Runtime {
    package func nextHostElementIdentifier() -> Int {
        hostElementCounter += 1
        return hostElementCounter
    }

    /// A player's state changed: the host must look again.
    package func hostElementsDidChange() { requestLayout(invalidatingSizes: false) }

    /// The elements painted by the last render, for the host.
    public func hostElements() -> [HostElement] { hostElementsLastFrame }
}
