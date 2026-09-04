// TextEditor node (Docs/elements/TextEditor.md): fills its proposal, paints a white background
// and the text in black 5 pt in, the first line's cap height at the top edge and lines at the
// text view's pitch (font size × 0.955, rounded) plus the line spacing; focus hands editing to
// the host's multi-line input.

@MainActor
private var nextEditorIdentifier = 9_500_000

@MainActor
package final class TextEditorNode: LeafNode<_TextEditorHost>, _Interactive, _TextInputNode {
    private let identifier: Int

    override package init(_ context: _NodeContext<_TextEditorHost>) {
        nextEditorIdentifier += 1
        identifier = nextEditorIdentifier
        super.init(context)
    }

    private var resolvedFont: ResolvedFont {
        (environment.font ?? environment.platformProfile.defaultFont).resolve(profile: environment.platformProfile)
    }

    /// The distance between baselines: the text view's line height for the font, plus the
    /// environment's line spacing.
    package var linePitch: CGFloat {
        (resolvedFont.size * PlatformMetrics.textEditorLineFactor).rounded() + environment.lineSpacing
    }

    /// The first baseline below the top edge: the cap height, plus a top gap that grows with
    /// the font size (two measurements: 13 pt and 22 pt).
    package var firstBaseline: CGFloat {
        let font = resolvedFont
        let cap = environment.platformProfile.systemFontMetrics(for: font).capHeight
        return cap + max(0, font.size - PlatformMetrics.textEditorBaseSize) * PlatformMetrics.textEditorTopGrowth
    }

    override package func computeSizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
        CGSize(width: proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? PlatformMetrics.textEditorIdealSize.width,
               height: proposal.height.flatMap { $0.isFinite ? $0 : nil } ?? PlatformMetrics.textEditorIdealSize.height)
    }

    /// The text area: 5 pt in from the sides.
    package var textRect: CGRect {
        CGRect(x: PlatformMetrics.textEditorInset, y: 0, width: max(0, frame.width - 2 * PlatformMetrics.textEditorInset), height: frame.height)
    }

    private var layout: TextLayout? {
        guard !view.value.isEmpty else { return nil }
        return runtime.textEngine.layout([StyledRun(view.value, font: resolvedFont)], options: TextLayoutOptions(lineSpacing: environment.lineSpacing),
                                         width: textRect.width)
    }

    override package func paintSelf(into list: inout DisplayList, context: PaintContext) {
        let bounds = absoluteBounds(context)
        if view.paintsBackground {
            list.append(.fillRect(bounds, RGBA(red: 1, green: 1, blue: 1, alpha: 1)))
        }
        guard let layout else { return }
        let rect = context.absoluteRect(textRect)
        let color = environment.foregroundColor?.resolve(in: environment) ?? PlatformMetrics.textEditorTextColor
        let font = DisplayFont(resolvedFont)
        let pitch = linePitch
        var baseline = bounds.minY + firstBaseline
        list.withSavedState { list in
            list.append(.clipRect(bounds))
            for line in layout.lines {
                for fragment in line.fragments where !fragment.text.isEmpty {
                    list.append(.drawText(fragment.text, font, origin: CGPoint(x: rect.minX + fragment.x, y: baseline), color))
                }
                baseline += pitch
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
        var info = TextInputInfo(text: view.value, placeholder: "", isSecure: false, textRect: textRect.offsetBy(dx: absolute.minX, dy: absolute.minY),
                                 font: DisplayFont(resolvedFont), isEnabled: environment.isEnabled)
        info.isMultiline = true
        info.lineHeight = linePitch
        info.firstBaseline = firstBaseline
        return SemanticsNode(role: .textField, label: "", frame: absolute, identifier: identifier, textInput: info)
    }

    package func setText(_ text: String) {
        guard view.text.wrappedValue != text else { return }
        view.text.wrappedValue = text
    }

    /// Return inserts a newline in an editor.
    package func submit() {
        setText(view.text.wrappedValue + "\n")
    }
}
