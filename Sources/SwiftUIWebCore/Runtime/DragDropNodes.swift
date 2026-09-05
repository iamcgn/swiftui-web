// Drag sessions: a press on a draggable view that moves past the threshold lifts the payload
// (painted as a preview under the pointer), drop destinations under the pointer are targeted,
// and a release over a destination that accepts the payload delivers it.

/// A node that can start a drag.
@MainActor
package protocol _DragSource: AnyObject {
    func makeDragItem() -> _TransferItem
    /// The node painted as the preview.
    var previewNode: ViewNode { get }
}

/// A node that can receive drops.
@MainActor
package protocol _DropTarget: AnyObject {
    func accepts(_ item: _TransferItem) -> Bool
    func setTargeted(_ targeted: Bool)
    func perform(_ item: _TransferItem, at point: CGPoint) -> Bool
}

/// A drag in progress.
package struct DragSession {
    package let item: _TransferItem
    package weak var source: ViewNode?
    package weak var previewNode: ViewNode?
    /// The pointer's offset within the preview when the drag started.
    package var grab: CGPoint
    package var location: CGPoint
    package weak var target: (ViewNode & _DropTarget)?
}

@MainActor
package final class DraggableNode<Content: View, Payload: Transferable, Preview: View>: UnaryLayoutModifierNode<Content, _DraggableModifier<Payload, Preview>>, _DragSource {
    private var preview: TypedNode<Preview>?

    package func makeDragItem() -> _TransferItem { _TransferItem(modifier.payload()) }

    package var previewNode: ViewNode {
        if let make = modifier.preview {
            if preview == nil {
                preview = Preview._makeNode(_NodeContext(view: make(), parent: self, environment: environment))
            }
            let node = preview!
            let size = node.sizeThatFits(.unspecified)
            node.place(at: .zero, anchor: .topLeading, proposal: ProposedViewSize(size), by: self)
            return node
        }
        return self
    }

    override package var nodeDescription: String { "Draggable" }
}

@MainActor
package final class DropDestinationNode<Content: View, T: Transferable>: UnaryLayoutModifierNode<Content, _DropDestinationModifier<T>>, _DropTarget {
    private var targeted = false

    package func accepts(_ item: _TransferItem) -> Bool { item.load(as: T.self) != nil }

    package func setTargeted(_ targeted: Bool) {
        guard targeted != self.targeted else { return }
        self.targeted = targeted
        modifier.isTargeted(targeted)
        runtime.requestLayout()
    }

    package func perform(_ item: _TransferItem, at point: CGPoint) -> Bool {
        guard let value = item.load(as: T.self) else { return false }
        return modifier.action([value], point)
    }

    override package var nodeDescription: String { "DropDestination" }
}

extension Runtime {
    /// Whether a drag is in progress.
    public var isDragging: Bool { dragSession != nil }

    /// The drag source under `point`, if any (window coordinates).
    package func dragSource(at point: CGPoint) -> (ViewNode & _DragSource)? {
        for node in root.layoutChildren.reversed() {
            let local = CGPoint(x: point.x - node.frame.minX, y: point.y - node.frame.minY)
            if let hit = node.hitTest(local, where: { $0 is _DragSource }) { return hit as? (ViewNode & _DragSource) }
        }
        return nil
    }

    /// The drop target under `point` that accepts `item`, if any.
    package func dropTarget(at point: CGPoint, for item: _TransferItem) -> (ViewNode & _DropTarget)? {
        for node in root.layoutChildren.reversed() {
            let local = CGPoint(x: point.x - node.frame.minX, y: point.y - node.frame.minY)
            if let hit = node.hitTest(local, where: { ($0 as? _DropTarget)?.accepts(item) ?? false }) {
                return hit as? (ViewNode & _DropTarget)
            }
        }
        return nil
    }

    /// Lifts the payload of `source`, pressed at `start`, with the pointer now at `point`.
    package func beginDrag(from source: ViewNode & _DragSource, pressedAt start: CGPoint, at point: CGPoint) {
        let preview = source.previewNode
        let origin = source.frameInRoot.origin
        let grab = preview === source ? CGPoint(x: start.x - origin.x, y: start.y - origin.y)
            : CGPoint(x: preview.frame.width / 2, y: preview.frame.height / 2)
        dragSession = DragSession(item: source.makeDragItem(), source: source, previewNode: preview, grab: grab, location: point, target: nil)
        if let pressed = pressedNode {
            pressedNode = nil
            pressed.pressEnded(inside: false, at: .zero)
        }
        setPointerStyle(.grabActive)
        updateDrag(to: point)
    }

    package func updateDrag(to point: CGPoint) {
        guard var session = dragSession else { return }
        session.location = point
        let target = dropTarget(at: point, for: session.item)
        if target !== session.target {
            session.target?.setTargeted(false)
            target?.setTargeted(true)
            session.target = target
        }
        dragSession = session
        setNeedsDisplay()
    }

    /// Drops at `point`: the targeted destination gets the payload; returns whether it took it.
    @discardableResult
    package func endDrag(at point: CGPoint) -> Bool {
        guard let session = dragSession else { return false }
        dragSession = nil
        setPointerStyle(nil)
        var accepted = false
        if let target = session.target {
            let origin = target.frameInRoot.origin
            accepted = target.perform(session.item, at: CGPoint(x: point.x - origin.x, y: point.y - origin.y))
            target.setTargeted(false)
        }
        requestLayout()
        setNeedsDisplay()
        return accepted
    }

    /// Paints the dragged preview under the pointer, over everything else.
    package func paintDragPreview(into list: inout DisplayList, context: PaintContext) {
        guard let session = dragSession, let preview = session.previewNode else { return }
        let frame = CGRect(x: session.location.x - session.grab.x, y: session.location.y - session.grab.y,
                           width: preview.frame.width, height: preview.frame.height)
        list.append(.beginGroup(opacity: 0.8))
        preview.paint(into: &list, context: context.child(at: frame))
        list.append(.endGroup)
    }
}
