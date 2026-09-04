// Colour well node (Docs/elements/ColorPicker.md): 48 × 24, a 230-grey rounded rect (radius 11)
// with the colour in a concentric swatch inset 3 pt over a black/white diagonal ground, a 10 %
// inner stroke and a darker top edge; half opacity when disabled; the label's baseline 1.5 pt
// above the bottom. A press opens the preset panel as a popover below the well.
import Foundation

@MainActor
private var nextColorWellIdentifier = 9_900_000

@MainActor
package final class ColorWellNode: LeafNode<_ColorWellHost>, _Interactive {
    private let identifier: Int
    private weak var panel: PresentationNode?
    private var pressed = false

    override package init(_ context: _NodeContext<_ColorWellHost>) {
        nextColorWellIdentifier += 1
        identifier = nextColorWellIdentifier
        super.init(context)
    }

    override package func computeSizeThatFits(_ proposal: ProposedViewSize) -> CGSize { PlatformMetrics.colorWellSize }
    /// Rows of wells sit 8.15 apart and a checkbox row 6 below one (form fixture): the well
    /// asks 8.15 above itself and only 4.74 below, so a checkbox's own 6 wins there.
    override package var layoutSpacing: ViewSpacing {
        .control(top: PlatformMetrics.controlSpacingBelow, bottom: PlatformMetrics.controlSpacingAbove,
                 belowText: PlatformMetrics.controlSpacingBelow, aboveText: PlatformMetrics.controlSpacingBelow)
    }

    override package func dimensions(in proposal: ProposedViewSize) -> ViewDimensions {
        ViewDimensions(size: sizeThatFits(proposal), explicit: [VerticalAlignment.firstTextBaseline.key: PlatformMetrics.colorWellBaseline,
                                                                VerticalAlignment.lastTextBaseline.key: PlatformMetrics.colorWellBaseline])
    }

    override package func paintSelf(into list: inout DisplayList, context: PaintContext) {
        let bounds = absoluteBounds(context)
        let opacity = environment.isEnabled ? 1 : PlatformMetrics.colorWellDisabledOpacity
        let well = Path(roundedRect: bounds, cornerRadius: PlatformMetrics.colorWellCornerRadius, style: .continuous)
        list.append(.fillPath(well, RGBA(red: 0, green: 0, blue: 0, alpha: PlatformMetrics.colorWellAlpha * opacity)))
        let inset = PlatformMetrics.colorWellSwatchInset
        Self.paintSwatch(in: bounds.insetBy(dx: inset, dy: inset), cornerRadius: PlatformMetrics.colorWellCornerRadius - inset,
                         color: view.color.resolve(in: environment), opacity: opacity, into: &list)
    }

    /// The swatch: white and a black upper-left triangle (split by the diagonal through the
    /// centre at slope −½) under the colour, then the inner stroke and the top shade.
    package static func paintSwatch(in rect: CGRect, cornerRadius: CGFloat, color: RGBA, opacity: Double, into list: inout DisplayList) {
        let swatch = Path(roundedRect: rect, cornerRadius: cornerRadius, style: .continuous)
        list.withSavedState { list in
            list.append(.clipPath(swatch))
            list.append(.fillRect(rect, RGBA(red: 1, green: 1, blue: 1, alpha: opacity)))
            var triangle = Path()
            let rise = rect.width / 4
            triangle.move(to: CGPoint(x: rect.minX, y: rect.midY + rise))
            triangle.addLine(to: CGPoint(x: rect.maxX, y: rect.midY - rise))
            triangle.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            triangle.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
            triangle.closeSubpath()
            list.append(.fillPath(triangle, RGBA(red: 0, green: 0, blue: 0, alpha: opacity)))
            list.append(.fillPath(swatch, RGBA(red: color.red, green: color.green, blue: color.blue, alpha: color.alpha * opacity)))
            list.append(.fillRect(CGRect(x: rect.minX + 1, y: rect.minY, width: rect.width - 2, height: 0.5),
                                  RGBA(red: 0, green: 0, blue: 0, alpha: PlatformMetrics.colorWellTopShadeAlpha * opacity)))
        }
        let stroke = Path(roundedRect: rect.insetBy(dx: 0.25, dy: 0.25), cornerRadius: cornerRadius - 0.25, style: .continuous)
        list.append(.strokePath(stroke, style: StrokeStyle(lineWidth: 0.5), RGBA(red: 0, green: 0, blue: 0, alpha: PlatformMetrics.colorWellStrokeAlpha * opacity)))
    }

    // MARK: Interaction

    package func pressBegan() { pressed = true }

    package func pressEnded(inside: Bool) {
        pressed = false
        guard inside, environment.isEnabled else { return }
        if let panel {
            panel.dismiss()
            self.panel = nil
            return
        }
        let selection = view.selection, supportsOpacity = view.supportsOpacity
        weak let weakSelf = self
        let content = _ColorPanel(selection: selection, supportsOpacity: supportsOpacity) { weakSelf?.panel?.dismiss(); weakSelf?.panel = nil }
        panel = runtime.present(kind: .popover(arrowEdge: .top), view: AnyView(content), environment: environment, anchor: self) { weakSelf?.panel = nil }
        runtime.setNeedsDisplay()
    }

    package var semantics: SemanticsNode {
        var node = SemanticsNode(role: .button, label: view.title.map { "\($0), color" } ?? "Color", frame: frameInRoot, identifier: identifier)
        node.value = _ColorSwatch.name(of: view.color)
        return node
    }
}

/// A panel swatch painted like the well's.
@MainActor
package final class ColorSwatchNode: LeafNode<_ColorSwatchHost> {
    override package func computeSizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
        CGSize(width: proposal.width ?? PlatformMetrics.colorPanelSwatchSize, height: proposal.height ?? PlatformMetrics.colorPanelSwatchSize)
    }

    override package func paintSelf(into list: inout DisplayList, context: PaintContext) {
        ColorWellNode.paintSwatch(in: absoluteBounds(context), cornerRadius: 4, color: view.color.resolve(in: environment), opacity: 1, into: &list)
    }
}
