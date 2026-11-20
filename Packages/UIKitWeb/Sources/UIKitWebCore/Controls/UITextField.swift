// UITextField (Docs/elements/UIKit/UITextField.md): the rounded-rect field (34 pt, a 0.5 pt
// border at 20 % black inside 4 pt corners, text 7 in), the line (30 pt, 1 pt label-coloured,
// text 2 in) and bezel (32 pt, 1 pt black 50 % with an inner 1 pt 33 % line on top and left,
// text 7 in and 1.5 down) borders, the clear button (17 pt `xmark.circle.fill` at 80 % white
// centred 15 from the right edge), left and right views flush to the edges, all measured on
// `uikit/textfield/looks`; typing goes through the host's input element (`TextInputInfo`).
import WebFoundation   // NSCoder, for init?(coder:)

#if !os(WASI)
import Foundation
#endif

/// The methods a text field's delegate implements.
@preconcurrency @MainActor
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
@preconcurrency @MainActor
open class UITextField: UIControl {
    /// No archive to decode on the web: nil, as for an archive this class cannot read.
    public required init?(coder: NSCoder) { return nil }

    public enum BorderStyle: Int, Sendable { case none = 0, line, bezel, roundedRect }
    public enum ViewMode: Int, Sendable { case never = 0, whileEditing, unlessEditing, always }

    open var text: String? {
        didSet {
            guard text != oldValue else { return }
            // A text the app sets puts the caret at its end, as the host's element does; the
            // host's own edits keep the selection it reports next.
            let length = (text ?? "").utf16.count
            if keepsSelection {
                let start = min(selection.location, length)
                selection = NSRange(location: start, length: min(selection.length, length - start))
            } else {
                selection = NSRange(location: length, length: 0)
                // A selection the app set earlier is replaced by the caret at the end.
                if pendingSelection != nil { pendingSelection = selection }
            }
            setNeedsDisplay()
        }
    }
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

    // The views shown for editing (Controls/UIInputView.swift): the accessory along the
    // bottom of the window while editing; a custom input view is kept but not shown.
    private var storedInputView: UIView?
    private var storedInputAccessoryView: UIView?
    override open var inputView: UIView? {
        get { storedInputView }
        set { storedInputView = newValue }
    }
    override open var inputAccessoryView: UIView? {
        get { storedInputAccessoryView }
        set { storedInputAccessoryView = newValue }
    }

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
        keepsSelection = true
        text = newText
        keepsSelection = false
        sendActions(for: .editingChanged)
        delegate?.textFieldDidChangeSelection(self)
    }

    // MARK: Edit actions (UIPasteboard.general; uk-pasteboard)

    /// The host's input element keeps the field's selection, so the programmatic actions work
    /// on the whole text: copy and cut take it all, paste appends.
    override open func copy(_ sender: Any?) {
        guard let text, !text.isEmpty else { return }
        UIPasteboard.general.string = text
    }

    override open func cut(_ sender: Any?) {
        guard isEnabled, let text, !text.isEmpty else { return }
        UIPasteboard.general.string = text
        self.text = ""
        sendActions(for: .editingChanged)
    }

    override open func paste(_ sender: Any?) {
        guard isEnabled, let string = UIPasteboard.general.string else { return }
        text = (text ?? "") + string
        sendActions(for: .editingChanged)
    }

    /// The host's element moved its caret or selection (UTF-16 offsets).
    func hostDidSelect(start: Int, end: Int) {
        pendingSelection = nil
        let length = (text ?? "").utf16.count
        let lower = max(0, min(min(start, end), length)), upper = max(lower, min(max(start, end), length))
        let range = NSRange(location: lower, length: upper - lower)
        guard range != selection else { return }
        inputDelegate?.selectionWillChange(self)
        selection = range
        inputDelegate?.selectionDidChange(self)
        delegate?.textFieldDidChangeSelection(self)
    }

    // MARK: Text input (UITextInput: positions are UTF-16 offsets of the text)

    /// The selection the host's element keeps (UTF-16 offsets), as it last reported it.
    private(set) var selection = NSRange(location: 0, length: 0)
    /// A selection the app set, for the host's element to take.
    private(set) var pendingSelection: NSRange?
    private var keepsSelection = false
    /// Told before and after the text or selection changes (`UITextInput`).
    open weak var inputDelegate: (any UITextInputDelegate)?

    open var hasText: Bool { !(text ?? "").isEmpty }

    /// Types `text` over the selection, as a key press does.
    open func insertText(_ text: String) { replace(selectedTextRange ?? UITextRange(start: endOfDocument, end: endOfDocument), withText: text) }

    /// Deletes the selection, else the character before the caret.
    open func deleteBackward() {
        guard selection.length == 0 else { replace(selectedTextRange!, withText: ""); return }
        let utf16 = Array((text ?? "").utf16)
        let caret = min(selection.location, utf16.count)
        guard caret > 0 else { return }
        let removed = String(decoding: utf16[..<caret], as: UTF16.self).last?.utf16.count ?? 1
        replace(UITextRange(start: UITextPosition(offset: caret - removed), end: UITextPosition(offset: caret)), withText: "")
    }

    open var beginningOfDocument: UITextPosition { UITextPosition(offset: 0) }
    open var endOfDocument: UITextPosition { UITextPosition(offset: (text ?? "").utf16.count) }

    /// The selection as positions; setting it moves the host's caret or selection there.
    open var selectedTextRange: UITextRange? {
        get { UITextRange(start: UITextPosition(offset: selection.location), end: UITextPosition(offset: selection.location + selection.length)) }
        set {
            guard let newValue else { return }
            let range = characterRange(newValue)
            guard range != selection else { return }
            inputDelegate?.selectionWillChange(self)
            selection = range
            pendingSelection = range
            inputDelegate?.selectionDidChange(self)
            setNeedsDisplay()
        }
    }

    private func characterRange(_ range: UITextRange) -> NSRange {
        let length = (text ?? "").utf16.count
        let start = max(0, min(min(range.start.offset, range.end.offset), length))
        let end = max(start, min(max(range.start.offset, range.end.offset), length))
        return NSRange(location: start, length: end - start)
    }

    open func text(in range: UITextRange) -> String? {
        let utf16 = Array((text ?? "").utf16)
        let characters = characterRange(range)
        return String(decoding: utf16[characters.location..<(characters.location + characters.length)], as: UTF16.self)
    }

    /// Replaces the range with `text`, puts the caret after it and reports the edit as typing
    /// does (`.editingChanged`).
    open func replace(_ range: UITextRange, withText replacement: String) {
        let characters = characterRange(range)
        var utf16 = Array((text ?? "").utf16)
        utf16.replaceSubrange(characters.location..<(characters.location + characters.length), with: Array(replacement.utf16))
        inputDelegate?.textWillChange(self)
        keepsSelection = true
        text = String(decoding: utf16, as: UTF16.self)
        keepsSelection = false
        let caret = characters.location + replacement.utf16.count
        selection = NSRange(location: caret, length: 0)
        pendingSelection = selection
        inputDelegate?.textDidChange(self)
        sendActions(for: .editingChanged)
        delegate?.textFieldDidChangeSelection(self)
    }

    /// The caret before a position: 2 points wide at the character's left edge, the text
    /// line's height (view coordinates).
    open func caretRect(for position: UITextPosition) -> CGRect {
        let rect = textRect(forBounds: bounds)
        let x = rect.minX + caretOffset(upTo: max(0, min(position.offset, (text ?? "").utf16.count)), in: rect)
        return CGRect(x: x, y: rect.minY, width: 2, height: min(rect.height, resolvedFont.lineHeight))
    }

    /// The rectangle a range takes on the line (view coordinates).
    open func firstRect(for range: UITextRange) -> CGRect {
        let characters = characterRange(range)
        let start = caretRect(for: UITextPosition(offset: characters.location))
        guard characters.length > 0 else { return start }
        let end = caretRect(for: UITextPosition(offset: characters.location + characters.length))
        return CGRect(x: start.minX, y: start.minY, width: end.minX - start.minX, height: start.height)
    }

    /// How far into the text rect the first `offset` UTF-16 units reach, with the alignment's inset.
    private func caretOffset(upTo offset: Int, in rect: CGRect) -> CGFloat {
        let whole = isSecureTextEntry ? String(repeating: "•", count: (text ?? "").count) : (text ?? "")
        let prefixText = String(decoding: Array((text ?? "").utf16).prefix(offset), as: UTF16.self)
        let prefix = isSecureTextEntry ? String(repeating: "•", count: prefixText.count) : prefixText
        func width(_ string: String) -> CGFloat {
            guard !string.isEmpty else { return 0 }
            let layout = UIKitScene.shared.textEngine.layout([StyledRun(string, font: resolvedFont.resolved)], options: TextLayoutOptions(lineLimit: 1), width: nil)
            return layout.size.width
        }
        let total = width(whole)
        let inset: CGFloat
        switch textAlignment {
        case .center: inset = (rect.width - total) / 2
        case .right: inset = rect.width - total
        default: inset = 0
        }
        return inset + width(prefix)
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
    /// The clear button's disc colour (a search field's is the secondary label colour).
    var clearButtonFill: UIColor { UIColor(_light: RGBA(r: 204, g: 204, b: 204), _dark: RGBA(r: 92, g: 92, b: 97)) }
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
            let fill = clearButtonFill.rgba(for: style)
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
        // A selection the app set moves the element's (`selectedTextRange`, `insertText`).
        info.selection = pendingSelection.map { TextRange(start: $0.location, end: $0.location + $0.length) }
        node.textInput = info
        if node.label.isEmpty { node.label = placeholder ?? "" }
    }
}

// `UIKeyboardType`, `UIReturnKeyType`, `UITextAutocapitalizationType`, `UITextAutocorrectionType`,
// `UITextSpellCheckingType` and `UITextContentType` live in WebGraphics (Input/TextInputTypes.swift),
// shared with SwiftUIWeb.
