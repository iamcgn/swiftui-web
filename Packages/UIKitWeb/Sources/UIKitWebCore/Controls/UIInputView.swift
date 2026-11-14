// Input views (Docs/elements/UIKit/UITextField.md, "Input views"): `UIInputView`, a view with
// the keyboard's look for a text field's accessory (KeyboardToolbar's toolbar above Runestone's
// editor in GistHub), `UIInputViewAudioFeedback`, and the responder's `inputView` and
// `inputAccessoryView`. While a responder with an accessory is first responder its window
// shows the accessory along the bottom, above the on-screen keyboard when the host reports
// one (`UIKitScene.keyboardFrame`) and above the home indicator when it does not, as UIKit
// shows it with a hardware keyboard. The web has no system keyboard to replace, so a custom
// `inputView` is kept and returned but not shown.
import WebFoundation   // NSCoder, for init?(coder:)

/// A view whose background matches the keyboard's, for an input view or accessory.
@preconcurrency @MainActor
open class UIInputView: UIView {
    public enum Style: Int, Sendable {
        /// No background of its own.
        case `default` = 0
        /// The keyboard's background: light gray, or dark gray in the dark appearance.
        case keyboard = 1
    }

    open var inputViewStyle: Style { style }
    private let style: Style
    /// Whether the view sizes itself with Auto Layout instead of its frame's height.
    open var allowsSelfSizing = false

    public init(frame: CGRect, inputViewStyle: Style) {
        style = inputViewStyle
        super.init(frame: frame)
        if inputViewStyle == .keyboard { backgroundColor = Self.keyboardBackground }
    }

    public override init(frame: CGRect) {
        style = .default
        super.init(frame: frame)
    }

    public required init?(coder: NSCoder) {
        style = .default
        super.init(coder: coder)
    }

    /// The keyboard's background (iOS 17's: 209/212/217 light, 43/43/43 dark).
    static let keyboardBackground = UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(red: 43 / 255, green: 43 / 255, blue: 43 / 255, alpha: 1)
            : UIColor(red: 209 / 255, green: 212 / 255, blue: 217 / 255, alpha: 1)
    }
}

/// An input view that plays the keyboard's click when `UIDevice.current.playInputClick()` is
/// called while it shows (the web plays none).
@preconcurrency @MainActor
public protocol UIInputViewAudioFeedback: AnyObject {
    var enableInputClicksWhenVisible: Bool { get }
}

extension UIInputViewAudioFeedback {
    public var enableInputClicksWhenVisible: Bool { false }
}

extension UIKitScene {
    /// Shows the first responder's input accessory along the bottom of its window, and takes
    /// down the one shown before.
    func updateInputAccessory() {
        let accessory = firstResponder?.inputAccessoryView
        if let docked = dockedInputAccessory, docked !== accessory {
            if docked.superview is UIWindow { docked.removeFromSuperview() }
            dockedInputAccessory = nil
        }
        guard let accessory,
              let window = (firstResponder as? UIView)?.window ?? windows.first(where: { $0.isKeyWindow }) ?? windows.last else { return }
        var height = accessory.frame.height
        if height <= 0 { height = max(accessory.intrinsicContentSize.height, 0) }
        if height <= 0 { height = accessory.systemLayoutSizeFitting(CGSize(width: window.bounds.width, height: 0)).height }
        let bottom = keyboardFrame.map { min($0.minY, window.bounds.maxY) } ?? window.bounds.maxY - window.safeAreaInsets.bottom
        accessory.frame = CGRect(x: 0, y: bottom - height, width: window.bounds.width, height: height)
        if accessory.superview !== window { window.addSubview(accessory) } else { window.bringSubviewToFront(accessory) }
        dockedInputAccessory = accessory
    }
}
