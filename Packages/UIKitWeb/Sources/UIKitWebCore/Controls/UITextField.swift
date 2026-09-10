// UITextField (Docs/elements/UIKit/UITextField.md): the rounded-rect field (34 pt, a 0.5 pt
// border at 20 % black inside 4 pt corners, text 7.5 in, the geometry measured on
// `ios/textfield/basic`); typing goes through the host's input element (`TextInputInfo`).

/// The methods a text field's delegate implements.
@MainActor
public protocol UITextFieldDelegate: AnyObject {
    func textFieldShouldBeginEditing(_ textField: UITextField) -> Bool
    func textFieldDidBeginEditing(_ textField: UITextField)
    func textFieldShouldEndEditing(_ textField: UITextField) -> Bool
    func textFieldDidEndEditing(_ textField: UITextField)
    func textFieldDidChangeSelection(_ textField: UITextField)
    func textFieldShouldClear(_ textField: UITextField) -> Bool
    func textFieldShouldReturn(_ textField: UITextField) -> Bool
}

extension UITextFieldDelegate {
    public func textFieldShouldBeginEditing(_ textField: UITextField) -> Bool { true }
    public func textFieldDidBeginEditing(_ textField: UITextField) {}
    public func textFieldShouldEndEditing(_ textField: UITextField) -> Bool { true }
    public func textFieldDidEndEditing(_ textField: UITextField) {}
    public func textFieldDidChangeSelection(_ textField: UITextField) {}
    public func textFieldShouldClear(_ textField: UITextField) -> Bool { true }
    public func textFieldShouldReturn(_ textField: UITextField) -> Bool { true }
}

/// An object that displays an editable text area in your interface.
@MainActor
open class UITextField: UIControl {
    public enum BorderStyle: Int, Sendable { case none = 0, line, bezel, roundedRect }
    public enum ViewMode: Int, Sendable { case never = 0, whileEditing, unlessEditing, always }

    open var text: String? { didSet { if text != oldValue { setNeedsDisplay() } } }
    open var placeholder: String? { didSet { setNeedsDisplay() } }
    open var font: UIFont? = .systemFont(ofSize: 17) { didSet { invalidateIntrinsicContentSize(); setNeedsDisplay() } }
    open var textColor: UIColor? = .label { didSet { setNeedsDisplay() } }
    open var textAlignment: NSTextAlignment = .natural { didSet { setNeedsDisplay() } }
    open var borderStyle: BorderStyle = .none { didSet { invalidateIntrinsicContentSize(); setNeedsDisplay() } }
    open var isSecureTextEntry = false { didSet { setNeedsDisplay() } }
    open var clearButtonMode: ViewMode = .never
    open var clearsOnBeginEditing = false
    open var adjustsFontSizeToFitWidth = false
    open var minimumFontSize: CGFloat = 0
    open var keyboardType: UIKeyboardType = .default
    open var returnKeyType: UIReturnKeyType = .default
    open var autocapitalizationType: UITextAutocapitalizationType = .sentences
    open var autocorrectionType: UITextAutocorrectionType = .default
    open var spellCheckingType: UITextSpellCheckingType = .default
    open var enablesReturnKeyAutomatically = false
    open var textContentType: String?
    open weak var delegate: (any UITextFieldDelegate)?
    open var leftView: UIView?
    open var rightView: UIView?
    open var leftViewMode: ViewMode = .never
    open var rightViewMode: ViewMode = .never

    public override init(frame: CGRect) {
        super.init(frame: frame)
        isAccessibilityElement = true
    }

    open var isEditing: Bool { isFirstResponder }
    override open var canBecomeFirstResponder: Bool { isEnabled }

    @discardableResult
    override open func becomeFirstResponder() -> Bool {
        guard !isFirstResponder else { return true }
        guard delegate?.textFieldShouldBeginEditing(self) ?? true, super.becomeFirstResponder() else { return false }
        if clearsOnBeginEditing { text = nil }
        delegate?.textFieldDidBeginEditing(self)
        sendActions(for: .editingDidBegin)
        return true
    }

    @discardableResult
    override open func resignFirstResponder() -> Bool {
        guard isFirstResponder else { return true }
        guard delegate?.textFieldShouldEndEditing(self) ?? true, super.resignFirstResponder() else { return false }
        delegate?.textFieldDidEndEditing(self)
        sendActions(for: .editingDidEnd)
        return true
    }

    override open func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        if isEnabled, let touch = touches.first, point(inside: touch.location(in: self), with: event) { becomeFirstResponder() }
    }

    /// The host's input element changed the text.
    func hostDidChange(_ newText: String) {
        text = newText
        sendActions(for: .editingChanged)
        delegate?.textFieldDidChangeSelection(self)
    }

    /// Return was pressed in the host's input element.
    func hostDidSubmit() {
        if delegate?.textFieldShouldReturn(self) ?? true {
            sendActions(for: .editingDidEndOnExit)
        }
    }

    // MARK: Geometry (Docs/elements/iOS.md: the 34 pt rounded field)

    private var bordered: Bool { borderStyle != .none }
    private var horizontalInset: CGFloat { bordered ? 7 : 0 }
    private var resolvedFont: UIFont { font ?? .systemFont(ofSize: 17) }

    override open func sizeThatFits(_ size: CGSize) -> CGSize {
        let f = resolvedFont
        // A plain field is its ascender-plus-descender on the pixel grid, plus one (21.5 at 17 pt; measured once).
        let height: CGFloat = bordered ? 34 : (f.ascender - f.descender).roundedUp(to: UIScreen.main.scale) + 1
        let content = text?.isEmpty == false ? text! : (placeholder ?? "")
        let layout = UIKitScene.shared.textEngine.layout([StyledRun(content, font: f.resolved)], options: .default, width: nil)
        return CGSize(width: layout.size.width.roundedUp(to: UIScreen.main.scale) + 2 * horizontalInset, height: height)
    }

    override open var intrinsicContentSize: CGSize {
        let fitted = sizeThatFits(CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude))
        return CGSize(width: UIView.noIntrinsicMetric, height: fitted.height)
    }

    open func textRect(forBounds bounds: CGRect) -> CGRect {
        let line = resolvedFont.lineHeight
        return CGRect(x: bounds.minX + horizontalInset, y: bounds.minY + ((bounds.height - line) / 2).rounded(),
                      width: bounds.width - 2 * horizontalInset, height: line.roundedUp(to: UIScreen.main.scale))
    }

    open func editingRect(forBounds bounds: CGRect) -> CGRect { textRect(forBounds: bounds) }
    open func placeholderRect(forBounds bounds: CGRect) -> CGRect { textRect(forBounds: bounds) }
    open func borderRect(forBounds bounds: CGRect) -> CGRect { bounds }

    // MARK: Painting

    override func drawContent(into list: inout DisplayList, context: PaintContext, style: UIUserInterfaceStyle) {
        let rect = context.absoluteRect(CGRect(origin: .zero, size: bounds.size))
        if bordered {
            let fill = UIColor.systemBackground.rgba(for: style)
            list.append(.fillRRect(rect, cornerRadius: borderStyle == .roundedRect ? 4 : 0, fill))
            let border = rect.insetBy(dx: 0.25, dy: 0.25)
            list.append(.strokePath(Path(roundedRect: border, cornerRadius: borderStyle == .roundedRect ? 4 : 0, style: .circular),
                                    style: StrokeStyle(lineWidth: 0.5), RGBA(red: 0, green: 0, blue: 0, alpha: 0.2)))
        }
        let f = resolvedFont
        let textRect = self.textRect(forBounds: bounds)
        let showsPlaceholder = text?.isEmpty != false
        let string = showsPlaceholder ? (placeholder ?? "") : (isSecureTextEntry ? String(repeating: "•", count: text!.count) : text!)
        guard !string.isEmpty else { return }
        let layout = UIKitScene.shared.textEngine.layout([StyledRun(string, font: f.resolved)], options: TextLayoutOptions(lineLimit: 1), width: textRect.width)
        guard let line = layout.lines.first else { return }
        let color = (showsPlaceholder ? UIColor.placeholderText : (isEnabled ? (textColor ?? .label) : .tertiaryLabel)).rgba(for: style)
        let inset: CGFloat
        switch textAlignment {
        case .center: inset = (textRect.width - line.inkWidth) / 2
        case .right: inset = textRect.width - line.inkWidth
        default: inset = 0
        }
        let baseline = context.origin.y + textRect.minY + f.ascender
        for fragment in line.fragments {
            list.append(.drawText(fragment.text, DisplayFont(f.resolved), origin: CGPoint(x: context.origin.x + textRect.minX + inset + fragment.x, y: baseline), color))
        }
    }

    // MARK: Semantics

    override func decorateSemantics(_ node: inout SemanticsNode) {
        node.role = .textField
        let windowRect = convert(textRect(forBounds: bounds), to: nil)
        node.textInput = TextInputInfo(text: text ?? "", placeholder: placeholder ?? "", isSecure: isSecureTextEntry,
                                       textRect: windowRect, font: DisplayFont(resolvedFont.resolved), isEnabled: isEnabled)
        if node.label.isEmpty { node.label = placeholder ?? "" }
    }
}

public enum UIKeyboardType: Int, Sendable {
    case `default` = 0, asciiCapable, numbersAndPunctuation, URL, numberPad, phonePad, namePhonePad, emailAddress, decimalPad, twitter, webSearch, asciiCapableNumberPad
}

public enum UIReturnKeyType: Int, Sendable {
    case `default` = 0, go, google, join, next, route, search, send, yahoo, done, emergencyCall, `continue`
}

public enum UITextAutocapitalizationType: Int, Sendable { case none = 0, words, sentences, allCharacters }
public enum UITextAutocorrectionType: Int, Sendable { case `default` = 0, no, yes }
public enum UITextSpellCheckingType: Int, Sendable { case `default` = 0, no, yes }
