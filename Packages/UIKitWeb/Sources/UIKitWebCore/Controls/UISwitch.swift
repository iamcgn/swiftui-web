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
        super.init(frame: CGRect(origin: frame.origin, size: CGSize(width: 51, height: 31)))
        isAccessibilityElement = true
    }

    open func setOn(_ on: Bool, animated: Bool) { isOn = on }

    override open func sizeThatFits(_ size: CGSize) -> CGSize { CGSize(width: 51, height: 31) }
    override open var intrinsicContentSize: CGSize { CGSize(width: 51, height: 31) }

    override open func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        let wasTracking = isTracking
        super.touchesEnded(touches, with: event)
        if wasTracking, isEnabled, let touch = touches.first, point(inside: touch.location(in: self), with: event) {
            isOn.toggle()
            sendActions(for: .valueChanged)
        }
    }

    override func drawContent(into list: inout DisplayList, context: PaintContext, style: UIUserInterfaceStyle) {
        let track = context.absoluteRect(CGRect(x: 0, y: (bounds.height - 31) / 2, width: 51, height: 31))
        let dim = isEnabled ? 1.0 : 0.5
        let fill = isOn ? (onTintColor ?? .systemGreen).rgba(for: style).multiplyingAlpha(by: dim)
            : (style == .dark ? RGBA(r: 120, g: 120, b: 128, a: 0.32) : RGBA(r: 120, g: 120, b: 128, a: 0.16)).multiplyingAlpha(by: dim)
        list.append(.fillRRect(track, cornerRadius: track.height / 2, fill))
        let knobSize: CGFloat = 27
        let knob = CGRect(x: isOn ? track.maxX - 2 - knobSize : track.minX + 2, y: track.minY + 2, width: knobSize, height: knobSize)
        list.append(.beginShadow(RGBA(red: 0, green: 0, blue: 0, alpha: 0.15 * dim), radius: 4, offset: CGSize(width: 0, height: 3)))
        list.append(.fillRRect(knob, cornerRadius: knobSize / 2, (thumbTintColor ?? .white).rgba(for: style)))
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
