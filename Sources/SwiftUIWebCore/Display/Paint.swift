/// State carried through one painting pass.
public struct PaintContext {
    /// Absolute origin (points) of the node being painted, unrounded.
    package var origin: CGPoint
    /// Pixels per point; frame edges are rounded to this grid.
    package let scale: CGFloat
    /// Absolute area a clipping scroll view can show, plus a margin: nodes whose frames lie
    /// outside it are not painted (`ViewNode.paintChildren`).
    package var visibleRect: CGRect?

    package init(origin: CGPoint, scale: CGFloat) {
        self.origin = origin
        self.scale = scale
    }

    /// Rounds a value to the pixel grid.
    package func round(_ value: CGFloat) -> CGFloat {
        (value * scale).rounded(.toNearestOrAwayFromZero) / scale
    }

    /// The absolute, pixel-aligned rectangle for a frame relative to this context.
    package func absoluteRect(_ frame: CGRect) -> CGRect {
        let minX = round(origin.x + frame.minX), minY = round(origin.y + frame.minY)
        let maxX = round(origin.x + frame.maxX), maxY = round(origin.y + frame.maxY)
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// The context for a child placed at `frame` within this node.
    package func child(at frame: CGRect) -> PaintContext {
        var child = PaintContext(origin: CGPoint(x: origin.x + frame.minX, y: origin.y + frame.minY), scale: scale)
        child.visibleRect = visibleRect
        return child
    }
}

extension Runtime {
    /// Paints the laid-out tree into a display list at `scale` pixels per point.
    public func render(scale: CGFloat = 2) -> DisplayList {
        var list = DisplayList()
        let context = PaintContext(origin: .zero, scale: scale)
        for node in root.layoutChildren {
            node.paint(into: &list, context: context.child(at: node.presentedFrame))
        }
        paintPresentations(into: &list, context: context)
        paintFocusRing(into: &list, context: context)
        return list
    }
}
