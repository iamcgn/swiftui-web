// The text field node: layout, painting of bezel, text, placeholder and bullets, focus, and the
// text-change and submit entry points the host calls from its `<input>` element.

/// What a host needs to place and drive a real input element over a text field.
public struct TextInputInfo: Equatable, Sendable {
    /// The field's text and placeholder.
    public var text: String
    public var placeholder: String
    public var isSecure: Bool
    /// The rectangle the text occupies (window coordinates): the input goes there.
    public var textRect: CGRect
    public var font: DisplayFont
    public var isEnabled: Bool

    public init(text: String, placeholder: String, isSecure: Bool, textRect: CGRect, font: DisplayFont, isEnabled: Bool) {
        self.text = text
        self.placeholder = placeholder
        self.isSecure = isSecure
        self.textRect = textRect
        self.font = font
        self.isEnabled = isEnabled
    }
}

@MainActor
package final class TextFieldNode: LeafNode<_TextFieldCore>, _Interactive {
    override package var layoutSpacing: ViewSpacing {
        .control(top: PlatformMetrics.textFieldSpacing, bottom: PlatformMetrics.textFieldSpacing,
                 belowText: PlatformMetrics.textFieldSpacing, aboveText: PlatformMetrics.textFieldSpacing)
    }

    private static var nextIdentifier = 3_000_000
    package let identifier: Int

    override package init(_ context: _NodeContext<_TextFieldCore>) {
        Self.nextIdentifier += 1
        identifier = Self.nextIdentifier
        super.init(context)
    }

    private var bezel: _TextFieldBezel { view.style._bezel }
    private var resolvedFont: ResolvedFont {
        (environment.font ?? environment.platformProfile.defaultFont).resolve(profile: environment.platformProfile)
    }
    private var metrics: SystemFontMetrics { environment.platformProfile.systemFontMetrics(for: resolvedFont) }

    /// Insets between the frame and the text line: 6 pt sideways and 4 pt vertically for a bezel,
    /// none for the plain style.
    private var insets: EdgeInsets {
        bezel == .plain ? EdgeInsets() : EdgeInsets(top: PlatformMetrics.textFieldVerticalPadding, leading: PlatformMetrics.textFieldHorizontalPadding,
                                                    bottom: PlatformMetrics.textFieldVerticalPadding, trailing: PlatformMetrics.textFieldHorizontalPadding)
    }

    private func textWidth(_ string: String) -> CGFloat {
        guard !string.isEmpty else { return 0 }
        return runtime.textEngine.layout(string, font: resolvedFont, width: nil).size.width
    }

    override package func computeSizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
        let insets = insets
        let lineHeight = metrics.lineHeight
        // Flexible across the proposal; the ideal width fits the longer of text and placeholder.
        let ideal = max(textWidth(view.text.wrappedValue), textWidth(view.placeholder)) + insets.leading + insets.trailing
        if view.fitsText {
            let shown = view.text.wrappedValue.isEmpty ? view.placeholder : view.text.wrappedValue
            return CGSize(width: textWidth(shown) + insets.leading + insets.trailing,
                          height: max(lineHeight + insets.top + insets.bottom, bezel == .plain ? 0 : PlatformMetrics.textFieldHeight))
        }
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? ideal
        let height = max(lineHeight + insets.top + insets.bottom, bezel == .plain ? 0 : PlatformMetrics.textFieldHeight)
        return CGSize(width: width, height: height)
    }

    override package func dimensions(in proposal: ProposedViewSize) -> ViewDimensions {
        let size = sizeThatFits(proposal)
        let baseline = (size.height - metrics.lineHeight) / 2 + metrics.baseline
        return ViewDimensions(size: size, explicit: [
            VerticalAlignment.firstTextBaseline.key: baseline,
            VerticalAlignment.lastTextBaseline.key: baseline,
        ])
    }

    /// The text line's rectangle within the frame.
    package var textRect: CGRect {
        let insets = insets
        let lineHeight = metrics.lineHeight
        return CGRect(x: insets.leading, y: (frame.height - lineHeight) / 2,
                      width: max(0, frame.width - insets.leading - insets.trailing), height: lineHeight)
    }

    override package func paintSelf(into list: inout DisplayList, context: PaintContext) {
        let bounds = absoluteBounds(context)
        let enabled = environment.isEnabled
        if bezel != .plain {
            let outer = bounds.insetBy(dx: -PlatformMetrics.textFieldBorderWidth, dy: -PlatformMetrics.textFieldBorderWidth)
            list.append(.fillRRect(outer, cornerRadius: PlatformMetrics.textFieldCornerRadius + PlatformMetrics.textFieldBorderWidth,
                                   RGBA(red: 0, green: 0, blue: 0, alpha: PlatformMetrics.textFieldBorderAlpha)))
            list.append(.fillRRect(bounds, cornerRadius: PlatformMetrics.textFieldCornerRadius,
                                   RGBA(red: 1, green: 1, blue: 1, alpha: enabled ? 1 : PlatformMetrics.textFieldDisabledFillAlpha)))
            if runtime.focusedTextFieldIdentifier == identifier {
                let ring = bounds.insetBy(dx: -PlatformMetrics.focusRingWidth / 2, dy: -PlatformMetrics.focusRingWidth / 2)
                list.append(.strokePath(Path(roundedRect: ring, cornerRadius: PlatformMetrics.textFieldCornerRadius + PlatformMetrics.focusRingWidth / 2, style: .circular),
                                        style: StrokeStyle(lineWidth: PlatformMetrics.focusRingWidth),
                                        Color.accentColor.opacity(PlatformMetrics.focusRingOpacity).resolve(in: environment)))
            }
        }
        let text = view.text.wrappedValue
        let rect = context.absoluteRect(textRect)
        let font = resolvedFont
        let baseline = CGPoint(x: rect.minX, y: rect.minY + metrics.baseline)
        if text.isEmpty {
            guard !view.placeholder.isEmpty else { return }
            list.append(.drawText(view.placeholder, DisplayFont(font), origin: baseline, Color.secondary.resolve(in: environment)))
        } else if view.isSecure {
            let color = (environment.foregroundColor ?? .primary).resolve(in: environment)
            let radius = PlatformMetrics.secureBulletDiameter / 2
            var x = rect.minX + PlatformMetrics.secureBulletInset + radius
            let y = baseline.y - PlatformMetrics.secureBulletBaselineOffset
            for _ in text {
                guard x + radius <= rect.maxX + 0.5 else { break }
                list.append(.fillPath(Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: 2 * radius, height: 2 * radius)), color))
                x += PlatformMetrics.secureBulletPitch
            }
        } else {
            var color = (environment.foregroundColor ?? .primary).resolve(in: environment)
            if !enabled { color = color.multiplyingAlpha(by: PlatformMetrics.disabledLabelOpacity) }
            list.withSavedState { list in
                list.append(.clipRect(rect))
                list.append(.drawText(text, DisplayFont(font), origin: baseline, color))
            }
        }
    }

    // MARK: Interaction

    package func pressBegan() {}
    package func pressEnded(inside: Bool) {
        guard inside, environment.isEnabled else { return }
        runtime.focusTextField(identifier)
    }

    package var semantics: SemanticsNode {
        let absolute = frameInRoot
        let rect = textRect.offsetBy(dx: absolute.minX, dy: absolute.minY)
        let info = TextInputInfo(text: view.text.wrappedValue, placeholder: view.placeholder, isSecure: view.isSecure,
                                 textRect: rect, font: DisplayFont(resolvedFont), isEnabled: environment.isEnabled)
        return SemanticsNode(role: .textField, label: view.placeholder, frame: absolute, identifier: identifier, textInput: info)
    }

    /// The host's input changed: push the text into the binding.
    package func setText(_ text: String) {
        guard view.text.wrappedValue != text else { return }
        view.text.wrappedValue = text
    }

    package func submit() {
        environment.submitAction?.run()
    }
}

extension Runtime {
    /// Text typed into the field with this semantics identifier (from the host's input element).
    public func textField(_ semanticsIdentifier: Int, didChange text: String) {
        guard let node = interactiveNodes.first(where: { $0.semantics.identifier == semanticsIdentifier }) as? TextFieldNode else { return }
        node.setText(text)
    }

    /// Return pressed in the field with this identifier.
    public func textFieldDidSubmit(_ semanticsIdentifier: Int) {
        guard let node = interactiveNodes.first(where: { $0.semantics.identifier == semanticsIdentifier }) as? TextFieldNode else { return }
        node.submit()
    }

    /// The host's input gained or lost focus.
    public func textField(_ semanticsIdentifier: Int, focused: Bool) {
        if focused {
            focusTextField(semanticsIdentifier)
        } else if focusedTextFieldIdentifier == semanticsIdentifier {
            focusTextField(nil)
        }
    }
}
