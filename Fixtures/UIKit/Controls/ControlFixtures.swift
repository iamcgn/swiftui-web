// UISwitch and UITextField (Docs/elements/UIKit/UISwitch.md, UITextField.md): sized to fit,
// on and off, rounded and plain fields with text and placeholders.
#if canImport(UIKit)
import UIKit
import UIKitFixtureKit

public enum ControlFixtures {
    public static let all = [basic, intrinsic]

    public static let basic = UIKitFixture("uikit/controls/basic", size: CGSize(width: 320, height: 300)) {
        let root = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 300))
        let off = UISwitch()
        off.sizeToFit()
        off.frame.origin = CGPoint(x: 16, y: 16)
        root.addSubview(off.probe("off"))
        let on = UISwitch()
        on.isOn = true
        on.sizeToFit()
        on.frame.origin = CGPoint(x: 96, y: 16)
        root.addSubview(on.probe("on"))
        let disabled = UISwitch()
        disabled.isOn = true
        disabled.isEnabled = false
        disabled.sizeToFit()
        disabled.frame.origin = CGPoint(x: 176, y: 16)
        root.addSubview(disabled.probe("disabledSwitch"))
        let rounded = UITextField()
        rounded.borderStyle = .roundedRect
        rounded.text = "Hello"
        rounded.sizeToFit()
        rounded.frame = CGRect(x: 16, y: 72, width: 250, height: rounded.frame.height)
        root.addSubview(rounded.probe("rounded"))
        let placeholder = UITextField()
        placeholder.borderStyle = .roundedRect
        placeholder.placeholder = "Placeholder"
        placeholder.sizeToFit()
        placeholder.frame = CGRect(x: 16, y: 120, width: 250, height: placeholder.frame.height)
        root.addSubview(placeholder.probe("placeholder"))
        let plain = UITextField()
        plain.text = "Plain field"
        plain.sizeToFit()
        plain.frame.origin = CGPoint(x: 16, y: 168)
        root.addSubview(plain.probe("plain"))
        let secure = UITextField()
        secure.borderStyle = .roundedRect
        secure.text = "secret"
        secure.isSecureTextEntry = true
        secure.sizeToFit()
        secure.frame = CGRect(x: 16, y: 208, width: 250, height: secure.frame.height)
        root.addSubview(secure.probe("secure"))
        return root
    }

    /// Each control's `intrinsicContentSize` and compressed `systemLayoutSizeFitting`, as frames
    /// (a metric the view does not have, `noIntrinsicMetric`, is shown as 1): what SwiftUI's
    /// representables size from (Docs/elements/Representable.md).
    public static let intrinsic = UIKitFixture("uikit/controls/intrinsic", size: CGSize(width: 320, height: 300)) {
        let root = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 300))
        func shown(_ size: CGSize) -> CGSize { CGSize(width: size.width < 0 ? 1 : size.width, height: size.height < 0 ? 1 : size.height) }
        var y: CGFloat = 8
        @MainActor func add(_ view: UIView, _ name: String) {
            view.frame = CGRect(origin: CGPoint(x: 8, y: y), size: shown(view.intrinsicContentSize))
            root.addSubview(view.probe(name))
            let fitting = UIView()
            fitting.backgroundColor = .systemTeal
            fitting.frame = CGRect(origin: CGPoint(x: 160, y: y), size: shown(view.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)))
            root.addSubview(fitting.probe(name + "Fitting"))
            // The alignment rect insets, as a frame: (left, top) origin, (right, bottom) size.
            let insets = view.alignmentRectInsets
            let shownInsets = UIView()
            shownInsets.frame = CGRect(x: 240 + insets.left, y: y + insets.top, width: insets.right, height: insets.bottom)
            root.addSubview(shownInsets.probe(name + "Insets"))
            y += max(view.frame.height, fitting.frame.height) + 8
        }
        let toggle = UISwitch()
        toggle.isOn = true
        add(toggle, "switch")
        let label = UILabel()
        label.text = "Hello"
        label.font = .systemFont(ofSize: 17)
        add(label, "label")
        let field = UITextField()
        field.borderStyle = .roundedRect
        field.text = "Hello"
        add(field, "field")
        let button = UIButton(type: .system)
        button.setTitle("Tap", for: .normal)
        add(button, "button")
        let plain = UIView()
        plain.backgroundColor = .systemBlue
        add(plain, "plain")
        return root
    }
}
#endif
