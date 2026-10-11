// Colour well node (Docs/elements/ColorPicker.md): 48 × 24, a 230-grey rounded rect (radius 11)
// with the colour in a concentric swatch inset 3 pt over a black/white diagonal ground, a 10 %
// inner stroke and a darker top edge; half opacity when disabled; the label's baseline 1.5 pt
// above the bottom. A press asks the host for its system colour chooser (the browser's colour
// input, NSColorPanel) and, without one, opens the preset panel as a popover below the well;
// while a chooser targets the well its frame is the focus blue (macOS 27). Dropped colours set it.
#if os(WASI)
import WebFoundation   // never full Foundation on wasm: it links ICU (decisions 0006, 0017)
#else
import Foundation
#endif

@MainActor
private var nextColorWellIdentifier = 9_900_000

@MainActor
package final class ColorWellNode: LeafNode<_ColorWellHost>, _Interactive, _DropTarget {
    private let identifier: Int
    private weak var panel: PresentationNode?
    private var pressed = false
    /// Whether a colour chooser (the host's or the preset popover) targets the well.
    private(set) var active = false
    private var targeted = false

    package var wellIdentifier: Int { identifier }

    override package init(_ context: _NodeContext<_ColorWellHost>) {
        nextColorWellIdentifier += 1
        identifier = nextColorWellIdentifier
        super.init(context)
    }

    override package func computeSizeThatFits(_ proposal: ProposedViewSize) -> CGSize { PlatformMetrics.colorWellSize }
    /// Rows of wells sit 8.15 apart and so does a checkbox row below one (`colorpicker/form` on
    /// macOS 27; 26.2 put the checkbox 6 below): the well asks 8.15 on every side.
    override package var layoutSpacing: ViewSpacing {
        .control(top: PlatformMetrics.controlSpacingBelow, bottom: PlatformMetrics.controlSpacingBelow,
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
        if active || targeted {
            list.append(.fillPath(well, PlatformMetrics.colorWellActiveColor.resolve(in: environment).multiplyingAlpha(by: opacity)))
        } else {
            list.append(.fillPath(well, RGBA(red: 0, green: 0, blue: 0, alpha: PlatformMetrics.colorWellAlpha * opacity)))
        }
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

    /// A press (or Space / Return on the focused well) opens a chooser: the host's when it has
    /// one, else the preset popover. A press while the popover is open closes it.
    package func pressEnded(inside: Bool) {
        pressed = false
        guard inside, environment.isEnabled else { return }
        if let panel {
            panel.dismiss()
            self.panel = nil
            return
        }
        let request = ColorPanelRequest(identifier: identifier, color: view.color.resolve(in: environment), supportsOpacity: view.supportsOpacity, anchor: frameInRoot)
        if runtime.colorPanelHandler?(request) == true {
            active = true
            runtime.setNeedsDisplay()
            return
        }
        let selection = view.selection, supportsOpacity = view.supportsOpacity
        weak let weakSelf = self
        let content = _ColorPanel(selection: selection, supportsOpacity: supportsOpacity) { weakSelf?.panel?.dismiss(); weakSelf?.panel = nil }
        panel = runtime.present(kind: .popover(arrowEdge: .top, anchor: .rect(.bounds)), view: AnyView(content), environment: environment, anchor: self) {
            weakSelf?.panel = nil
            weakSelf?.panelDidClose()
        }
        active = true
        runtime.setNeedsDisplay()
    }

    /// The host's chooser picked: the binding follows (the alpha stays 1 without opacity support).
    package func panelDidPick(_ color: RGBA) {
        let alpha = view.supportsOpacity ? Double(color.alpha) : 1
        view.selection.binding.wrappedValue = Color(red: Double(color.red), green: Double(color.green), blue: Double(color.blue), opacity: alpha)
        runtime.setNeedsDisplay()
    }

    package func panelDidClose() {
        guard active else { return }
        active = false
        runtime.setNeedsDisplay()
    }

    // MARK: Drops

    /// A dragged `Color` (or anything exporting one) lands in the well as its selection.
    package func accepts(_ item: _TransferItem) -> Bool { environment.isEnabled && item.load(as: Color.self) != nil }

    package func setTargeted(_ targeted: Bool) {
        guard targeted != self.targeted else { return }
        self.targeted = targeted
        runtime.setNeedsDisplay()
    }

    package func perform(_ item: _TransferItem, at point: CGPoint) -> Bool {
        guard let color = item.load(as: Color.self) else { return false }
        let dropped = color.resolve(in: environment)
        view.selection.binding.wrappedValue = view.supportsOpacity ? color : Color(red: Double(dropped.red), green: Double(dropped.green), blue: Double(dropped.blue))
        runtime.setNeedsDisplay()
        return true
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
