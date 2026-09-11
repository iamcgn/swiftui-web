// UISwitch (Docs/elements/UIKit/UISwitch.md): the 51 × 31 switch with a 27 pt white knob 2 pt
// in, green (or the tint) when on, the system fill when off (the geometry SwiftUIWeb's iOS
// toggle paints).

/// A control that offers a binary choice, such as on/off.
@MainActor
open class UISwitch: UIControl {
    public enum Style: Int, Sendable { case automatic = 0, checkbox, sliding }

    open var isOn = false { didSet { if isOn != oldValue { setNeedsDisplay() } } }
    open var onTintColor: UIColor? { didSet { setNeedsDisplay() } }
    open var thumbTintColor: UIColor? { didSet { setNeedsDisplay() } }
    open var preferredStyle: Style = .automatic
    open var style: Style { .sliding }
    open var title: String?

    public override init(frame: CGRect) {
        super.init(frame: CGRect(origin: frame.origin, size: CGSize(width: 68, height: 30)))
        isAccessibilityElement = true
        // A switch hugs its content on both axes (uikit/controls/intrinsic, ios/representable/controls).
        setContentHuggingPriority(.defaultHigh, for: .horizontal)
        setContentHuggingPriority(.defaultHigh, for: .vertical)
    }

    open func setOn(_ on: Bool, animated: Bool) { isOn = on }

    /// The iOS 26 switch is 68 × 30 (`sizeToFit` and the intrinsic size alike: uikit/controls/basic,
    /// uikit/controls/intrinsic) with a 2 pt alignment inset on the right, so layout aligns a
    /// 66 × 30 rectangle at the frame's origin (ios/representable/controls).
    override open func sizeThatFits(_ size: CGSize) -> CGSize { CGSize(width: 68, height: 30) }
    override open var intrinsicContentSize: CGSize { CGSize(width: 68, height: 30) }
    override open var alignmentRectInsets: UIEdgeInsets { UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 2) }

    override open func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        let wasTracking = isTracking
        super.touchesEnded(touches, with: event)
        if wasTracking, isEnabled, let touch = touches.first, point(inside: touch.location(in: self), with: event) {
            isOn.toggle()
            sendActions(for: .valueChanged)
        }
    }

    /// The iOS 26 switch drawn to the bounds: a capsule track, a white pill knob 2.5 in whose
    /// proportions are the 68 × 30 switch's (a 38 × 25 knob; the track scales the knob with its
    /// height), green (or the tint) when on, the system fill when off, at half strength when
    /// disabled.
    override func drawContent(into list: inout DisplayList, context: PaintContext, style: UIUserInterfaceStyle) {
        let track = context.absoluteRect(CGRect(origin: .zero, size: bounds.size))
        let dim = isEnabled ? 1.0 : 0.5
        let fill = isOn ? (onTintColor ?? .systemGreen).rgba(for: style).multiplyingAlpha(by: dim)
            : (style == .dark ? RGBA(r: 120, g: 120, b: 128, a: 0.32) : RGBA(r: 120, g: 120, b: 128, a: 0.16)).multiplyingAlpha(by: dim)
        list.append(.fillRRect(track, cornerRadius: track.height / 2, fill))
        let inset: CGFloat = 2.5
        let knobHeight = track.height - 2 * inset
        let knobWidth = min(track.width - 2 * inset, knobHeight * 38 / 25)
        let knob = CGRect(x: isOn ? track.maxX - inset - knobWidth : track.minX + inset, y: track.minY + inset, width: knobWidth, height: knobHeight)
        list.append(.beginShadow(RGBA(red: 0, green: 0, blue: 0, alpha: 0.15 * dim), radius: 4, offset: CGSize(width: 0, height: 3)))
        list.append(.fillRRect(knob, cornerRadius: knobHeight / 2, (thumbTintColor ?? .white).rgba(for: style)))
        list.append(.endGroup)
    }

    override func decorateSemantics(_ node: inout SemanticsNode) {
        node.role = .switch
        node.isOn = isOn
    }

    override func accessibilityActivate() {
        guard isEnabled else { return }
        isOn.toggle()
        sendActions(for: .valueChanged)
    }
}
