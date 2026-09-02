// Nodes that draw: colours, shapes, text, and the modifiers that layer, fade or clip.

/// Node for a filled or stroked shape.
@MainActor
package final class ShapeNode<V: View, S: Shape>: LeafNode<V> {
    private let shapePath: (V) -> S
    private let stylePath: (V) -> any ShapeStyle
    private let lineWidthPath: KeyPath<V, CGFloat>?

    package init(_ context: _NodeContext<V>, shape: @escaping (V) -> S, style: @escaping (V) -> any ShapeStyle, lineWidth: KeyPath<V, CGFloat>?) {
        shapePath = shape
        stylePath = style
        lineWidthPath = lineWidth
        super.init(context)
    }

    package convenience init(_ context: _NodeContext<V>, shape: KeyPath<V, S>, style: @escaping (V) -> any ShapeStyle, lineWidth: KeyPath<V, CGFloat>?) {
        self.init(context, shape: { $0[keyPath: shape] }, style: style, lineWidth: lineWidth)
    }

    package var shape: S { shapePath(view) }

    override package func computeSizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
        shape.sizeThatFits(proposal)
    }

    override package func paintSelf(into list: inout DisplayList, context: PaintContext) {
        let color = stylePath(view).resolveColor(in: environment)
        guard color.alpha > 0 else { return }
        let bounds = absoluteBounds(context)
        if let lineWidthPath {
            list.append(.strokePath(shape.path(in: bounds), lineWidth: view[keyPath: lineWidthPath], color))
            return
        }
        list.append(_fillCommand(shape, in: bounds, color: color))
    }
}

/// The cheapest command that fills `shape` in `bounds`.
@MainActor
package func _fillCommand<S: Shape>(_ shape: S, in bounds: CGRect, color: RGBA) -> DisplayCommand {
    if S.self == Rectangle.self {
        return .fillRect(bounds, color)
    }
    if let rounded = shape as? RoundedRectangle, rounded.cornerSize.width == rounded.cornerSize.height {
        return .fillRRect(bounds, cornerRadius: rounded.cornerSize.width, color)
    }
    if shape is Capsule {
        return .fillRRect(bounds, cornerRadius: min(bounds.width, bounds.height) / 2, color)
    }
    return .fillPath(shape.path(in: bounds), color)
}

@MainActor
package func _clipCommand<S: Shape>(_ shape: S, in bounds: CGRect) -> DisplayCommand {
    if S.self == Rectangle.self {
        return .clipRect(bounds)
    }
    if let rounded = shape as? RoundedRectangle, rounded.cornerSize.width == rounded.cornerSize.height {
        return .clipRRect(bounds, cornerRadius: rounded.cornerSize.width)
    }
    return .clipPath(shape.path(in: bounds))
}

/// Background / overlay: a second subtree laid out against the content's size.
@MainActor
package final class LayeredNode<Content: View, Modifier: ViewModifier, Layer: View>: UnaryLayoutModifierNode<Content, Modifier> {
    package private(set) var layer: TypedNode<Layer>!
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
        self.layer = Layer._makeNode(_NodeContext(view: context.view[keyPath: layer], parent: self, environment: context.environment))
    }

    override package func update(view: ModifiedContent<Content, Modifier>, environment: EnvironmentValues, force: Bool) {
        super.update(view: view, environment: environment, force: force)
        layer.update(view: view[keyPath: layerPath], environment: environment, force: force)
    }

    override package func placeTarget(_ target: ViewNode, in bounds: CGRect, proposal: ProposedViewSize, by placer: ViewNode) {
        super.placeTarget(target, in: bounds, proposal: proposal, by: placer)
        // The layer is proposed the content's size and aligned within it.
        let alignment = view[keyPath: alignmentPath]
        let container = ViewDimensions(size: bounds.size)
        let layerProposal = ProposedViewSize(bounds.size)
        for node in layer.layoutChildren {
            let dims = node.dimensions(in: layerProposal)
            let origin = CGPoint(x: bounds.minX + container[alignment.horizontal] - dims[alignment.horizontal],
                                 y: bounds.minY + container[alignment.vertical] - dims[alignment.vertical])
            node.place(at: origin, anchor: .topLeading, proposal: layerProposal, by: placer)
        }
    }

    override package func paintChildren(into list: inout DisplayList, context: PaintContext) {
        let layers = layer.layoutChildren
        if !isOverlay {
            for node in layers { node.paint(into: &list, context: context.child(at: node.frame)) }
        }
        super.paintChildren(into: &list, context: context)
        if isOverlay {
            for node in layers { node.paint(into: &list, context: context.child(at: node.frame)) }
        }
    }

    override package var structuralChildren: [ViewNode] { [child, layer] }
    override package var nodeDescription: String { isOverlay ? "Overlay" : "Background" }
}

@MainActor
package final class OpacityNode<Content: View>: UnaryLayoutModifierNode<Content, _OpacityEffect> {
    override package func paint(into list: inout DisplayList, context: PaintContext) {
        let opacity = modifier.opacity
        guard opacity > 0 else { return }
        if opacity >= 1 {
            super.paint(into: &list, context: context)
            return
        }
        list.append(.beginGroup(opacity: opacity))
        super.paint(into: &list, context: context)
        list.append(.endGroup)
    }
}

@MainActor
package final class ClipNode<Content: View, S: Shape>: UnaryLayoutModifierNode<Content, _ClipEffect<S>> {
    override package func paint(into list: inout DisplayList, context: PaintContext) {
        list.append(.save)
        list.append(_clipCommand(modifier.shape, in: absoluteBounds(context)))
        super.paint(into: &list, context: context)
        list.append(.restore)
    }
}
