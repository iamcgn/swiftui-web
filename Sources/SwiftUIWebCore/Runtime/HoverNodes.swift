// Hover tracking (API/Hover.swift): the runtime tells `_HoverTracking` nodes when the pointer
// enters, moves within and leaves their frame; `help` shows a tooltip the runtime paints; the
// deepest hovered `pointerStyle` decides the host's cursor.

/// A node that follows the pointer while it is over the node's frame.
@MainActor
package protocol _HoverTracking: AnyObject {
    /// `inside` with the pointer's position in the node's space; `false` once when it leaves.
    func hoverChanged(inside: Bool, at point: CGPoint)
}

extension Runtime {
    /// Hover-tracking nodes (paint order), memoised per layout.
    private var hoverTrackingNodes: [ViewNode & _HoverTracking] {
        if hoverNodesGeneration != layoutGeneration {
            hoverNodesGeneration = layoutGeneration
            hoverNodes = root.layoutChildren.flatMap { $0.collectNodes(where: { $0 is _HoverTracking }) }.compactMap { $0 as? (ViewNode & _HoverTracking) }
        }
        return hoverNodes
    }

    /// Ends the hovers the pointer left and starts or continues the ones it is over. `nil`
    /// ends them all.
    package func updateHover(at point: CGPoint?) {
        var current: [ViewNode & _HoverTracking] = []
        if let point {
            for node in hoverTrackingNodes where node.frameInRoot.contains(point) { current.append(node) }
        }
        for node in hovered where !current.contains(where: { $0 === node }) {
            node.hoverChanged(inside: false, at: .zero)
        }
        hovered = current
        if let point {
            for node in current {
                let origin = node.frameInRoot.origin
                node.hoverChanged(inside: true, at: CGPoint(x: point.x - origin.x, y: point.y - origin.y))
            }
        }
        setPointerStyle(current.reversed().lazy.compactMap { ($0 as? any _PointerStyled)?.pointerStyle }.first ?? nil)
    }

    // MARK: Tooltip

    /// Asks for a tooltip once the pointer has rested on a view (`help`).
    package func requestTooltip(_ text: String, at point: CGPoint) {
        if let tooltip, tooltip.text == text { return }
        tooltip = TooltipState(text: text, requestedAt: animationClock, anchor: point)
    }

    package func cancelTooltip() {
        guard tooltip != nil else { return }
        tooltip = nil
        setNeedsDisplay()
    }

    /// Whether a tooltip is waiting for its delay: hosts keep frames coming meanwhile.
    package var tooltipPending: Bool { tooltip.map { !$0.isShown } ?? false }

    /// Shows a pending tooltip once its delay has passed. Called from `advanceAnimations`.
    package func advanceTooltip() -> Bool {
        guard var state = tooltip, !state.isShown else { return false }
        if animationClock - state.requestedAt >= Runtime.tooltipDelay {
            state.isShown = true
            tooltip = state
            setNeedsDisplay()
            return false
        }
        return true
    }

    /// The seconds the pointer rests before a tooltip appears.
    package static let tooltipDelay = 1.0

    /// The tooltip's text and frame while one is shown (tests and hosts).
    public var visibleTooltip: (text: String, frame: CGRect)? {
        guard let tooltip, tooltip.isShown else { return nil }
        return (tooltip.text, tooltipFrame(tooltip))
    }

    private static let tooltipFont = Font.system(size: 11)
    private static let tooltipPadding = CGSize(width: 6, height: 3)

    private func tooltipLayout(_ state: TooltipState) -> TextLayout {
        layoutText(state.text, font: Self.tooltipFont.resolve(profile: rootEnvironment.platformProfile), width: min(300, layoutSize.width - 16))
    }

    /// Below and to the right of the pointer, kept inside the window.
    private func tooltipFrame(_ state: TooltipState) -> CGRect {
        let layout = tooltipLayout(state)
        let size = CGSize(width: (layout.size.width + Self.tooltipPadding.width * 2).rounded(.up), height: (layout.size.height + Self.tooltipPadding.height * 2).rounded(.up))
        var origin = CGPoint(x: state.anchor.x, y: state.anchor.y + 20)
        origin.x = max(0, min(origin.x, layoutSize.width - size.width))
        if origin.y + size.height > layoutSize.height { origin.y = max(0, state.anchor.y - 8 - size.height) }
        return CGRect(origin: origin, size: size)
    }

    /// Paints the tooltip, if one is shown, over everything else.
    package func paintTooltip(into list: inout DisplayList, context: PaintContext) {
        guard let tooltip, tooltip.isShown else { return }
        let frame = context.absoluteRect(tooltipFrame(tooltip))
        let environment = rootEnvironment
        let dark = environment.colorScheme == .dark
        list.append(.beginShadow(RGBA(red: 0, green: 0, blue: 0, alpha: 0.25), radius: 3, offset: CGSize(width: 0, height: 1)))
        list.append(.fillRRect(frame, cornerRadius: 4, dark ? RGBA(r: 44, g: 44, b: 44) : RGBA(r: 246, g: 246, b: 246)))
        list.append(.endGroup)
        list.append(.strokePath(Path(roundedRect: frame.insetBy(dx: 0.5, dy: 0.5), cornerRadius: 4), style: StrokeStyle(lineWidth: 1), environment._ink(dark ? 0.2 : 0.15)))
        let layout = tooltipLayout(tooltip)
        let font = DisplayFont(Self.tooltipFont.resolve(profile: environment.platformProfile))
        let color = environment._ink(0.85)
        for line in layout.lines {
            for fragment in line.fragments where !fragment.text.isEmpty {
                list.append(.drawText(fragment.text, font, origin: CGPoint(x: frame.minX + Self.tooltipPadding.width + fragment.x, y: frame.minY + Self.tooltipPadding.height + line.baseline), color))
            }
        }
    }
}

/// A tooltip requested by `help`.
package struct TooltipState: Equatable {
    package var text: String
    package var requestedAt: Double
    package var anchor: CGPoint
    package var isShown = false
}

/// A node that sets the pointer's look while hovered.
@MainActor
package protocol _PointerStyled: AnyObject {
    var pointerStyle: PointerStyle? { get }
}

/// `onHover`: enters once, leaves once.
@MainActor
package final class HoverNode<Content: View>: UnaryLayoutModifierNode<Content, _HoverModifier>, _HoverTracking {
    private var isInside = false

    package func hoverChanged(inside: Bool, at point: CGPoint) {
        guard inside != isInside else { return }
        isInside = inside
        modifier.action(inside)
    }

    override package func unmount() {
        if isInside { runtime.forgetHover(self) }
        super.unmount()
    }
}

/// `onContinuousHover`: every move while inside, then `.ended`.
@MainActor
package final class ContinuousHoverNode<Content: View>: UnaryLayoutModifierNode<Content, _ContinuousHoverModifier>, _HoverTracking {
    private var isInside = false

    package func hoverChanged(inside: Bool, at point: CGPoint) {
        if inside {
            isInside = true
            let location: CGPoint
            if modifier.coordinateSpace.isGlobal {
                let origin = frameInRoot.origin
                location = CGPoint(x: point.x + origin.x, y: point.y + origin.y)
            } else {
                location = point
            }
            modifier.action(.active(location))
        } else if isInside {
            isInside = false
            modifier.action(.ended)
        }
    }

    override package func unmount() {
        if isInside { runtime.forgetHover(self) }
        super.unmount()
    }
}

/// `help`: asks the runtime for a tooltip while hovered.
@MainActor
package final class HelpNode<Content: View>: UnaryLayoutModifierNode<Content, _HelpModifier>, _HoverTracking {
    private var isInside = false

    package func hoverChanged(inside: Bool, at point: CGPoint) {
        if inside {
            isInside = true
            runtime.requestTooltip(modifier.text, at: runtime.pointerPosition)
        } else if isInside {
            isInside = false
            runtime.cancelTooltip()
        }
    }

    override package func unmount() {
        if isInside { runtime.cancelTooltip(); runtime.forgetHover(self) }
        super.unmount()
    }
}

/// `pointerStyle`: the runtime reads the style of the deepest hovered one.
@MainActor
package final class PointerStyleNode<Content: View>: UnaryLayoutModifierNode<Content, _PointerStyleModifier>, _HoverTracking, _PointerStyled {
    package var pointerStyle: PointerStyle? { modifier.style }
    package func hoverChanged(inside: Bool, at point: CGPoint) {}
}
