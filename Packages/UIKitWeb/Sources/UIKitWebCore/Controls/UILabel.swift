// UILabel (Docs/elements/UIKit/UILabel.md): text laid out by the scene's text engine; the block
// is the font's line height per line plus its leading between lines, rounded up to the pixel
// (UIFont.labelHeight), centred vertically in the bounds as UIKit does.

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
        // UIKit's label priorities: hugging 251 on both axes (a hair above the default 250).
        setContentHuggingPriority(UILayoutPriority(251), for: .horizontal)
        setContentHuggingPriority(UILayoutPriority(251), for: .vertical)
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

    /// The text's size: the layout's width (rounded up to the pixel) and the font's height for
    /// the lines, as UILabel reports it. The recorded engine answers a wrapped request as one
    /// line of the recorded height, so a single-line answer's line count comes from that height
    /// in the font's pitch.
    func textSize(fitting width: CGFloat?) -> CGSize {
        let scale = UIScreen.main.scale
        guard let layout = layout(width: width) else { return CGSize(width: 0, height: font.labelHeight(lines: 1, scale: scale)) }
        let pitch = font.lineHeight + font.leading
        let lines = layout.lines.count > 1 ? layout.lines.count : max(1, Int((layout.size.height / pitch).rounded()))
        return CGSize(width: layout.size.width.roundedUp(to: scale), height: font.labelHeight(lines: lines, scale: scale))
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

    /// The text's rectangle in `bounds`: one line measures unbounded (it truncates rather than
    /// wraps), the block is centred vertically on the point grid.
    open func textRect(forBounds bounds: CGRect, limitedToNumberOfLines numberOfLines: Int) -> CGRect {
        let size = textSize(fitting: numberOfLines == 1 ? nil : bounds.width)
        return CGRect(x: bounds.minX, y: bounds.minY + ((bounds.height - size.height) / 2).rounded(), width: min(size.width, bounds.width), height: size.height)
    }

    /// The baselines of the text block in `size`: the text rect's top (rounded, as
    /// `textRect(forBounds:)` places it) plus the ascender rounded to the pixel, per line
    /// (`uikit/autolayout/baseline`: 10.5, 12.5, 16, 19, 26.5 and 32.5 for the 11, 13, 17, 20,
    /// 28 and 34 pt system fonts' ascenders 10.47, 12.38, 16.19, 19.04, 26.66 and 32.37).
    override func textBaselines(in size: CGSize) -> (first: CGFloat, last: CGFloat) {
        guard let layout = layout(width: numberOfLines == 1 ? nil : size.width), !layout.lines.isEmpty else { return (0, size.height) }
        let pitch = font.lineHeight + font.leading
        let lines = CGFloat(layout.lines.count)
        let top = textRect(forBounds: CGRect(origin: .zero, size: size), limitedToNumberOfLines: numberOfLines).minY
        let scale = UIScreen.main.scale
        let first = top + (font.ascender * scale).rounded() / scale
        return (first, first + pitch * (lines - 1))
    }

    // MARK: Painting

    override func drawContent(into list: inout DisplayList, context: PaintContext, style: UIUserInterfaceStyle) {
        guard let layout = layout(width: bounds.width) else { return }
        let lines = layout.lines
        guard !lines.isEmpty else { return }
        let pitch = font.lineHeight + font.leading
        let textHeight = font.lineHeight * CGFloat(lines.count) + font.leading * CGFloat(lines.count - 1)
        // The block is centred vertically; each line's baseline sits at the ascender.
        let top = (bounds.height - textHeight) / 2
        let color = (isEnabled ? textColor : .tertiaryLabel).rgba(for: style)
        let displayFont = DisplayFont(font.resolved)
        let alignment = textAlignment
        for (index, line) in lines.enumerated() {
            let baseline = context.origin.y + top + pitch * CGFloat(index) + font.ascender
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
