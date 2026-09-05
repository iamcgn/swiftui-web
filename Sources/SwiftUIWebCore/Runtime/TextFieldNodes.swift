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
    /// A multi-line editor: the host gives it a multi-line input and Return inserts a newline.
    public var isMultiline = false
    /// The editor's distance between baselines and its first baseline below the text rect's
    /// top (0 for a single-line field, whose text line is the rect).
    public var lineHeight: CGFloat = 0
    public var firstBaseline: CGFloat = 0

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

    /// The style's bezel; the automatic style is plain on iOS (ios/textfield/basic `plain`).
    private var bezel: _TextFieldBezel {
        if environment.platformProfile.isIOS, view.style is DefaultTextFieldStyle { return .plain }
        return view.style._bezel
    }
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
        return runtime.layoutText(string, font: resolvedFont, width: nil).size.width
    }

    /// The frame's height: the bezel's, or the line plus the plain style's extra (iOS: 26 for a
    /// 24.5 pt body line, ios/textfield/basic).
    private func height(lineHeight: CGFloat, insets: EdgeInsets) -> CGFloat {
        bezel == .plain ? lineHeight + PlatformMetrics.textFieldPlainExtraHeight
            : max(lineHeight + insets.top + insets.bottom, PlatformMetrics.textFieldHeight)
    }

    override package func computeSizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
        let insets = insets
        let lineHeight = metrics.lineHeight
        // Flexible across the proposal; the ideal width fits the longer of text and placeholder.
        let ideal = max(textWidth(view.text.wrappedValue), textWidth(view.placeholder)) + insets.leading + insets.trailing
        if view.fitsText {
            let shown = view.text.wrappedValue.isEmpty ? view.placeholder : view.text.wrappedValue
            return CGSize(width: textWidth(shown) + insets.leading + insets.trailing, height: height(lineHeight: lineHeight, insets: insets))
        }
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? ideal
        return CGSize(width: width, height: height(lineHeight: lineHeight, insets: insets))
    }

    /// Where the text line sits below the centred position (iOS: 0.75 down in a bezel, at the
    /// top of the plain style's frame).
    private var textOffset: CGFloat { bezel == .plain ? PlatformMetrics.textFieldPlainTextOffset : PlatformMetrics.textFieldTextOffset }

    override package func dimensions(in proposal: ProposedViewSize) -> ViewDimensions {
        let size = sizeThatFits(proposal)
        let baseline = (size.height - metrics.lineHeight) / 2 + textOffset + metrics.baseline
        return ViewDimensions(size: size, explicit: [
            VerticalAlignment.firstTextBaseline.key: baseline,
            VerticalAlignment.lastTextBaseline.key: baseline,
        ])
    }

    /// The text line's rectangle within the frame.
    package var textRect: CGRect {
        let insets = insets
        let lineHeight = metrics.lineHeight
        return CGRect(x: insets.leading, y: (frame.height - lineHeight) / 2 + textOffset,
                      width: max(0, frame.width - insets.leading - insets.trailing), height: lineHeight)
    }

    override package func paintSelf(into list: inout DisplayList, context: PaintContext) {
        let bounds = absoluteBounds(context)
        let enabled = environment.isEnabled
        if bezel != .plain && PlatformMetrics.textFieldBorderInside {
            // iOS: a 0.5 pt border inside the frame (ios/textfield/basic).
            let border = PlatformMetrics.textFieldBorderWidth, radius = PlatformMetrics.textFieldCornerRadius
            list.append(.fillRRect(bounds, cornerRadius: radius, environment._ink(PlatformMetrics.textFieldBorderAlpha)))
            list.append(.fillRRect(bounds.insetBy(dx: border, dy: border), cornerRadius: radius - border,
                                   environment._controlBackground.multiplyingAlpha(by: enabled || environment._isDark ? 1 : PlatformMetrics.textFieldDisabledFillAlpha)))
        } else if bezel != .plain {
            let outer = bounds.insetBy(dx: -PlatformMetrics.textFieldBorderWidth, dy: -PlatformMetrics.textFieldBorderWidth)
            // Dark: a mid-grey ring at the same alpha over the opaque control background (dark/controls).
            list.append(.fillRRect(outer, cornerRadius: PlatformMetrics.textFieldCornerRadius + PlatformMetrics.textFieldBorderWidth,
                                   environment._isDark ? RGBA(r: 128, g: 128, b: 128, a: PlatformMetrics.textFieldBorderAlpha) : environment._ink(PlatformMetrics.textFieldBorderAlpha)))
            list.append(.fillRRect(bounds, cornerRadius: PlatformMetrics.textFieldCornerRadius,
                                   environment._controlBackground.multiplyingAlpha(by: enabled || environment._isDark ? 1 : PlatformMetrics.textFieldDisabledFillAlpha)))
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
            list.append(.drawText(view.placeholder, DisplayFont(font), origin: baseline, PlatformMetrics.textFieldPlaceholder ?? Color.secondary.resolve(in: environment)))
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

/// A node whose text the host's input edits (text fields and editors).
@MainActor
package protocol _TextInputNode: AnyObject {
    func setText(_ text: String)
    func submit()
}

extension TextFieldNode: _TextInputNode {}

extension Runtime {
    /// Text typed into the field with this semantics identifier (from the host's input element).
    public func textField(_ semanticsIdentifier: Int, didChange text: String) {
        guard let node = interactiveNodes.first(where: { $0.semantics.identifier == semanticsIdentifier }) as? any _TextInputNode else { return }
        node.setText(text)
    }

    /// Return pressed in the field with this identifier (an editor inserts a newline).
    public func textFieldDidSubmit(_ semanticsIdentifier: Int) {
        guard let node = interactiveNodes.first(where: { $0.semantics.identifier == semanticsIdentifier }) as? any _TextInputNode else { return }
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
