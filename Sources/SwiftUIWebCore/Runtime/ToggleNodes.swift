// Toggle primitives: the host that flips the binding, and the painted checkbox and switch
// (geometry and colours from Docs/elements/Toggle.md).

/// Transparent layout node owning a toggle's activation and its accessibility node.
@MainActor
package final class ToggleHostNode: LayoutNode<_ToggleHost>, _Interactive, _FocusRingProviding {
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
        if PlatformMetrics.controlsUsePlainSpacing { return ViewSpacing() }
        var spacing = ViewSpacing.control(top: PlatformMetrics.checkboxSpacing, bottom: PlatformMetrics.checkboxSpacing,
                                          belowText: PlatformMetrics.checkboxSpacing, aboveText: PlatformMetrics.checkboxSpacing)
        spacing[.edgeBelowText, .top] = nil
        spacing[.textToText, .top] = PlatformMetrics.checkboxSpacing
        return spacing
    }
    override package var paintedChildren: [ViewNode] { target.map { [$0] } ?? [] }
    override package var structuralChildren: [ViewNode] { [child] }
    override package var nodeDescription: String { "Toggle" }

    /// The focus ring goes around the control, not the label (approximate: unfocused goldens).
    package var focusRingFrame: CGRect {
        child.descendants(where: { $0 is CheckboxNode || $0 is SwitchNode }).first?.frameInRoot ?? frameInRoot
    }

    package func pressBegan() {}
    package func pressEnded(inside: Bool) {
        guard inside, environment.isEnabled else { return }
        view.isOn.wrappedValue.toggle()
        // A menu row closes the menu unless `menuActionDismissBehavior(.disabled)`.
        if environment._inMenu, environment._dismissesOnActivation, environment._menuActionDismissBehavior.dismisses { runtime.dismissMenus() }
    }

    package var semantics: SemanticsNode {
        let label = child.descendants(where: { $0 is TextNode }).compactMap { ($0 as? TextNode)?.view.resolvedString }.joined(separator: " ")
        let isSwitch = !child.descendants(where: { $0 is SwitchNode }).isEmpty
        return SemanticsNode(role: isSwitch ? .switch : .checkbox, label: label, frame: frameInRoot, identifier: identifier, isOn: view.isOn.wrappedValue)
    }
}

/// The checkbox: a continuous rounded square, a stroked check mark when on, a dash when mixed;
/// in an active window (`Runtime.windowIsActive`) the on and mixed boxes fill with the tint and
/// the mark is white (approximate).
@MainActor
package final class CheckboxNode: LeafNode<_CheckboxControl> {
    private var boxSize: CGFloat {
        switch view.size {
        case .mini: return PlatformMetrics.checkboxMiniSize
        case .small: return PlatformMetrics.checkboxSmallSize
        case .large, .extraLarge: return PlatformMetrics.checkboxLargeSize
        case .regular: return PlatformMetrics.checkboxSize
        }
    }

    override package func computeSizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
        CGSize(width: boxSize, height: boxSize)
    }

    override package func paintSelf(into list: inout DisplayList, context: PaintContext) {
        let box = absoluteBounds(context)
        let enabled = environment.isEnabled
        let marked = view.isOn || view.isMixed
        let accent = marked && enabled && runtime.windowIsActive
        let s = box.width / PlatformMetrics.checkboxSize
        if accent {
            list.append(.fillPath(Path(roundedRect: box, cornerRadius: PlatformMetrics.checkboxCornerRadius * s),
                                  (environment._tint ?? Color.accentColor).resolve(in: environment)))
        } else {
            let fill = marked
                ? (enabled ? PlatformMetrics.checkboxFillOn : PlatformMetrics.checkboxDisabledFillOn)
                : (enabled ? PlatformMetrics.checkboxFillOff : PlatformMetrics.checkboxDisabledFillOff)
            list.append(.fillPath(Path(roundedRect: box, cornerRadius: PlatformMetrics.checkboxCornerRadius * s), environment._ink(fill)))
        }
        guard marked else { return }
        var mark = Path()
        if view.isMixed {
            let inset = PlatformMetrics.checkboxMixedDashInset * s
            mark.move(to: CGPoint(x: box.minX + inset, y: box.midY))
            mark.addLine(to: CGPoint(x: box.maxX - inset, y: box.midY))
        } else {
            mark.move(to: CGPoint(x: box.minX + 4 * s, y: box.minY + 8.75 * s))
            mark.addLine(to: CGPoint(x: box.minX + 6.75 * s, y: box.minY + 11.5 * s))
            mark.addLine(to: CGPoint(x: box.minX + 11.75 * s, y: box.minY + 5 * s))
        }
        let width = (view.isMixed ? PlatformMetrics.checkboxMixedDashWidth : PlatformMetrics.checkMarkWidth) * s
        let style = StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round)
        let color = accent ? RGBA(r: 255, g: 255, b: 255, a: PlatformMetrics.checkboxAccentCheckAlpha)
            : environment._ink(enabled ? PlatformMetrics.checkMarkAlpha : PlatformMetrics.checkMarkDisabledAlpha)
        list.append(.strokePath(mark, style: style, color))
    }
}

/// The switch: a capsule track and a white capsule knob at the on or off end.
@MainActor
package final class SwitchNode: LeafNode<_SwitchControl> {
    override package func computeSizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
        if environment.platformProfile.isIOS {
            // In a list row the toggle is its label's line (ios/form/basic: 24.5) and the switch
            // overflows it, centred; elsewhere the 66 × 30 frame.
            if environment._inListRow { return CGSize(width: PlatformMetrics.switchFrameSize.width, height: environment._lineHeight) }
            return PlatformMetrics.switchFrameSize
        }
        return macSizes.track
    }

    /// macOS: the track and knob for the control size (the grouped form's small switch, too).
    private var macSizes: (track: CGSize, knob: CGSize, inset: CGFloat) {
        if view.small { return (PlatformMetrics.formGroupedSwitchSize, PlatformMetrics.formGroupedSwitchKnobSize, 1) }
        switch view.size {
        case .mini: return (PlatformMetrics.switchMiniSize, PlatformMetrics.switchMiniKnobSize, 1)
        case .small: return (PlatformMetrics.switchSmallSize, PlatformMetrics.switchSmallKnobSize, PlatformMetrics.switchKnobInset)
        default: return (PlatformMetrics.switchSize, PlatformMetrics.switchKnobSize, PlatformMetrics.switchKnobInset)
        }
    }

    override package func paintSelf(into list: inout DisplayList, context: PaintContext) {
        if environment.platformProfile.isIOS { paintIOS(into: &list, context: context); return }
        let track = absoluteBounds(context)
        let enabled = environment.isEnabled
        var fill = view.isOn ? PlatformMetrics.switchTrackOn : PlatformMetrics.switchTrackOff
        if !enabled { fill /= 2 }
        if view.isOn, enabled, runtime.windowIsActive {
            // An active window's switch: the tint (approximate, unverified).
            list.append(.fillRRect(track, cornerRadius: track.height / 2, (environment._tint ?? Color.accentColor).resolve(in: environment)))
        } else {
            list.append(.fillRRect(track, cornerRadius: track.height / 2, environment._ink(fill)))
        }
        let sizes = macSizes
        let inset = context.round(sizes.inset)
        let knobSize = sizes.knob
        let knob = CGRect(x: view.isOn ? track.maxX - inset - knobSize.width : track.minX + inset,
                          y: track.minY + inset, width: knobSize.width, height: knobSize.height)
        // The knob's soft shadow: two rings over the track (toggle/styles pixels).
        let spread = PlatformMetrics.switchKnobShadowRingSpread
        for ring in [2.0, 1.0] {
            let shadow = knob.insetBy(dx: -spread * ring, dy: -spread * ring).intersection(track)
            list.append(.fillRRect(shadow, cornerRadius: shadow.height / 2, RGBA(r: 0, g: 0, b: 0, a: PlatformMetrics.switchKnobShadowRingAlpha * (enabled ? 1 : 0.5))))
        }
        list.append(.fillRRect(knob, cornerRadius: knob.height / 2, environment._knob.multiplyingAlpha(by: enabled ? 1 : 0.6)))
    }

    /// The iOS 26 switch (ios/toggle/basic): a green (on) or grey (off) capsule filling its frame
    /// with a white pill knob and its shadow; disabled, the track at half strength and the knob
    /// as it is (Docs/elements/iOS.md).
    private func paintIOS(into list: inout DisplayList, context: PaintContext) {
        let frame = absoluteBounds(context)
        let size = PlatformMetrics.switchSize
        let track = CGRect(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2, width: size.width, height: size.height)
        let enabled = environment.isEnabled
        let dim = enabled ? 1.0 : 0.5
        let offAlpha = environment._isDark ? PlatformMetrics.switchOffAlphaDark : PlatformMetrics.switchOffAlpha
        let onColor = environment._tint.map { $0.resolve(in: environment) } ?? PlatformMetrics.switchOnColor
        let fill = view.isOn ? onColor.multiplyingAlpha(by: dim) : environment._ink(offAlpha * dim)
        list.append(.fillRRect(track, cornerRadius: track.height / 2, fill))
        let inset = PlatformMetrics.switchKnobInset
        let knobSize = PlatformMetrics.switchKnobSize
        // The knob sits 2 pt nearer the on end than the off one (measured 0.5 and 2.5 in).
        let knob = CGRect(x: view.isOn ? track.maxX - max(0.5, inset - 2) - knobSize.width : track.minX + inset,
                          y: track.midY - knobSize.height / 2, width: knobSize.width, height: knobSize.height)
        list.append(.fillRRect(knob.offsetBy(dx: 0, dy: 1).insetBy(dx: -0.5, dy: -0.5), cornerRadius: knob.height / 2 + 0.5,
                               RGBA(r: 0, g: 0, b: 0, a: PlatformMetrics.switchKnobShadowAlpha * dim)))
        list.append(.fillRRect(knob, cornerRadius: knob.height / 2, RGBA(r: 255, g: 255, b: 255, a: 1)))
    }
}
