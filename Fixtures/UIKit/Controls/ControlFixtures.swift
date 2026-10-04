// UISwitch and UITextField (Docs/elements/UIKit/UISwitch.md, UITextField.md): sized to fit,
// on and off, rounded and plain fields with text and placeholders.
#if canImport(UIKit)
import UIKit
import UIKitFixtureKit

/// Text field looks (uk-textfield): the line and bezel borders, the clear button (shown while
/// editing after the "edit" step, and unless editing before it), left and right views, an
/// attributed placeholder, and a rounded field with text for its pixels.
public enum TextFieldFixtures {
    public static let all = [looks]

    @MainActor
    public final class LooksModel {
        public let editing = UITextField()
        public let unless = UITextField()
        public let centered = UITextField()
        public init() {}
    }

    public static let looks = UIKitFixture("uikit/textfield/looks", size: CGSize(width: 320, height: 340), model: { LooksModel() }, steps: [
        // The simulator only paints clear buttons once a field has been edited: the modes that
        // show one outside editing are set in the step, so the first frame shows none.
        UIKitFixtureStep("edit") { model in
            model.unless.clearButtonMode = .unlessEditing
            model.centered.clearButtonMode = .always
            model.editing.becomeFirstResponder()
        },
    ]) { model in
        let root = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 340))
        @MainActor func add(_ field: UITextField, y: CGFloat, width: CGFloat? = nil, id: String) {
            field.sizeToFit()
            field.frame.origin = CGPoint(x: 16, y: y)
            if let width { field.frame.size.width = width }
            root.addSubview(field.probe(id))
        }
        let line = UITextField()
        line.borderStyle = .line
        line.text = "Line border"
        add(line, y: 16, id: "line")
        let bezel = UITextField()
        bezel.borderStyle = .bezel
        bezel.text = "Bezel border"
        add(bezel, y: 60, id: "bezel")
        let clear = model.editing
        clear.borderStyle = .roundedRect
        clear.text = "Clear"
        clear.clearButtonMode = .whileEditing
        add(clear, y: 104, width: 160, id: "clear")
        let unless = model.unless
        unless.borderStyle = .roundedRect
        unless.text = "Unless"
        add(unless, y: 104, width: 120, id: "unless")
        unless.frame.origin.x = 184
        let sides = UITextField()
        sides.borderStyle = .roundedRect
        sides.text = "Views"
        let left = UIView(frame: CGRect(x: 0, y: 0, width: 20, height: 20))
        left.backgroundColor = .systemBlue
        sides.leftView = left
        sides.leftViewMode = .always
        let right = UIView(frame: CGRect(x: 0, y: 0, width: 24, height: 12))
        right.backgroundColor = .systemRed
        sides.rightView = right
        sides.rightViewMode = .always
        add(sides, y: 148, width: 200, id: "sides")
        _ = left.probe("leftView")
        _ = right.probe("rightView")
        let attributed = UITextField()
        attributed.borderStyle = .roundedRect
        attributed.attributedPlaceholder = NSAttributedString(string: "Attributed", attributes: [.foregroundColor: UIColor.systemRed, .font: UIFont.systemFont(ofSize: 15)])
        add(attributed, y: 192, width: 160, id: "attributed")
        let rounded = UITextField()
        rounded.borderStyle = .roundedRect
        rounded.text = "Rounded text"
        add(rounded, y: 236, width: 200, id: "rounded")
        let plain = UITextField()
        plain.text = "Plain text"
        add(plain, y: 280, width: 160, id: "plain")
        let centered = model.centered
        centered.borderStyle = .roundedRect
        centered.text = "Center"
        centered.textAlignment = .center
        add(centered, y: 280, width: 120, id: "centered")
        centered.frame.origin.x = 184
        return root
    }
}

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
