// UILabel (Docs/elements/UIKit/UILabel.md): text laid out by the scene's text engine at the
// font's UIKit line pitch, centred vertically in the bounds as UIKit does.

/// A view that displays one or more lines of informational text.
@MainActor
open class UILabel: UIView {
    open var text: String? { didSet { if text != oldValue { textDidChange() } } }
    open var font: UIFont = .systemFont(ofSize: 17) { didSet { if font != oldValue { textDidChange() } } }
    open var textColor: UIColor = .label { didSet { setNeedsDisplay() } }
    open var textAlignment: NSTextAlignment = .natural { didSet { setNeedsDisplay() } }
    open var lineBreakMode: NSLineBreakMode = .byTruncatingTail { didSet { textDidChange() } }
    /// 0 lays out as many lines as the text needs.
    open var numberOfLines = 1 { didSet { textDidChange() } }
    open var adjustsFontSizeToFitWidth = false
    open var minimumScaleFactor: CGFloat = 0
    open var allowsDefaultTighteningForTruncation = false
    open var isEnabled = true { didSet { setNeedsDisplay() } }
    open var isHighlighted = false
    open var highlightedTextColor: UIColor?
    open var shadowColor: UIColor?
    open var shadowOffset = CGSize(width: 0, height: -1)
    open var adjustsFontForContentSizeCategory = false
    open var showsExpansionTextWhenTruncated = false
    /// The width the intrinsic height wraps at (0: one line).
    open var preferredMaxLayoutWidth: CGFloat = 0 { didSet { invalidateIntrinsicContentSize() } }

    public override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isAccessibilityElement = true
        accessibilityTraits = .staticText
        backgroundColor = nil
    }

    private func textDidChange() {
        invalidateIntrinsicContentSize()
        setNeedsDisplay()
    }

    override open var accessibilityLabel: String? {
        get { super.accessibilityLabel ?? text }
        set { super.accessibilityLabel = newValue }
    }

    // MARK: Layout

    /// The text engine's layout of the text within `width` (nil: unbounded).
    func layout(width: CGFloat?) -> TextLayout? {
        guard let text, !text.isEmpty else { return nil }
        let engine = UIKitScene.shared.textEngine
        let limit = numberOfLines > 0 ? numberOfLines : nil
        let truncation: TextTruncationMode
        switch lineBreakMode {
        case .byTruncatingHead: truncation = .head
        case .byTruncatingMiddle: truncation = .middle
        default: truncation = .tail
        }
        let options = TextLayoutOptions(lineLimit: limit, truncationMode: truncation)
        let wrap = width.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        return engine.layout([StyledRun(text, font: font.resolved)], options: options, width: wrap)
    }

    /// The text's size: the layout's width (rounded up to the pixel) and lines × the font's line
    /// height, as UILabel reports it.
    func textSize(fitting width: CGFloat?) -> CGSize {
        guard let layout = layout(width: width) else { return CGSize(width: 0, height: font.lineHeight.roundedUp(to: UIScreen.main.scale)) }
        let lines = max(1, layout.lines.count)
        let height = (font.lineHeight * CGFloat(lines)).roundedUp(to: UIScreen.main.scale)
        return CGSize(width: layout.size.width.roundedUp(to: UIScreen.main.scale), height: height)
    }

    override open func sizeThatFits(_ size: CGSize) -> CGSize {
        let width: CGFloat? = size.width > 0 && size.width < CGFloat.greatestFiniteMagnitude ? size.width : nil
        // A one-line label reports its whole width; a wrapping one fits the proposal.
        if numberOfLines == 1 { return textSize(fitting: nil) }
        let fitted = textSize(fitting: width)
        return CGSize(width: width.map { min($0, fitted.width) } ?? fitted.width, height: fitted.height)
    }

    override open var intrinsicContentSize: CGSize {
        textSize(fitting: preferredMaxLayoutWidth > 0 ? preferredMaxLayoutWidth : nil)
    }

    open func textRect(forBounds bounds: CGRect, limitedToNumberOfLines numberOfLines: Int) -> CGRect {
        let size = textSize(fitting: bounds.width)
        return CGRect(x: bounds.minX, y: bounds.minY + ((bounds.height - size.height) / 2).rounded(), width: min(size.width, bounds.width), height: size.height)
    }

    // MARK: Painting

    override func drawContent(into list: inout DisplayList, context: PaintContext, style: UIUserInterfaceStyle) {
        guard let layout = layout(width: bounds.width) else { return }
        let lines = layout.lines
        guard !lines.isEmpty else { return }
        let lineHeight = font.lineHeight
        let textHeight = lineHeight * CGFloat(lines.count)
        // The block is centred vertically; each line's baseline sits at the ascender.
        let top = (bounds.height - textHeight) / 2
        let color = (isEnabled ? textColor : .tertiaryLabel).rgba(for: style)
        let displayFont = DisplayFont(font.resolved)
        let alignment = textAlignment
        for (index, line) in lines.enumerated() {
            let baseline = context.origin.y + top + lineHeight * CGFloat(index) + font.ascender
            let inset: CGFloat
            switch alignment {
            case .center: inset = (bounds.width - line.inkWidth) / 2
            case .right: inset = bounds.width - line.inkWidth
            default: inset = 0
            }
            for fragment in line.fragments {
                list.append(.drawText(fragment.text, displayFont, origin: CGPoint(x: context.origin.x + inset + fragment.x, y: baseline), color))
            }
        }
    }
}

extension CGFloat {
    /// Rounded up to the pixel grid of `scale` pixels per point.
    func roundedUp(to scale: CGFloat) -> CGFloat { (self * scale).rounded(.up) / scale }
}
