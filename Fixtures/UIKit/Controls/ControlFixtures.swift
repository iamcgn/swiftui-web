// UISwitch and UITextField (Docs/elements/UIKit/UISwitch.md, UITextField.md): sized to fit,
// on and off, rounded and plain fields with text and placeholders.
#if canImport(UIKit)
import UIKit
import UIKitFixtureKit

public enum ControlFixtures {
    public static let all = [basic]

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
}
#endif
