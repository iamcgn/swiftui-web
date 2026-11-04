// UIColorWell: a 28 pt round swatch of the selected colour (a light grey disc when none is
// selected). Tapping it does not open a colour picker yet; apps set `selectedColor` and read it
// back, and `.valueChanged` fires when they do.
import WebFoundation   // NSCoder, for init?(coder:)

/// A control that displays a color picker.
@preconcurrency @MainActor
open class UIColorWell: UIControl {
    /// No archive to decode on the web: nil, as for an archive this class cannot read.
    public required init?(coder: NSCoder) { return nil }

    open var title: String?
    open var supportsAlpha = true
    open var selectedColor: UIColor? {
        didSet {
            setNeedsDisplay()
            sendActions(for: .valueChanged)
        }
    }

    static let size = CGSize(width: 28, height: 28)

    public override init(frame: CGRect) {
        super.init(frame: frame)
        isAccessibilityElement = true
        setContentHuggingPriority(.defaultHigh, for: .horizontal)
        setContentHuggingPriority(.defaultHigh, for: .vertical)
    }

    override open func sizeThatFits(_ size: CGSize) -> CGSize { Self.size }
    override open var intrinsicContentSize: CGSize { Self.size }

    override func drawContent(into list: inout DisplayList, context: PaintContext, style: UIUserInterfaceStyle) {
        let side = min(bounds.width, bounds.height, Self.size.width)
        guard side > 0 else { return }
        let origin = CGPoint(x: (bounds.width - side) / 2, y: (bounds.height - side) / 2)
        let disc = context.absoluteRect(CGRect(origin: origin, size: CGSize(width: side, height: side)))
        let empty = UIColor(light: RGBA(r: 120, g: 120, b: 128, a: 0.2), dark: RGBA(r: 120, g: 120, b: 128, a: 0.36))
        list.append(.fillRRect(disc, cornerRadius: side / 2, (selectedColor ?? empty).rgba(for: style)))
    }

    override func decorateSemantics(_ node: inout SemanticsNode) {
        if node.label.isEmpty { node.label = title ?? "Color" }
    }
}
