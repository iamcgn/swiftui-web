/// State carried through one painting pass.
public struct PaintContext {
    /// Absolute origin (points) of the node being painted, unrounded.
    package var origin: CGPoint
    /// Pixels per point; frame edges are rounded to this grid.
    package let scale: CGFloat
    /// Absolute area a clipping scroll view can show, plus a margin: nodes whose frames lie
    /// outside it are not painted (`ViewNode.paintChildren`).
    package var visibleRect: CGRect?
    /// Effects the ancestors applied that SwiftUI distributes to every element (opacity, shadow,
    /// colour filters, blend modes): each painted leaf wraps its own drawing in these groups,
    /// outermost first, unless a compositing group collects the subtree into one.
    package var effects: [PendingEffect] = []

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
        child.effects = effects
        return child
    }

    /// Wraps a leaf's or a group's drawing in the pending effects: the group commands opened
    /// over `bounds` before `body` runs and closed after it. Nothing is emitted when `body`
    /// draws nothing.
    package func withEffects(_ bounds: CGRect, into list: inout DisplayList, _ body: (inout DisplayList) -> Void) {
        guard !effects.isEmpty else {
            body(&list)
            return
        }
        let mark = list.commands.count
        for effect in effects { list.append(effect.begin(bounds: bounds)) }
        body(&list)
        if list.commands.count == mark + effects.count {
            list.commands.removeLast(effects.count)
        } else {
            for _ in effects { list.append(.endGroup) }
        }
    }
}

/// One distributed effect (see `PaintContext.effects`).
public enum PendingEffect: Equatable, Sendable {
    case opacity(Double)
    case shadow(RGBA, radius: CGFloat, offset: CGSize)
    case filter(DisplayFilter)
    case blend(BlendMode)

    /// The command that opens this effect's group over `bounds` (closed by `endGroup`).
    package func begin(bounds: CGRect) -> DisplayCommand {
        switch self {
        case .opacity(let opacity): return .beginGroup(opacity: opacity)
        case .shadow(let color, let radius, let offset): return .beginShadow(color, radius: radius, offset: offset)
        case .filter(let filter): return .beginFilter(filter, bounds: bounds)
        case .blend(let mode): return .beginBlend(mode, bounds: bounds)
        }
    }
}

extension Runtime {
    /// Paints the laid-out tree into a display list at `scale` pixels per point.
    public func render(scale: CGFloat = 2) -> DisplayList {
        var list = DisplayList()
        let context = PaintContext(origin: .zero, scale: scale)
        if paintsWindowBackground {
            list.append(.fillRect(context.absoluteRect(CGRect(origin: .zero, size: layoutSize)), rootEnvironment._windowBackground))
        }
        for node in root.layoutChildren {
            node.paint(into: &list, context: context.child(at: node.presentedFrame))
        }
        paintPresentations(into: &list, context: context)
        paintFocusRing(into: &list, context: context)
        return list
    }
}
