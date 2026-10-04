// UITextField (Docs/elements/UIKit/UITextField.md): the rounded-rect field (34 pt, a 0.5 pt
// border at 20 % black inside 4 pt corners, text 7 in), the line (30 pt, 1 pt label-coloured,
// text 2 in) and bezel (32 pt, 1 pt black 50 % with an inner 1 pt 33 % line on top and left,
// text 7 in and 1.5 down) borders, the clear button (17 pt `xmark.circle.fill` at 80 % white
// centred 15 from the right edge), left and right views flush to the edges, all measured on
// `uikit/textfield/looks`; typing goes through the host's input element (`TextInputInfo`).

#if !os(WASI)
import Foundation
#endif

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
    /// A placeholder with its own font and colour (its first run's; the string is the placeholder).
    open var attributedPlaceholder: NSAttributedString? {
        didSet {
            placeholder = attributedPlaceholder?.string
            setNeedsDisplay()
        }
    }
    /// The text as an attributed string (one font and colour: the field's).
    open var attributedText: NSAttributedString? {
        get { text.map { NSAttributedString(string: $0) } }
        set { text = newValue?.string }
    }
    open var font: UIFont? = .systemFont(ofSize: 17) { didSet { invalidateIntrinsicContentSize(); setNeedsDisplay() } }
    open var textColor: UIColor? = .label { didSet { setNeedsDisplay() } }
    open var textAlignment: NSTextAlignment = .natural { didSet { setNeedsDisplay() } }
    open var borderStyle: BorderStyle = .none { didSet { invalidateIntrinsicContentSize(); setNeedsDisplay() } }
    open var isSecureTextEntry = false { didSet { setNeedsDisplay() } }
    open var clearButtonMode: ViewMode = .never { didSet { setNeedsDisplay() } }
    open var clearsOnBeginEditing = false
    open var adjustsFontSizeToFitWidth = false
    open var minimumFontSize: CGFloat = 0
    open var keyboardType: UIKeyboardType = .default
    open var returnKeyType: UIReturnKeyType = .default
    open var autocapitalizationType: UITextAutocapitalizationType = .sentences
    open var autocorrectionType: UITextAutocorrectionType = .default
    open var spellCheckingType: UITextSpellCheckingType = .default
    open var enablesReturnKeyAutomatically = false
    open var textContentType: UITextContentType?
    open weak var delegate: (any UITextFieldDelegate)?
    /// The side views are subviews of the field, laid out flush to its edges and centred
    /// vertically; a mode says when they show.
    open var leftView: UIView? { didSet { replaceSideView(oldValue, with: leftView) } }
    open var rightView: UIView? { didSet { replaceSideView(oldValue, with: rightView) } }
    open var leftViewMode: ViewMode = .never { didSet { setNeedsLayout() } }
    open var rightViewMode: ViewMode = .never { didSet { setNeedsLayout() } }

    private func replaceSideView(_ old: UIView?, with new: UIView?) {
        if old !== new { old?.removeFromSuperview() }
        if let new, new.superview !== self { addSubview(new) }
        setNeedsLayout()
        setNeedsDisplay()
    }
    /// The placeholder's colour (a search field draws it as the secondary label).
    var placeholderColor: UIColor = .placeholderText

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
        setNeedsLayout()
        setNeedsDisplay()
        delegate?.textFieldDidBeginEditing(self)
        sendActions(for: .editingDidBegin)
        return true
    }

    @discardableResult
    override open func resignFirstResponder() -> Bool {
        guard isFirstResponder else { return true }
        guard delegate?.textFieldShouldEndEditing(self) ?? true, super.resignFirstResponder() else { return false }
        setNeedsLayout()
        setNeedsDisplay()
        delegate?.textFieldDidEndEditing(self)
        sendActions(for: .editingDidEnd)
        return true
    }

    override open func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        guard isEnabled, let touch = touches.first else { return }
        let location = touch.location(in: self)
        guard point(inside: location, with: event) else { return }
        if showsClearButton, clearButtonRect(forBounds: bounds).insetBy(dx: -4, dy: -8).contains(location) {
            clear()
            return
        }
        becomeFirstResponder()
    }

    /// The clear button was tapped: the delegate can keep the text.
    func clear() {
        guard delegate?.textFieldShouldClear(self) ?? true else { return }
        text = ""
        sendActions(for: .editingChanged)
        delegate?.textFieldDidChangeSelection(self)
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

    // MARK: Geometry (uikit/textfield/looks)

    private var bordered: Bool { borderStyle != .none }
    /// The text's inset from the border: 7 in the rounded and bezel fields, 2 in the line field.
    private var horizontalInset: CGFloat {
        switch borderStyle {
        case .none: return 0
        case .line: return 2
        case .bezel, .roundedRect: return 7
        }
    }
    /// A bordered field sizes to its text plus twice this each side (uikit/controls/intrinsic:
    /// 67 for the 39 pt "Hello" in a rounded field; 95 for the 87 pt "Line border" in a line one).
    private var sizingInset: CGFloat {
        switch borderStyle {
        case .none: return 0
        case .line: return 4
        case .bezel, .roundedRect: return 14
        }
    }
    private var resolvedFont: UIFont { font ?? .systemFont(ofSize: 17) }

    /// Whether a view shown by `mode` shows now.
    private func shows(_ mode: ViewMode) -> Bool {
        switch mode {
        case .never: return false
        case .always: return true
        case .whileEditing: return isEditing
        case .unlessEditing: return !isEditing
        }
    }

    /// The clear button shows in its mode while there is text.
    var showsClearButton: Bool { shows(clearButtonMode) && text?.isEmpty == false }
    var showsLeftView: Bool { leftView != nil && shows(leftViewMode) }
    var showsRightView: Bool { rightView != nil && shows(rightViewMode) }

    override open func sizeThatFits(_ size: CGSize) -> CGSize {
        let f = resolvedFont
        // A plain field is its line height plus 1.5 on the pixel grid (22 at 17 pt on an iPhone,
        // 21.5 on Catalyst); its width is the text's rounded up to the point (74 for 73.5).
        let height: CGFloat
        switch borderStyle {
        case .none: height = (f.lineHeight + 1.5).roundedUp(to: UIScreen.main.scale)
        case .line: height = 30
        case .bezel: height = 32
        case .roundedRect: height = 34
        }
        let showsPlaceholder = text?.isEmpty != false
        let content = showsPlaceholder ? (placeholder ?? "") : text!
        let measured = showsPlaceholder ? placeholderStyle.font : f
        let layout = UIKitScene.shared.textEngine.layout([StyledRun(content, font: measured.resolved)], options: .default, width: nil)
        return CGSize(width: layout.size.width.rounded(.up) + 2 * sizingInset, height: height)
    }

    /// A field's intrinsic size is what fits its text (uikit/controls/intrinsic).
    override open var intrinsicContentSize: CGSize {
        sizeThatFits(CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude))
    }

    /// The text's line box: between the side views (or the border inset) and the clear button,
    /// centred vertically (the bezel's text sits 1.5 lower).
    open func textRect(forBounds bounds: CGRect) -> CGRect {
        let line = resolvedFont.lineHeight.roundedUp(to: UIScreen.main.scale)
        let left = showsLeftView ? leftViewRect(forBounds: bounds).maxX + horizontalInset : bounds.minX + horizontalInset
        var right = showsRightView ? rightViewRect(forBounds: bounds).minX - horizontalInset : bounds.maxX - horizontalInset
        if showsClearButton { right = min(right, clearButtonRect(forBounds: bounds).minX - Self.clearButtonGap) }
        let y = bounds.minY + (bounds.height - line) / 2 + (borderStyle == .bezel ? 1.5 : 0)
        return CGRect(x: left, y: y, width: max(0, right - left), height: line)
    }

    open func editingRect(forBounds bounds: CGRect) -> CGRect { textRect(forBounds: bounds) }
    open func placeholderRect(forBounds bounds: CGRect) -> CGRect { textRect(forBounds: bounds) }
    open func borderRect(forBounds bounds: CGRect) -> CGRect { bounds }

    /// The clear button: 17 pt, centred 15 in from the right edge and half a point below the middle.
    static let clearButtonSize: CGFloat = 17
    static let clearButtonGap: CGFloat = 11
    open func clearButtonRect(forBounds bounds: CGRect) -> CGRect {
        CGRect(x: bounds.maxX - 15 - Self.clearButtonSize / 2, y: bounds.midY + 0.5 - Self.clearButtonSize / 2,
               width: Self.clearButtonSize, height: Self.clearButtonSize)
    }

    open func leftViewRect(forBounds bounds: CGRect) -> CGRect {
        let size = leftView?.bounds.size ?? .zero
        return CGRect(x: bounds.minX, y: bounds.minY + ((bounds.height - size.height) / 2).roundedUp(to: UIScreen.main.scale), width: size.width, height: size.height)
    }

    open func rightViewRect(forBounds bounds: CGRect) -> CGRect {
        let size = rightView?.bounds.size ?? .zero
        return CGRect(x: bounds.maxX - size.width, y: bounds.minY + ((bounds.height - size.height) / 2).roundedUp(to: UIScreen.main.scale), width: size.width, height: size.height)
    }

    override open func layoutSubviews() {
        super.layoutSubviews()
        if let leftView {
            leftView.isHidden = !showsLeftView
            leftView.frame = leftViewRect(forBounds: bounds)
        }
        if let rightView {
            rightView.isHidden = !showsRightView
            rightView.frame = rightViewRect(forBounds: bounds)
        }
    }

    // MARK: Painting

    /// The placeholder's font and colour: the attributed placeholder's first run's, else the
    /// field's font in the placeholder colour.
    private var placeholderStyle: (font: UIFont, color: UIColor) {
        guard let attributed = attributedPlaceholder, attributed.length > 0 else { return (resolvedFont, placeholderColor) }
        let attributes = attributed.attributes(at: 0, effectiveRange: nil)
        return (attributes[.font] as? UIFont ?? resolvedFont, attributes[.foregroundColor] as? UIColor ?? placeholderColor)
    }

    override func drawContent(into list: inout DisplayList, context: PaintContext, style: UIUserInterfaceStyle) {
        let rect = context.absoluteRect(CGRect(origin: .zero, size: bounds.size))
        switch borderStyle {
        case .none: break
        case .roundedRect:
            list.append(.fillRRect(rect, cornerRadius: 4, UIColor.systemBackground.rgba(for: style)))
            list.append(.strokePath(Path(roundedRect: rect.insetBy(dx: 0.25, dy: 0.25), cornerRadius: 4, style: .circular),
                                    style: StrokeStyle(lineWidth: 0.5), RGBA(red: 0, green: 0, blue: 0, alpha: 0.2)))
        case .line:
            list.append(.strokePath(Path(rect.insetBy(dx: 0.5, dy: 0.5)), style: StrokeStyle(lineWidth: 1), UIColor.label.rgba(for: style)))
        case .bezel:
            list.append(.strokePath(Path(rect.insetBy(dx: 0.5, dy: 0.5)), style: StrokeStyle(lineWidth: 1), RGBA(red: 0, green: 0, blue: 0, alpha: 0.5)))
            var inner = Path()
            inner.move(to: CGPoint(x: rect.minX + 1.5, y: rect.maxY - 1))
            inner.addLine(to: CGPoint(x: rect.minX + 1.5, y: rect.minY + 1.5))
            inner.addLine(to: CGPoint(x: rect.maxX - 1, y: rect.minY + 1.5))
            list.append(.strokePath(inner, style: StrokeStyle(lineWidth: 1), RGBA(red: 0, green: 0, blue: 0, alpha: 1 / 3)))
        }
        if showsClearButton {
            // A 17 pt disc at 80 % white (the dark look is unverified) with a white cross
            // 1.7 wide reaching 3.3 from the centre.
            let fill: RGBA = style == .dark ? RGBA(r: 92, g: 92, b: 97) : RGBA(r: 204, g: 204, b: 204)
            let button = context.absoluteRect(clearButtonRect(forBounds: bounds))
            list.append(.fillPath(Path(ellipseIn: button), fill))
            var cross = Path()
            let arm: CGFloat = 3.3
            cross.move(to: CGPoint(x: button.midX - arm, y: button.midY - arm))
            cross.addLine(to: CGPoint(x: button.midX + arm, y: button.midY + arm))
            cross.move(to: CGPoint(x: button.midX + arm, y: button.midY - arm))
            cross.addLine(to: CGPoint(x: button.midX - arm, y: button.midY + arm))
            let ink: RGBA = style == .dark ? RGBA(r: 28, g: 28, b: 30) : RGBA.white
            list.append(.strokePath(cross, style: StrokeStyle(lineWidth: 1.7, lineCap: .round), ink))
        }
        let showsPlaceholder = text?.isEmpty != false
        let f = showsPlaceholder ? placeholderStyle.font : resolvedFont
        var textRect = self.textRect(forBounds: bounds)
        if showsPlaceholder, f !== resolvedFont {
            let line = f.lineHeight.roundedUp(to: UIScreen.main.scale)
            textRect.origin.y += (textRect.height - line) / 2
            textRect.size.height = line
        }
        let string = showsPlaceholder ? (placeholder ?? "") : (isSecureTextEntry ? String(repeating: "•", count: text!.count) : text!)
        guard !string.isEmpty else { return }
        let layout = UIKitScene.shared.textEngine.layout([StyledRun(string, font: f.resolved)], options: TextLayoutOptions(lineLimit: 1), width: textRect.width)
        guard let line = layout.lines.first else { return }
        let color = (showsPlaceholder ? placeholderStyle.color : (isEnabled ? (textColor ?? .label) : .tertiaryLabel)).rgba(for: style)
        let inset: CGFloat
        switch textAlignment {
        case .center: inset = (textRect.width - line.inkWidth) / 2
        case .right: inset = textRect.width - line.inkWidth
        default: inset = 0
        }
        // The baseline sits on the pixel grid (37 for the 30 pt line field's 36.94).
        let scale = UIScreen.main.scale
        let baseline = ((context.origin.y + textRect.minY + f.ascender) * scale).rounded() / scale
        for fragment in line.fragments {
            list.append(.drawText(fragment.text, DisplayFont(f.resolved), origin: CGPoint(x: context.origin.x + textRect.minX + inset + fragment.x, y: baseline), color))
        }
    }

    // MARK: Semantics

    override func decorateSemantics(_ node: inout SemanticsNode) {
        node.role = .textField
        let windowRect = convert(textRect(forBounds: bounds), to: nil)
        var info = TextInputInfo(text: text ?? "", placeholder: placeholder ?? "", isSecure: isSecureTextEntry,
                                 textRect: windowRect, font: DisplayFont(resolvedFont.resolved), isEnabled: isEnabled)
        // The keyboard reaches the host's input element as its attributes (as SwiftUIWeb's
        // `keyboardType`, `submitLabel`, `textContentType` and autocapitalization do).
        info.inputMode = keyboardType.inputMode
        info.inputType = isSecureTextEntry ? "password" : keyboardType.inputType
        info.autocomplete = textContentType?.rawValue
        info.autocapitalize = autocapitalizationType.token
        info.enterKeyHint = returnKeyType.enterKeyHint
        info.autocorrect = autocorrectionType != .no
        node.textInput = info
        if node.label.isEmpty { node.label = placeholder ?? "" }
    }
}

// `UIKeyboardType`, `UIReturnKeyType`, `UITextAutocapitalizationType`, `UITextAutocorrectionType`,
// `UITextSpellCheckingType` and `UITextContentType` live in WebGraphics (Input/TextInputTypes.swift),
// shared with SwiftUIWeb.
