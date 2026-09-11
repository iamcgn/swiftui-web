// UITextView (Docs/elements/UIKit/TextView.md): a scroll view showing wrapped text, editable
// through the host's multi-line input. The geometry is UIKit's on the iPhone SE simulator
// (uikit/textview/*): the container insets (8 above and below), the 5 pt line fragment padding,
// lines on the font's pitch with the first baseline an ascender below the top inset, and
// `sizeThatFits` giving the text's used width plus the insets and the label height for the
// lines plus the insets.

/// The methods a text view's delegate implements.
@MainActor
public protocol UITextViewDelegate: UIScrollViewDelegate {
    func textViewShouldBeginEditing(_ textView: UITextView) -> Bool
    func textViewDidBeginEditing(_ textView: UITextView)
    func textViewShouldEndEditing(_ textView: UITextView) -> Bool
    func textViewDidEndEditing(_ textView: UITextView)
    func textViewDidChange(_ textView: UITextView)
    func textViewDidChangeSelection(_ textView: UITextView)
}

extension UITextViewDelegate {
    public func textViewShouldBeginEditing(_ textView: UITextView) -> Bool { true }
    public func textViewDidBeginEditing(_ textView: UITextView) {}
    public func textViewShouldEndEditing(_ textView: UITextView) -> Bool { true }
    public func textViewDidEndEditing(_ textView: UITextView) {}
    public func textViewDidChange(_ textView: UITextView) {}
    public func textViewDidChangeSelection(_ textView: UITextView) {}
}

/// The part of a text container UIKit code touches: the padding either side of each line.
@MainActor
public final class NSTextContainer {
    public var lineFragmentPadding: CGFloat = 5
    public var maximumNumberOfLines = 0
    public var lineBreakMode: NSLineBreakMode = .byWordWrapping
    init() {}
}

/// A scrollable, multiline text region.
@MainActor
open class UITextView: UIScrollView, HostTextInput {
    open var text: String! = "" { didSet { if text != oldValue { textDidChange() } } }
    /// The font; nil draws the default (UIKit's Helvetica 12, here the 12 pt system font).
    open var font: UIFont? { didSet { textDidChange() } }
    open var textColor: UIColor? = .label { didSet { setNeedsDisplay() } }
    open var textAlignment: NSTextAlignment = .natural { didSet { setNeedsDisplay() } }
    open var isEditable = true
    open var isSelectable = true
    open var textContainerInset = UIEdgeInsets(top: 8, left: 0, bottom: 8, right: 0) { didSet { textDidChange() } }
    public let textContainer = NSTextContainer()
    open var keyboardType: UIKeyboardType = .default
    open var returnKeyType: UIReturnKeyType = .default
    open var autocapitalizationType: UITextAutocapitalizationType = .sentences
    open var autocorrectionType: UITextAutocorrectionType = .default
    open var spellCheckingType: UITextSpellCheckingType = .default
    open var textContentType: String?
    /// The delegate is a text view delegate too (`UITextViewDelegate` refines the scroll
    /// view's, as in UIKit).
    open override weak var delegate: (any UIScrollViewDelegate)? {
        didSet { textViewDelegate = delegate as? any UITextViewDelegate }
    }
    private weak var textViewDelegate: (any UITextViewDelegate)?

    public override init(frame: CGRect) {
        super.init(frame: frame)
        isAccessibilityElement = true
        backgroundColor = .systemBackground
    }

    private func textDidChange() {
        invalidateIntrinsicContentSize()
        setNeedsLayout()
        setNeedsDisplay()
    }

    // MARK: Editing

    open var isEditing: Bool { isFirstResponder }
    override open var canBecomeFirstResponder: Bool { isEditable }

    @discardableResult
    override open func becomeFirstResponder() -> Bool {
        guard !isFirstResponder else { return true }
        guard textViewDelegate?.textViewShouldBeginEditing(self) ?? true, super.becomeFirstResponder() else { return false }
        textViewDelegate?.textViewDidBeginEditing(self)
        return true
    }

    @discardableResult
    override open func resignFirstResponder() -> Bool {
        guard isFirstResponder else { return true }
        guard textViewDelegate?.textViewShouldEndEditing(self) ?? true, super.resignFirstResponder() else { return false }
        textViewDelegate?.textViewDidEndEditing(self)
        return true
    }

    override open func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        if isEditable, let touch = touches.first, point(inside: touch.location(in: self), with: event) { becomeFirstResponder() }
    }

    /// The host's input element changed the text.
    func hostDidChange(_ newText: String) {
        guard newText != text else { return }
        text = newText
        textViewDelegate?.textViewDidChange(self)
        textViewDelegate?.textViewDidChangeSelection(self)
    }

    /// Return in a multi-line input is a newline the host inserts itself.
    func hostDidSubmit() {}

    // MARK: Geometry

    var resolvedFont: UIFont { font ?? .systemFont(ofSize: 12) }
    private var padding: CGFloat { textContainer.lineFragmentPadding }

    /// The width lines wrap to in a view `width` wide: the insets and the padding taken off.
    func containerWidth(for width: CGFloat) -> CGFloat {
        max(0, width - textContainerInset.left - textContainerInset.right - 2 * padding)
    }

    /// The pitch between lines: the font's line height on the pixel grid (TextKit's line
    /// fragments are pixel-aligned: 20.5 for 17 pt, 15.5 for 13 pt).
    var linePitch: CGFloat { (resolvedFont.lineHeight + resolvedFont.leading).roundedUp(to: UIScreen.main.scale) }

    /// The lines of text at `width`.
    private func layout(width: CGFloat) -> TextLayout? {
        let string = text ?? ""
        guard !string.isEmpty else { return nil }
        let limit = textContainer.maximumNumberOfLines > 0 ? textContainer.maximumNumberOfLines : nil
        return UIKitScene.shared.textEngine.layout([StyledRun(string, font: resolvedFont.resolved)], options: TextLayoutOptions(lineLimit: limit), width: width > 0 ? width : nil)
    }

    /// How many lines the view shows: a text view that does not scroll lays out only the lines
    /// its container holds, without an ellipsis (uikit/textview/basic `fitted`: two of three
    /// lines in 41 pt); a scrolling one shows them all.
    private var visibleLineLimit: Int? {
        guard !isScrollEnabled else { return nil }
        let available = bounds.height - textContainerInset.top - textContainerInset.bottom
        return max(1, Int((available / linePitch).rounded(.down)))
    }

    /// The lines the text makes at `width` (the recorded engine answers a wrapped request as one
    /// line of the recorded height, so a single line's count comes from that height).
    private func lineCount(of layout: TextLayout?) -> Int {
        guard let layout else { return 1 }
        let pitch = resolvedFont.lineHeight + resolvedFont.leading
        return layout.lines.count > 1 ? layout.lines.count : max(1, Int((layout.size.height / pitch).rounded()))
    }

    /// The text's height in a view `width` wide: the label height for the lines plus the insets.
    open func contentHeight(for width: CGFloat) -> CGFloat {
        let lines = lineCount(of: layout(width: containerWidth(for: width)))
        return resolvedFont.labelHeight(lines: lines, scale: UIScreen.main.scale) + textContainerInset.top + textContainerInset.bottom
    }

    /// The used width plus the insets (not the padding) by the height for the lines at the
    /// proposed width (uikit/textview/basic `fitted`: 90.5 × 57 for "Two lines of / text").
    override open func sizeThatFits(_ size: CGSize) -> CGSize {
        let scale = UIScreen.main.scale
        let proposed = size.width > 0 && size.width < CGFloat.greatestFiniteMagnitude ? size.width : bounds.width
        let layout = layout(width: containerWidth(for: proposed))
        let used = (layout?.size.width ?? 0).roundedUp(to: scale)
        let height = resolvedFont.labelHeight(lines: lineCount(of: layout), scale: scale)
        return CGSize(width: used + textContainerInset.left + textContainerInset.right,
                      height: height + textContainerInset.top + textContainerInset.bottom)
    }

    /// A scrolling text view has no intrinsic size; one that does not scroll is its content.
    override open var intrinsicContentSize: CGSize {
        guard !isScrollEnabled else { return CGSize(width: UIView.noIntrinsicMetric, height: UIView.noIntrinsicMetric) }
        return CGSize(width: UIView.noIntrinsicMetric, height: contentHeight(for: bounds.width))
    }

    override open func layoutSubviews() {
        super.layoutSubviews()
        let height = max(bounds.height, contentHeight(for: bounds.width))
        let size = CGSize(width: bounds.width, height: height)
        if contentSize != size { contentSize = size }
    }

    /// The rectangle the lines occupy at the top of the content: inside the insets and the padding.
    var textRect: CGRect {
        let width = containerWidth(for: bounds.width)
        let lines = lineCount(of: layout(width: width))
        return CGRect(x: textContainerInset.left + padding, y: textContainerInset.top, width: width,
                      height: resolvedFont.labelHeight(lines: lines, scale: UIScreen.main.scale))
    }

    /// The first baseline: the top inset plus the ascender, rounded up to the pixel (24.5 for
    /// 17 pt under the 8 pt inset).
    var firstBaseline: CGFloat { (textContainerInset.top + resolvedFont.ascender).roundedUp(to: UIScreen.main.scale) }

    override func textBaselines(in size: CGSize) -> (first: CGFloat, last: CGFloat) {
        let lines = lineCount(of: layout(width: containerWidth(for: size.width)))
        return (firstBaseline, firstBaseline + linePitch * CGFloat(lines - 1))
    }

    // MARK: Painting

    override func drawContent(into list: inout DisplayList, context: PaintContext, style: UIUserInterfaceStyle) {
        let rect = textRect
        guard let layout = layout(width: rect.width), !layout.lines.isEmpty else { return }
        let font = resolvedFont
        let pitch = linePitch
        let color = (textColor ?? .label).rgba(for: style)
        let displayFont = DisplayFont(font.resolved)
        let lines = visibleLineLimit.map { Array(layout.lines.prefix($0)) } ?? layout.lines
        for (index, line) in lines.enumerated() {
            let baseline = context.origin.y + firstBaseline + pitch * CGFloat(index)
            let inset: CGFloat
            switch textAlignment {
            case .center: inset = (rect.width - line.inkWidth) / 2
            case .right: inset = rect.width - line.inkWidth
            default: inset = 0
            }
            for fragment in line.fragments where !fragment.text.isEmpty {
                list.append(.drawText(fragment.text, displayFont, origin: CGPoint(x: context.origin.x + rect.minX + inset + fragment.x, y: baseline), color))
            }
        }
    }

    // MARK: Semantics

    override func decorateSemantics(_ node: inout SemanticsNode) {
        node.role = .textField
        let font = resolvedFont
        var info = TextInputInfo(text: text ?? "", placeholder: "", isSecure: false, textRect: convert(textRect, to: nil),
                                 font: DisplayFont(font.resolved), isEnabled: isEditable)
        info.isMultiline = true
        info.lineHeight = linePitch
        info.firstBaseline = firstBaseline - textContainerInset.top
        node.textInput = info
    }
}

/// A view the host types into: the text field and the text view.
@MainActor
protocol HostTextInput: UIView {
    func hostDidChange(_ newText: String)
    func hostDidSubmit()
}

extension UITextField: HostTextInput {}
