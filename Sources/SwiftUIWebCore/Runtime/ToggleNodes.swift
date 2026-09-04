// Toggle primitives: the host that flips the binding, and the painted checkbox and switch
// (geometry and colours from Docs/elements/Toggle.md).

/// Transparent layout node owning a toggle's activation and its accessibility node.
@MainActor
package final class ToggleHostNode: LayoutNode<_ToggleHost>, _Interactive {
    package private(set) var child: TypedNode<AnyView>!
    private static var nextIdentifier = 2_000_000
    private let identifier: Int

    package init(_ context: _NodeContext<_ToggleHost>) {
        Self.nextIdentifier += 1
        identifier = Self.nextIdentifier
        super.init(view: context.view, parent: context.parent, runtime: context.runtime, environment: context.environment)
        child = AnyView._makeNode(_NodeContext(view: context.view.content, parent: self, environment: context.environment))
    }

    override package func update(view: _ToggleHost, environment: EnvironmentValues, force: Bool) {
        self.view = view
        self.environment = environment
        clearNeedsUpdate()
        child.update(view: view.content, environment: environment, force: force)
    }

    private var target: ViewNode? { child.layoutChildren.first }

    override package func computeSizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
        target?.sizeThatFits(proposal) ?? .zero
    }
    override package func dimensions(in proposal: ProposedViewSize) -> ViewDimensions {
        target?.dimensions(in: proposal) ?? ViewDimensions(size: .zero)
    }
    override package func layoutContents(proposal: ProposedViewSize) {
        target?.place(at: .zero, anchor: .topLeading, proposal: proposal, by: self)
    }
    /// A checkbox keeps 6 from its neighbours; under a text its 6 replaces the text's 8.15
    /// (groupbox/basic `content`), which the text-to-text category expresses (the lower
    /// neighbour's value applies), unlike text fields, which keep the text's distance.
    override package var layoutSpacing: ViewSpacing {
        var spacing = ViewSpacing.control(top: PlatformMetrics.checkboxSpacing, bottom: PlatformMetrics.checkboxSpacing,
                                          belowText: PlatformMetrics.checkboxSpacing, aboveText: PlatformMetrics.checkboxSpacing)
        spacing[.edgeBelowText, .top] = nil
        spacing[.textToText, .top] = PlatformMetrics.checkboxSpacing
        return spacing
    }
    override package var paintedChildren: [ViewNode] { target.map { [$0] } ?? [] }
    override package var structuralChildren: [ViewNode] { [child] }
    override package var nodeDescription: String { "Toggle" }

    package func pressBegan() {}
    package func pressEnded(inside: Bool) {
        guard inside, environment.isEnabled else { return }
        view.isOn.wrappedValue.toggle()
    }

    package var semantics: SemanticsNode {
        let label = child.descendants(where: { $0 is TextNode }).compactMap { ($0 as? TextNode)?.view.resolvedString }.joined(separator: " ")
        let isSwitch = !child.descendants(where: { $0 is SwitchNode }).isEmpty
        return SemanticsNode(role: isSwitch ? .switch : .checkbox, label: label, frame: frameInRoot, identifier: identifier, isOn: view.isOn.wrappedValue)
    }
}

/// The checkbox: a continuous rounded square, a stroked check mark when on.
@MainActor
package final class CheckboxNode: LeafNode<_CheckboxControl> {
    override package func computeSizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
        CGSize(width: PlatformMetrics.checkboxSize, height: PlatformMetrics.checkboxSize)
    }

    override package func paintSelf(into list: inout DisplayList, context: PaintContext) {
        let box = absoluteBounds(context)
        let enabled = environment.isEnabled
        let fill = view.isOn
            ? (enabled ? PlatformMetrics.checkboxFillOn : PlatformMetrics.checkboxDisabledFillOn)
            : (enabled ? PlatformMetrics.checkboxFillOff : PlatformMetrics.checkboxDisabledFillOff)
        list.append(.fillPath(Path(roundedRect: box, cornerRadius: PlatformMetrics.checkboxCornerRadius), RGBA(red: 0, green: 0, blue: 0, alpha: fill)))
        guard view.isOn else { return }
        let s = box.width / PlatformMetrics.checkboxSize
        var mark = Path()
        mark.move(to: CGPoint(x: box.minX + 4 * s, y: box.minY + 8.75 * s))
        mark.addLine(to: CGPoint(x: box.minX + 6.75 * s, y: box.minY + 11.5 * s))
        mark.addLine(to: CGPoint(x: box.minX + 11.75 * s, y: box.minY + 5 * s))
        let style = StrokeStyle(lineWidth: PlatformMetrics.checkMarkWidth * s, lineCap: .round, lineJoin: .round)
        list.append(.strokePath(mark, style: style, RGBA(red: 0, green: 0, blue: 0, alpha: enabled ? PlatformMetrics.checkMarkAlpha : PlatformMetrics.checkMarkDisabledAlpha)))
    }
}

/// The switch: a capsule track and a white capsule knob at the on or off end.
@MainActor
package final class SwitchNode: LeafNode<_SwitchControl> {
    override package func computeSizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
        view.small ? PlatformMetrics.formGroupedSwitchSize : PlatformMetrics.switchSize
    }

    override package func paintSelf(into list: inout DisplayList, context: PaintContext) {
        let track = absoluteBounds(context)
        let enabled = environment.isEnabled
        var fill = view.isOn ? PlatformMetrics.switchTrackOn : PlatformMetrics.switchTrackOff
        if !enabled { fill /= 2 }
        list.append(.fillRRect(track, cornerRadius: track.height / 2, RGBA(red: 0, green: 0, blue: 0, alpha: fill)))
        let inset = context.round(view.small ? 1 : PlatformMetrics.switchKnobInset)
        let knobSize = view.small ? PlatformMetrics.formGroupedSwitchKnobSize : PlatformMetrics.switchKnobSize
        let knob = CGRect(x: view.isOn ? track.maxX - inset - knobSize.width : track.minX + inset,
                          y: track.minY + inset, width: knobSize.width, height: knobSize.height)
        list.append(.fillRRect(knob, cornerRadius: knob.height / 2, RGBA(red: 1, green: 1, blue: 1, alpha: enabled ? 1 : 0.6)))
    }
}
