// Nodes that draw: colours, shapes, text, and the modifiers that layer, fade or clip.

/// Node for a shape view (`_ShapeView`, `FillShapeView`, `StrokeShapeView`, …): the view sizes
/// and paints itself.
@MainActor
package final class ShapeNode<V: _ShapePainting>: LeafNode<V> {
    override package func computeSizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
        view._shapeSizeThatFits(proposal)
    }

    override package func paintSelf(into list: inout DisplayList, context: PaintContext) {
        view._paintShape(in: absoluteBounds(context), environment: environment, into: &list)
    }
}

/// Background / overlay: a second subtree laid out against the content's size. When the content
/// is a list, every element gets its own layer instance (`Group { A; B }.background(...)` draws
/// two backgrounds), created when the element is first placed and dropped when it goes away.
@MainActor
package final class LayeredNode<Content: View, Modifier: ViewModifier, Layer: View>: UnaryLayoutModifierNode<Content, Modifier> {
    private struct Slot {
        weak var target: ViewNode?
        let layer: TypedNode<Layer>
    }

    private var slots: [ObjectIdentifier: Slot] = [:]
    private let layerPath: KeyPath<ModifiedContent<Content, Modifier>, Layer>
    private let alignmentPath: KeyPath<ModifiedContent<Content, Modifier>, Alignment>
    private let isOverlay: Bool

    package init(_ context: _NodeContext<ModifiedContent<Content, Modifier>>,
                 layer: KeyPath<ModifiedContent<Content, Modifier>, Layer>,
                 alignment: KeyPath<ModifiedContent<Content, Modifier>, Alignment>, isOverlay: Bool) {
        layerPath = layer
        alignmentPath = alignment
        self.isOverlay = isOverlay
        super.init(context)
        for target in targets { _ = self.layer(for: target) }
    }

    /// The layer subtree for one element, in target order.
    package var layers: [TypedNode<Layer>] { targets.compactMap { slots[ObjectIdentifier($0)]?.layer } }

    /// For tests: the single layer of a non-list content.
    package var layer: TypedNode<Layer>! { layers.first }

    private func layer(for target: ViewNode) -> TypedNode<Layer> {
        let key = ObjectIdentifier(target)
        if let slot = slots[key], slot.target === target { return slot.layer }
        let node = Layer._makeNode(_NodeContext(view: view[keyPath: layerPath], parent: self, environment: environment))
        slots[key] = Slot(target: target, layer: node)
        return node
    }

    override package func update(view: ModifiedContent<Content, Modifier>, environment: EnvironmentValues, force: Bool) {
        super.update(view: view, environment: environment, force: force)
        let live = Set(targets.map(ObjectIdentifier.init))
        for (key, slot) in slots where !live.contains(key) || slot.target == nil {
            slot.layer.unmount()
            slots[key] = nil
        }
        for target in targets {
            layer(for: target).update(view: view[keyPath: layerPath], environment: environment, force: force)
        }
    }

    override package func unmount() {
        for slot in slots.values { slot.layer.unmount() }
        slots.removeAll()
        super.unmount()
    }

    override package func placeTarget(_ target: ViewNode, in bounds: CGRect, proposal: ProposedViewSize, by placer: ViewNode) {
        super.placeTarget(target, in: bounds, proposal: proposal, by: placer)
        // The layer is proposed the content's size and aligned within it.
        let alignment = view[keyPath: alignmentPath]
        let container = ViewDimensions(size: bounds.size)
        let layerProposal = ProposedViewSize(bounds.size)
        for node in layer(for: target).layoutChildren {
            let dims = node.dimensions(in: layerProposal)
            let origin = CGPoint(x: bounds.minX + container[alignment.horizontal] - dims[alignment.horizontal],
                                 y: bounds.minY + container[alignment.vertical] - dims[alignment.vertical])
            node.place(at: origin, anchor: .topLeading, proposal: layerProposal, by: placer)
        }
    }

    override package func paintTarget(_ target: ViewNode, in node: ViewNode, into list: inout DisplayList, context: PaintContext) {
        let layerNodes = layer(for: target).layoutChildren
        if !isOverlay {
            for layerNode in layerNodes { layerNode.paint(into: &list, context: context.child(at: layerNode.presentedFrame)) }
        }
        super.paintTarget(target, in: node, into: &list, context: context)
        if isOverlay {
            for layerNode in layerNodes { layerNode.paint(into: &list, context: context.child(at: layerNode.presentedFrame)) }
        }
    }

    override package var structuralChildren: [ViewNode] { [child] + layers }
    override package var nodeDescription: String { isOverlay ? "Overlay" : "Background" }
}

@MainActor
package final class OpacityNode<Content: View>: UnaryLayoutModifierNode<Content, _OpacityEffect> {
    override package func update(view: ModifiedContent<Content, _OpacityEffect>, environment: EnvironmentValues, force: Bool) {
        let old = presentedOpacity
        let changed = modifier.opacity != view.modifier.opacity
        super.update(view: view, environment: environment, force: force)
        if changed {
            if let animation = runtime.effectiveUpdateAnimation(for: self) {
                let presentation = self.presentation ?? NodePresentation()
                presentation.opacity = Tween(from: [old], to: [view.modifier.opacity], animation: animation, start: runtime.animationClock)
                self.presentation = presentation
                runtime.register(animating: self)
            } else {
                presentation?.opacity = nil
            }
        }
    }

    /// The opacity to paint with: the tween's value while animating.
    package var presentedOpacity: Double {
        presentation?.opacity?.value(at: runtime.animationClock).first ?? modifier.opacity
    }

    override package func paintTarget(_ target: ViewNode, in node: ViewNode, into list: inout DisplayList, context: PaintContext) {
        let opacity = presentedOpacity
        guard opacity > 0 else { return }
        if opacity >= 1 {
            super.paintTarget(target, in: node, into: &list, context: context)
            return
        }
        list.append(.beginGroup(opacity: opacity))
        super.paintTarget(target, in: node, into: &list, context: context)
        list.append(.endGroup)
    }
}

@MainActor
package final class ClipNode<Content: View, S: Shape>: UnaryLayoutModifierNode<Content, _ClipEffect<S>> {
    override package func paintTarget(_ target: ViewNode, in node: ViewNode, into list: inout DisplayList, context: PaintContext) {
        list.append(.save)
        list.append(_clipCommand(modifier.shape, in: context.absoluteRect(CGRect(origin: .zero, size: node.frame.size)), fillStyle: modifier.style))
        super.paintTarget(target, in: node, into: &list, context: context)
        list.append(.restore)
    }
}
