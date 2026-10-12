// Drag sessions: a press on a draggable view that moves past the threshold lifts the payload
// (painted as a preview under the pointer), drop destinations under the pointer are targeted,
// and a release over a destination that accepts the payload delivers it. Hosts carry drags
// across the app boundary through the external entry points (sw-dragdrop-os).
#if os(WASI)
import WebFoundation
#else
import Foundation
#endif

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
    /// The drag moved to `point` (the node's coordinates) while targeted: a list moves its
    /// insertion line. The default ignores it.
    func dragUpdated(_ item: _TransferItem, at point: CGPoint)
    func perform(_ item: _TransferItem, at point: CGPoint) -> Bool
}

extension _DropTarget {
    package func dragUpdated(_ item: _TransferItem, at point: CGPoint) {}
}

/// A drag in progress: the app's own (a source, a preview) or one from outside (an item of
/// the host's types, its data arriving with the drop).
package struct DragSession {
    package var item: _TransferItem
    package weak var source: ViewNode?
    package weak var previewNode: ViewNode?
    /// The pointer's offset within the preview when the drag started.
    package var grab: CGPoint
    package var location: CGPoint
    package weak var target: (ViewNode & _DropTarget)?
    /// Whether the host's system drag carries the session (its own pointer events stop).
    package var isSystemDrag = false
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

    package func accepts(_ item: _TransferItem) -> Bool { item.canLoad(as: T.self) }

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
        for node in simultaneousPressNodes { node.pressEnded(inside: false) }
        simultaneousPressNodes = []
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
        if let target {
            let origin = target.frameInRoot.origin
            target.dragUpdated(session.item, at: CGPoint(x: point.x - origin.x, y: point.y - origin.y))
        }
        dragSession = session
        setNeedsDisplay()
    }

    /// Cancels the drag in flight: the target is released, nothing is delivered.
    package func cancelDrag() {
        guard let session = dragSession else { return }
        dragSession = nil
        setPointerStyle(nil)
        session.target?.setTargeted(false)
        requestLayout()
        setNeedsDisplay()
    }

    // MARK: Across the app boundary (sw-dragdrop-os)

    public func hasDragSource(at point: CGPoint) -> Bool { dragSource(at: point) != nil }

    /// The items of the drag in flight for the host's system drag: none for a drag from outside
    /// (the host already has it), none before a payload is lifted.
    public func externalDragItems() -> [ExternalDragItem] {
        guard let session = dragSession, !session.item.isExternal else { return [] }
        return session.item.externalItems()
    }

    /// The host's system drag is starting from the pressed source: the payload lifts now.
    public func beginExternalDrag(at point: CGPoint) -> [ExternalDragItem] {
        if dragSession == nil, let pending = pendingDrag {
            pendingDrag = nil
            beginDrag(from: pending.source, pressedAt: pending.start, at: point)
        }
        guard var session = dragSession, !session.item.isExternal else { return [] }
        session.isSystemDrag = true
        dragSession = session
        return session.item.externalItems()
    }

    /// A system drag over `point`: the app's own session follows it; a drag from outside opens
    /// a session of its announced types (the data comes with the drop). Returns whether a
    /// destination is targeted.
    public func externalDragUpdated(types: [String], at point: CGPoint) -> Bool {
        if dragSession == nil || dragSession?.item.isExternal == true && dragSession?.item.external.map(\.type) != types {
            let items = types.map { ExternalDragItem(type: $0, text: UTType(_mime: $0).isText ? "" : nil, data: Data()) }
            dragSession = DragSession(item: _TransferItem(external: items), source: nil, previewNode: nil, grab: .zero, location: point, target: nil, isSystemDrag: true)
        }
        updateDrag(to: point)
        return dragSession?.target != nil
    }

    /// The system drag left the scene: the app's own drag keeps going (it may come back or
    /// drop elsewhere), one from outside is over.
    public func externalDragExited() {
        guard let session = dragSession else { return }
        if session.item.isExternal {
            cancelDrag()
        } else {
            session.target?.setTargeted(false)
            var copy = session
            copy.target = nil
            dragSession = copy
            setNeedsDisplay()
        }
    }

    /// The system drag dropped: the app's own session ends at the point; one from outside is
    /// delivered with the items' data.
    @discardableResult
    public func externalDrop(items: [ExternalDragItem], at point: CGPoint) -> Bool {
        guard var session = dragSession else {
            // A drop without any dragover (synthetic hosts): target and deliver in one go.
            dragSession = DragSession(item: _TransferItem(external: items), source: nil, previewNode: nil, grab: .zero, location: point, target: nil, isSystemDrag: true)
            updateDrag(to: point)
            return endDrag(at: point)
        }
        if session.item.isExternal {
            session.item = _TransferItem(external: items)
            dragSession = session
        }
        updateDrag(to: point)
        return endDrag(at: point)
    }

    /// The host's system session for the app's drag ended elsewhere: the drag is over.
    public func externalDragEnded(dropped: Bool) {
        guard dragSession != nil else { return }
        cancelDrag()
    }

    /// The lifted preview painted at the origin of its own space, for the system's drag image.
    public func externalDragPreview() -> ExternalDragPreview? {
        guard let session = dragSession, let preview = session.previewNode else { return nil }
        var list = DisplayList()
        let size = preview.frame.size
        list.append(.beginGroup(opacity: 0.8))
        preview.paint(into: &list, context: PaintContext(origin: .zero, scale: hostDisplayScale))
        list.append(.endGroup)
        return ExternalDragPreview(list: list, size: size, grab: session.grab)
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

    /// Paints the dragged preview under the pointer, over everything else (the system draws
    /// its own image while it carries the drag).
    package func paintDragPreview(into list: inout DisplayList, context: PaintContext) {
        guard let session = dragSession, !session.isSystemDrag, let preview = session.previewNode else { return }
        let frame = CGRect(x: session.location.x - session.grab.x, y: session.location.y - session.grab.y,
                           width: preview.frame.width, height: preview.frame.height)
        list.append(.beginGroup(opacity: 0.8))
        preview.paint(into: &list, context: context.child(at: frame))
        list.append(.endGroup)
    }
}
