// The runtime's frame: the laid-out tree painted into a display list (`PaintContext` is in
// WebGraphics/Display/PaintContext.swift).

extension Runtime {
    /// Paints the laid-out tree into a display list at `scale` pixels per point.
    public func render(scale: CGFloat = 2) -> DisplayList {
        // The root's profile is current from the first node on: a node whose paint override
        // skips the base selection (pickers) otherwise reads whatever table was last used.
        let previousMetrics = PlatformMetrics.select(rootEnvironment.platformProfile)
        defer { PlatformMetrics.current = previousMetrics }
        var list = DisplayList()
        let context = PaintContext(origin: .zero, scale: scale)
        if paintsWindowBackground {
            list.append(.fillRect(context.absoluteRect(CGRect(origin: .zero, size: layoutSize)), rootEnvironment._windowBackground))
        }
        for node in root.layoutChildren {
            node.paint(into: &list, context: context.child(at: node.presentedFrame))
        }
        toolbar?.paint(into: &list, context: context)
        paintPresentations(into: &list, context: context)
        paintFocusRing(into: &list, context: context)
        paintTooltip(into: &list, context: context)
        paintDragPreview(into: &list, context: context)
        return list
    }
}
