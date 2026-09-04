// Picker, Slider and Stepper runtime nodes: the picker lays its label and options out per style
// and paints the pop-up button, segmented control or radio group; the slider track and the
// stepper buttons are painted leaves that change their bindings on presses and drags
// (Docs/elements/{Picker,Slider,Stepper}.md).

@MainActor
private var nextControlIdentifier = 5_000_000

extension ViewSpacing {
    /// The default-stack spacing a macOS control declares: `top`/`bottom` towards plain
    /// neighbours, `belowText` under a text, `aboveText` over one (form/basic row gaps).
    package static func control(top: CGFloat, bottom: CGFloat, belowText: CGFloat = 0, aboveText: CGFloat = 0) -> ViewSpacing {
        var spacing = ViewSpacing()
        spacing[nil, .top] = top
        spacing[nil, .bottom] = bottom
        spacing[.edgeBelowText, .top] = belowText
        spacing[.edgeAboveText, .bottom] = aboveText
        return spacing
    }

    /// A pop-up button or stepper: text-like (4.74 above, 8.15 below).
    package static let textLikeControl = ViewSpacing.control(top: PlatformMetrics.controlSpacingAbove, bottom: PlatformMetrics.controlSpacingBelow,
                                                             aboveText: PlatformMetrics.controlSpacingBelow)
    /// A segmented control or slider: 4.74 on both sides, nothing extra next to text.
    package static let plainControl = ViewSpacing.control(top: PlatformMetrics.controlSpacingAbove, bottom: PlatformMetrics.controlSpacingAbove)
}

/// The layout leaves of a picker's content with their tags (`ForEach` ids stand in for missing
/// tags); a unary modifier on a `ForEach` applies to each option through its proxies.
@MainActor
package func _collectOptions(_ node: ViewNode, wrap: @MainActor (ViewNode) -> ViewNode = { $0 }) -> [(node: ViewNode, id: AnyHashable?)] {
    var result: [(node: ViewNode, id: AnyHashable?)] = []
    func walk(_ node: ViewNode, id: AnyHashable?, wrap: @MainActor (ViewNode) -> ViewNode) {
        if let forEach = node as? any _ForEachNodeProviding {
            for (entryID, entryNode) in forEach._entries { walk(entryNode, id: entryID, wrap: wrap) }
            return
        }
        if let modifier = node as? any _UnaryLayoutModifier {
            var proxies: [ObjectIdentifier: ViewNode] = [:]
            for (target, proxy) in zip(modifier.targets, node.layoutChildren) { proxies[ObjectIdentifier(target)] = proxy }
            walk(modifier.modifiedContent, id: id) { wrap(proxies[ObjectIdentifier($0)] ?? $0) }
            return
        }
        if node.isLayoutNode {
            result.append((wrap(node), id))
            return
        }
        for structural in node.structuralChildren { walk(structural, id: id, wrap: wrap) }
    }
    walk(node, id: nil, wrap: wrap)
    return result
}

// MARK: - Picker

@MainActor
package final class PickerNode: LayoutNode<_PickerHost>, _Interactive, _KeyHandling {
    private let identifier: Int
    package private(set) var label: TypedNode<AnyView>?
    package private(set) var content: TypedNode<AnyView>!
    /// The pop-up and segmented styles show each option's title in their own text (as
    /// `NSPopUpButton`/`NSSegmentedControl` do); the option views are only walked for tags and
    /// titles. The radio group lays the option views out themselves.
    private var titles: [TypedNode<AnyView>] = []

    package struct Option {
        package let node: ViewNode
        package let tag: AnyHashable?
        package let title: String
        /// The node placed and painted for this option: the title text, or the option itself.
        package var shown: ViewNode?
        package var frame: CGRect = .zero        // the option's cell (segment or radio row)
    }

    package private(set) var options: [Option] = []
    private var labelFrame: CGRect = .zero
    private var controlFrame: CGRect = .zero

    package init(_ context: _NodeContext<_PickerHost>) {
        nextControlIdentifier += 1
        identifier = nextControlIdentifier
        super.init(view: context.view, parent: context.parent, runtime: context.runtime, environment: context.environment)
        mountChildren(force: true)
    }

    private var style: _PickerStyleKind { view.style }
    private var enabled: Bool { environment.isEnabled }

    private func labelEnvironment() -> EnvironmentValues {
        var environment = environment
        environment.font = .body
        if !enabled { environment.foregroundColor = Color.primary.opacity(PlatformMetrics.disabledLabelOpacity) }
        return environment
    }

    private func optionEnvironment() -> EnvironmentValues {
        var environment = environment
        environment.font = style == .radioGroup ? .body : .system(size: PlatformMetrics.buttonLabelSize)
        if !enabled { environment.foregroundColor = Color.primary.opacity(PlatformMetrics.disabledLabelOpacity) }
        return environment
    }

    /// The text a pop-up or segment shows for an option, in the style's font and colour.
    private func titleView(_ title: String, selected: Bool) -> AnyView {
        let color: Color
        switch style {
        case .segmented:
            let alpha = selected ? PlatformMetrics.segmentedSelectedTextAlpha : PlatformMetrics.segmentedTextAlpha
            color = Color.black.opacity(enabled ? alpha : alpha / 2)
        case .menu, .radioGroup:
            color = enabled ? Color.primary : Color.black.opacity(PlatformMetrics.popUpDisabledTextAlpha)
        }
        return AnyView(Text(title).font(.system(size: PlatformMetrics.buttonLabelSize)).foregroundColor(color))
    }

    private func mountChildren(force: Bool) {
        if let labelView = view.label {
            if let label {
                label.update(view: labelView, environment: labelEnvironment(), force: force)
            } else {
                label = AnyView._makeNode(_NodeContext(view: labelView, parent: self, environment: labelEnvironment()))
            }
        } else {
            label?.unmount()
            label = nil
        }
        if let content {
            content.update(view: view.content, environment: optionEnvironment(), force: force)
        } else {
            content = AnyView._makeNode(_NodeContext(view: view.content, parent: self, environment: optionEnvironment()))
        }
    }

    override package func update(view: _PickerHost, environment: EnvironmentValues, force: Bool) {
        self.view = view
        self.environment = environment
        clearNeedsUpdate()
        mountChildren(force: force)
    }

    private func collectOptions() -> [Option] {
        var result = _collectOptions(content).map { entry in
            Option(node: entry.node, tag: entry.node.layoutValue(for: TagKey.self) ?? entry.id,
                   title: entry.node.descendants(where: { $0 is TextNode }).compactMap { ($0 as? TextNode)?.view.resolvedString }.joined(separator: " "))
        }
        if style == .radioGroup {
            for node in titles { node.unmount() }
            titles.removeAll()
            for index in result.indices { result[index].shown = result[index].node }
        } else {
            while titles.count > result.count { titles.removeLast().unmount() }
            for index in result.indices {
                let view = titleView(result[index].title, selected: result[index].tag == self.view.selected)
                if index < titles.count {
                    titles[index].update(view: view, environment: environment, force: false)
                } else {
                    titles.append(AnyView._makeNode(_NodeContext(view: view, parent: self, environment: environment)))
                }
                result[index].shown = titles[index].layoutChildren.first
            }
        }
        return result
    }

    private func isSelected(_ option: Option) -> Bool { option.tag == view.selected }

    // MARK: Layout

    private struct Plan {
        var options: [Option]
        var label: CGRect
        var control: CGRect
        var size: CGSize
    }

    private func plan() -> Plan {
        var options = collectOptions()
        let unspecified = ProposedViewSize(width: nil, height: nil)
        let labelSize = label?.layoutChildren.first?.sizeThatFits(unspecified) ?? .zero
        let hasLabel = label?.layoutChildren.isEmpty == false
        let labelWidth = hasLabel ? labelSize.width + PlatformMetrics.controlLabelSpacing : 0
        let sizes = options.map { $0.shown?.sizeThatFits(unspecified) ?? .zero }
        let widest = sizes.map(\.width).max() ?? 0
        switch style {
        case .menu:
            let width = PlatformMetrics.popUpTextInset + widest + PlatformMetrics.popUpChevronGap
                + PlatformMetrics.popUpChevronWidth + PlatformMetrics.popUpChevronTrailing
            let height = max(PlatformMetrics.popUpHeight, labelSize.height)
            let control = CGRect(x: labelWidth, y: (height - PlatformMetrics.popUpHeight) / 2, width: width, height: PlatformMetrics.popUpHeight)
            for index in options.indices {
                options[index].frame = CGRect(x: control.minX + PlatformMetrics.popUpTextInset, y: control.minY + (control.height - sizes[index].height) / 2,
                                              width: sizes[index].width, height: sizes[index].height)
            }
            return Plan(options: options, label: CGRect(x: 0, y: (height - labelSize.height) / 2, width: labelSize.width, height: labelSize.height),
                        control: control, size: CGSize(width: labelWidth + width, height: height))
        case .segmented:
            let segment = widest + PlatformMetrics.segmentPadding
            let width = segment * CGFloat(options.count)
            let height = max(PlatformMetrics.segmentedHeight, labelSize.height)
            let control = CGRect(x: labelWidth, y: (height - PlatformMetrics.segmentedHeight) / 2, width: width, height: PlatformMetrics.segmentedHeight)
            for index in options.indices {
                options[index].frame = CGRect(x: control.minX + segment * CGFloat(index), y: control.minY, width: segment, height: control.height)
            }
            return Plan(options: options, label: CGRect(x: 0, y: (height - labelSize.height) / 2, width: labelSize.width, height: labelSize.height),
                        control: control, size: CGSize(width: labelWidth + width, height: height))
        case .radioGroup:
            var y: CGFloat = 0
            var width: CGFloat = 0
            for index in options.indices {
                if index > 0 { y += PlatformMetrics.radioRowSpacing }
                let rowHeight = max(PlatformMetrics.radioSize, sizes[index].height)
                let rowWidth = PlatformMetrics.radioSize + PlatformMetrics.radioLabelSpacing + sizes[index].width
                options[index].frame = CGRect(x: labelWidth, y: y, width: rowWidth, height: rowHeight)
                width = max(width, rowWidth)
                y += rowHeight
            }
            let height = max(y, labelSize.height)
            return Plan(options: options, label: CGRect(x: 0, y: 0, width: labelSize.width, height: labelSize.height),
                        control: CGRect(x: labelWidth, y: 0, width: width, height: y), size: CGSize(width: labelWidth + width, height: height))
        }
    }

    override package func computeSizeThatFits(_ proposal: ProposedViewSize) -> CGSize { plan().size }

    /// In a columns form the control column starts where the control does.
    override package func dimensions(in proposal: ProposedViewSize) -> ViewDimensions {
        let plan = plan()
        var dims = ViewDimensions(size: plan.size)
        dims.explicit[HorizontalAlignment._formControlColumn.key] = plan.control.minX
        return dims
    }

    override package func layoutContents(proposal: ProposedViewSize) {
        let plan = plan()
        options = plan.options
        labelFrame = plan.label
        controlFrame = plan.control
        if let target = label?.layoutChildren.first {
            target.place(at: plan.label.origin, anchor: .topLeading, proposal: ProposedViewSize(plan.label.size), by: self)
        }
        for option in options {
            guard let shown = option.shown else { continue }
            let size = shown.sizeThatFits(ProposedViewSize(width: nil, height: nil))
            let origin: CGPoint
            switch style {
            case .menu: origin = option.frame.origin
            case .segmented: origin = CGPoint(x: option.frame.midX - size.width / 2, y: option.frame.midY - size.height / 2)
            case .radioGroup:
                origin = CGPoint(x: option.frame.minX + PlatformMetrics.radioSize + PlatformMetrics.radioLabelSpacing,
                                 y: option.frame.midY - size.height / 2)
            }
            shown.place(at: origin, anchor: .topLeading, proposal: ProposedViewSize(size), by: self)
        }
    }

    override package var paintedChildren: [ViewNode] {
        (label?.layoutChildren ?? []) + options.compactMap { style == .menu && !isSelected($0) ? nil : $0.shown }
    }
    override package var layoutSpacing: ViewSpacing { style == .segmented ? .plainControl : .textLikeControl }
    override package var structuralChildren: [ViewNode] { [label as ViewNode?, content].compactMap { $0 } + titles }
    override package var nodeDescription: String { "Picker" }

    override package func unmount() {
        label?.unmount()
        content.unmount()
        for node in titles { node.unmount() }
        super.unmount()
    }

    // MARK: Painting

    override package func paint(into list: inout DisplayList, context: PaintContext) {
        if let target = label?.layoutChildren.first { target.paint(into: &list, context: context.child(at: target.presentedFrame)) }
        switch style {
        case .menu: paintPopUp(into: &list, context: context)
        case .segmented: paintSegmented(into: &list, context: context)
        case .radioGroup: paintRadios(into: &list, context: context)
        }
    }

    private func black(_ alpha: Double) -> RGBA { environment._ink(alpha) }

    private func paintPopUp(into list: inout DisplayList, context: PaintContext) {
        let control = context.absoluteRect(controlFrame)
        list.append(.fillRRect(control, cornerRadius: PlatformMetrics.popUpCornerRadius,
                               black(enabled ? PlatformMetrics.popUpFill : PlatformMetrics.popUpDisabledFill)))
        if let shown = options.first(where: isSelected)?.shown {
            shown.paint(into: &list, context: context.child(at: shown.presentedFrame))
        }
        // Up and down chevrons before the trailing edge.
        let x0 = control.maxX - PlatformMetrics.popUpChevronTrailing - PlatformMetrics.popUpChevronWidth
        let x1 = x0 + PlatformMetrics.popUpChevronWidth
        let midX = (x0 + x1) / 2, midY = control.midY
        var chevrons = Path()
        chevrons.move(to: CGPoint(x: x0, y: midY - PlatformMetrics.popUpChevronOffset + 1.5))
        chevrons.addLine(to: CGPoint(x: midX, y: midY - PlatformMetrics.popUpChevronOffset - PlatformMetrics.popUpChevronHalfHeight + 1.5))
        chevrons.addLine(to: CGPoint(x: x1, y: midY - PlatformMetrics.popUpChevronOffset + 1.5))
        chevrons.move(to: CGPoint(x: x0, y: midY + PlatformMetrics.popUpChevronOffset - 1.5))
        chevrons.addLine(to: CGPoint(x: midX, y: midY + PlatformMetrics.popUpChevronOffset + PlatformMetrics.popUpChevronHalfHeight - 1.5))
        chevrons.addLine(to: CGPoint(x: x1, y: midY + PlatformMetrics.popUpChevronOffset - 1.5))
        let style = StrokeStyle(lineWidth: PlatformMetrics.popUpChevronStroke, lineCap: .round, lineJoin: .round)
        list.append(.strokePath(chevrons, style: style, black(enabled ? PlatformMetrics.radioDotAlpha : PlatformMetrics.popUpDisabledTextAlpha)))
    }

    private func paintSegmented(into list: inout DisplayList, context: PaintContext) {
        let control = context.absoluteRect(controlFrame)
        list.append(.fillRRect(control, cornerRadius: PlatformMetrics.segmentedCornerRadius,
                               black(enabled ? PlatformMetrics.segmentedFill : PlatformMetrics.popUpDisabledFill)))
        let selectedIndex = options.firstIndex(where: isSelected)
        if let selectedIndex {
            let cell = context.absoluteRect(options[selectedIndex].frame)
            list.append(.fillRRect(cell, cornerRadius: PlatformMetrics.segmentedCornerRadius,
                                   black(enabled ? PlatformMetrics.segmentedSelectedFill : PlatformMetrics.segmentedSelectedFill / 2)))
        }
        // Dividers between segments, except next to the selected one.
        for index in options.indices.dropFirst() where index != selectedIndex && index - 1 != selectedIndex {
            let x = context.round(context.origin.x + options[index].frame.minX)
            let line = CGRect(x: x, y: control.minY + PlatformMetrics.segmentedDividerInset, width: 1,
                              height: control.height - 2 * PlatformMetrics.segmentedDividerInset)
            list.append(.fillRect(line, black(PlatformMetrics.segmentedDividerAlpha)))
        }
        for option in options {
            if let shown = option.shown { shown.paint(into: &list, context: context.child(at: shown.presentedFrame)) }
        }
    }

    private func paintRadios(into list: inout DisplayList, context: PaintContext) {
        for option in options {
            let selected = isSelected(option)
            let circle = context.absoluteRect(CGRect(x: option.frame.minX, y: option.frame.midY - PlatformMetrics.radioSize / 2,
                                                     width: PlatformMetrics.radioSize, height: PlatformMetrics.radioSize))
            var fill = selected ? PlatformMetrics.radioFillOn : PlatformMetrics.radioFillOff
            if !enabled { fill /= 2 }
            var path = Path()
            path.addEllipse(in: circle)
            list.append(.fillPath(path, black(fill)))
            if selected {
                let dot = circle.insetBy(dx: (PlatformMetrics.radioSize - PlatformMetrics.radioDotSize) / 2,
                                         dy: (PlatformMetrics.radioSize - PlatformMetrics.radioDotSize) / 2)
                var dotPath = Path()
                dotPath.addEllipse(in: dot)
                list.append(.fillPath(dotPath, black(enabled ? PlatformMetrics.radioDotAlpha : PlatformMetrics.radioDotAlpha / 2)))
            }
            if let shown = option.shown { shown.paint(into: &list, context: context.child(at: shown.presentedFrame)) }
        }
    }

    // MARK: Interaction

    package func pressBegan() {}
    package func pressEnded(inside: Bool) {}

    package func pressEnded(inside: Bool, at point: CGPoint) {
        guard inside, enabled else { return }
        switch style {
        case .menu:
            let titles = options.map(\.title)
            let selectedIndex = options.firstIndex(where: isSelected)
            let select = view.select
            let tags = options.map(\.tag)
            let list = _MenuList(titles: titles, selected: selectedIndex, select: _MenuSelection { index in
                if let tag = tags[index] { select.select(tag) }
            })
            runtime.present(kind: .menu, view: AnyView(list), environment: environment, anchor: self) {}
        case .segmented, .radioGroup:
            guard let option = options.first(where: { $0.frame.contains(point) }), let tag = option.tag else { return }
            view.select.select(tag)
            runtime.setNeedsDisplay()
        }
    }

    /// Left/Right (and Up/Down) move a segmented or radio group's selection to the previous or
    /// next option; a pop-up opens its menu on Down.
    package func handleKey(_ press: KeyPress) -> Bool {
        guard enabled, press.modifiers.shortcutModifiers.isEmpty else { return false }
        let step: Int
        switch press.key {
        case .rightArrow, .downArrow: step = 1
        case .leftArrow, .upArrow: step = -1
        default: return false
        }
        if style == .menu {
            guard step == 1 else { return false }
            pressEnded(inside: true, at: .zero)
            return true
        }
        let selectable = options.filter { $0.tag != nil }
        guard !selectable.isEmpty else { return false }
        let current = selectable.firstIndex(where: isSelected) ?? (step == 1 ? -1 : selectable.count)
        let next = min(max(current + step, 0), selectable.count - 1)
        guard let tag = selectable[next].tag, next != current else { return true }
        view.select.select(tag)
        runtime.setNeedsDisplay()
        return true
    }

    package var semantics: SemanticsNode {
        let text = label?.descendants(where: { $0 is TextNode }).compactMap { ($0 as? TextNode)?.view.resolvedString }.joined(separator: " ") ?? ""
        let role: SemanticsNode.Role
        switch style {
        case .menu: role = .popUpButton
        case .segmented: role = .segmented
        case .radioGroup: role = .radioGroup
        }
        var node = SemanticsNode(role: role, label: text, frame: frameInRoot, identifier: identifier)
        node.value = options.first(where: isSelected)?.title
        return node
    }
}

// MARK: - Slider

@MainActor
package final class SliderTrackNode: LeafNode<_SliderTrack>, _Interactive {
    private let identifier: Int
    private var editing = false

    override package init(_ context: _NodeContext<_SliderTrack>) {
        nextControlIdentifier += 1
        identifier = nextControlIdentifier
        super.init(context)
    }

    override package func computeSizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
        CGSize(width: proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? PlatformMetrics.sliderIdealWidth, height: PlatformMetrics.sliderHeight)
    }
    override package var layoutSpacing: ViewSpacing { .plainControl }

    /// Where the knob's centre sits for the current value, in local coordinates.
    private var knobCenterX: CGFloat {
        let travel = max(0, frame.width - 2 * PlatformMetrics.sliderKnobInset)
        let span = view.range.upperBound - view.range.lowerBound
        let t = span > 0 ? (view.value.get() - view.range.lowerBound) / span : 0
        return PlatformMetrics.sliderKnobInset + travel * CGFloat(min(max(t, 0), 1))
    }

    override package func paintSelf(into list: inout DisplayList, context: PaintContext) {
        let bounds = absoluteBounds(context)
        let enabled = environment.isEnabled
        let trackY = bounds.minY + (bounds.height - PlatformMetrics.sliderTrackHeight) / 2
        let track = CGRect(x: bounds.minX, y: trackY, width: bounds.width, height: PlatformMetrics.sliderTrackHeight)
        let ink = environment; let black = { (alpha: Double) in ink._ink(alpha) }
        list.append(.fillRRect(track, cornerRadius: track.height / 2, black(PlatformMetrics.sliderTrackAlpha)))
        let knobX = bounds.minX + knobCenterX
        let filled = CGRect(x: track.minX, y: track.minY, width: max(0, knobX - track.minX), height: track.height)
        list.append(.fillRRect(filled, cornerRadius: track.height / 2, black(enabled ? PlatformMetrics.sliderFilledAlpha : PlatformMetrics.sliderDisabledFilledAlpha)))
        if let step = view.step, step > 0 {
            let span = view.range.upperBound - view.range.lowerBound
            let count = span > 0 ? Int((span / step).rounded()) : 0
            if count > 0 && count <= 200 {
                let travel = bounds.width - 2 * PlatformMetrics.sliderKnobInset
                for index in 0...count {
                    let x = bounds.minX + PlatformMetrics.sliderKnobInset + travel * CGFloat(index) / CGFloat(count)
                    let tick = CGRect(x: x - PlatformMetrics.sliderTickSize / 2, y: bounds.minY + PlatformMetrics.sliderTickTop,
                                      width: PlatformMetrics.sliderTickSize, height: PlatformMetrics.sliderTickSize)
                    list.append(.fillRRect(tick, cornerRadius: tick.width / 2, black(PlatformMetrics.sliderFilledAlpha)))
                }
            }
        }
        let knobSize = PlatformMetrics.sliderKnobSize
        let knob = CGRect(x: knobX - knobSize.width / 2, y: bounds.minY + (bounds.height - knobSize.height) / 2, width: knobSize.width, height: knobSize.height)
        if enabled {
            list.append(.fillRRect(knob.insetBy(dx: -1, dy: -1), cornerRadius: knob.height / 2 + 1, black(PlatformMetrics.sliderKnobShadowAlpha)))
        }
        list.append(.fillRRect(knob, cornerRadius: knob.height / 2, environment._knob))
    }

    // MARK: Interaction

    private func value(at point: CGPoint) -> Double {
        let travel = max(1, frame.width - 2 * PlatformMetrics.sliderKnobInset)
        let t = min(max((point.x - PlatformMetrics.sliderKnobInset) / travel, 0), 1)
        var value = view.range.lowerBound + Double(t) * (view.range.upperBound - view.range.lowerBound)
        if let step = view.step, step > 0 {
            value = view.range.lowerBound + ((value - view.range.lowerBound) / step).rounded() * step
        }
        return min(max(value, view.range.lowerBound), view.range.upperBound)
    }

    private func set(_ value: Double) {
        guard value != view.value.get() else { return }
        view.value.set(value)
        runtime.setNeedsDisplay()
    }

    package func pressBegan() {}
    package func pressBegan(at point: CGPoint) {
        guard environment.isEnabled else { return }
        editing = true
        view.onEditingChanged.run(true)
        set(value(at: point))
    }
    package func pressMoved(to point: CGPoint) {
        guard editing else { return }
        set(value(at: point))
    }
    package func pressEnded(inside: Bool) {
        guard editing else { return }
        editing = false
        view.onEditingChanged.run(false)
    }

    package var semantics: SemanticsNode {
        var node = SemanticsNode(role: .slider, label: "", frame: frameInRoot, identifier: identifier)
        let current = view.value.get()
        node.range = SemanticsRange(minimum: view.range.lowerBound, maximum: view.range.upperBound, value: current, step: view.step)
        let span = view.range.upperBound - view.range.lowerBound
        node.value = "\(Int(((span > 0 ? (current - view.range.lowerBound) / span : 0) * 100).rounded())) percent"
        node.isAdjustable = true
        return node
    }
}

extension SliderTrackNode: _Adjustable {
    package func adjust(increment: Bool) {
        let step = view.step ?? (view.range.upperBound - view.range.lowerBound) / 10
        setValue(view.value.get() + (increment ? step : -step))
    }

    package func setValue(_ value: Double) {
        let clamped = min(max(value, view.range.lowerBound), view.range.upperBound)
        guard clamped != view.value.get() else { return }
        view.value.set(clamped)
        runtime.setNeedsDisplay()
    }
}

// MARK: - Stepper

@MainActor
package final class StepperControlNode: LeafNode<_StepperControl>, _Interactive {
    private let identifier: Int

    override package init(_ context: _NodeContext<_StepperControl>) {
        nextControlIdentifier += 1
        identifier = nextControlIdentifier
        super.init(context)
    }

    override package func computeSizeThatFits(_ proposal: ProposedViewSize) -> CGSize { PlatformMetrics.stepperSize }
    override package var layoutSpacing: ViewSpacing { .textLikeControl }

    override package func paintSelf(into list: inout DisplayList, context: PaintContext) {
        let bounds = absoluteBounds(context)
        let enabled = environment.isEnabled
        let ink = environment; let black = { (alpha: Double) in ink._ink(alpha) }
        list.append(.fillRRect(bounds, cornerRadius: PlatformMetrics.stepperCornerRadius,
                               black(enabled ? PlatformMetrics.stepperFill : PlatformMetrics.stepperDisabledFill)))
        let divider = CGRect(x: bounds.minX + PlatformMetrics.stepperDividerInset, y: context.round(bounds.midY),
                             width: bounds.width - 2 * PlatformMetrics.stepperDividerInset, height: 1)
        list.append(.fillRect(divider, black(PlatformMetrics.stepperDividerAlpha)))
        let x0 = bounds.minX + PlatformMetrics.stepperChevronInset, x1 = bounds.maxX - PlatformMetrics.stepperChevronInset
        let midX = bounds.midX
        var chevrons = Path()
        chevrons.move(to: CGPoint(x: x0, y: bounds.minY + PlatformMetrics.stepperUpChevronBase))
        chevrons.addLine(to: CGPoint(x: midX, y: bounds.minY + PlatformMetrics.stepperUpChevronBase - PlatformMetrics.stepperChevronRise))
        chevrons.addLine(to: CGPoint(x: x1, y: bounds.minY + PlatformMetrics.stepperUpChevronBase))
        chevrons.move(to: CGPoint(x: x0, y: bounds.minY + PlatformMetrics.stepperDownChevronBase))
        chevrons.addLine(to: CGPoint(x: midX, y: bounds.minY + PlatformMetrics.stepperDownChevronBase + PlatformMetrics.stepperChevronRise))
        chevrons.addLine(to: CGPoint(x: x1, y: bounds.minY + PlatformMetrics.stepperDownChevronBase))
        let style = StrokeStyle(lineWidth: PlatformMetrics.stepperChevronStroke, lineCap: .round, lineJoin: .round)
        list.append(.strokePath(chevrons, style: style, black(enabled ? PlatformMetrics.stepperChevronAlpha : PlatformMetrics.stepperDisabledChevronAlpha)))
    }

    package func pressBegan() {}
    package func pressEnded(inside: Bool) {}
    package func pressEnded(inside: Bool, at point: CGPoint) {
        guard inside, environment.isEnabled else { return }
        view.onEditingChanged.run(true)
        if point.y < frame.height / 2 { view.increment.run() } else { view.decrement.run() }
        view.onEditingChanged.run(false)
        runtime.setNeedsDisplay()
    }

    package var semantics: SemanticsNode {
        var node = SemanticsNode(role: .stepper, label: "", frame: frameInRoot, identifier: identifier)
        node.isAdjustable = true
        return node
    }
}

extension StepperControlNode: _Adjustable {
    package func adjust(increment: Bool) {
        guard environment.isEnabled else { return }
        if increment { view.increment.run() } else { view.decrement.run() }
        runtime.setNeedsDisplay()
    }

    package func setValue(_ value: Double) {}
}

// MARK: - Pixel alignment

/// Places its content at the nearest device pixel (2 × grid, halves rounded up), as the
/// AppKit-backed control rows do on macOS (`slider/basic` `min`, `Docs/elements/Slider.md`).
public struct _PixelAlignedModifier {
    package init() {}
}

extension _PixelAlignedModifier: ViewModifier {
    public typealias Body = Never
    public static func _makeNode<Content: View>(_ context: _NodeContext<ModifiedContent<Content, Self>>) -> TypedNode<ModifiedContent<Content, Self>> {
        PixelAlignedNode(context)
    }
}

@MainActor
package final class PixelAlignedNode<Content: View>: UnaryLayoutModifierNode<Content, _PixelAlignedModifier> {
    private func snap(_ value: CGFloat) -> CGFloat { (value * 2).rounded(.toNearestOrAwayFromZero) / 2 }

    override package func placeTarget(_ target: ViewNode, in bounds: CGRect, proposal: ProposedViewSize, by placer: ViewNode) {
        let root = placer.frameInRoot.origin
        let x = root.x + bounds.minX, y = root.y + bounds.minY
        super.placeTarget(target, in: bounds.offsetBy(dx: snap(x) - x, dy: snap(y) - y), proposal: proposal, by: placer)
    }
}

extension View {
    package func _pixelAligned() -> some View { modifier(_PixelAlignedModifier()) }
}
