import WebFoundation

/// A control that displays an editable text interface.
///
/// macOS geometry measured in `Docs/elements/TextField.md`: the rounded-border field (default) is
/// 24 pt tall with the text 6 pt in on a 17 pt baseline, a white fill with a 1 pt border outside
/// it; the plain style is the bare text line. Editing happens in a transparent `<input>` the
/// browser host keeps over the field (typing, IME, caret and selection are the browser's); the
/// runtime paints text, placeholder and bullets.
public struct TextField<Label: View>: View {
    package let text: Binding<String>
    package let label: Label
    package let prompt: Text?
    package let isSecure: Bool
    /// `axis: .vertical`: the field wraps and grows with its text.
    package var axis: Axis? = nil
    /// A value field (`format:` or `formatter:`): the text goes into the binding on submit or
    /// when focus leaves, not on every keystroke.
    package var commitsOnSubmit = false
    package var onEditingChanged: ((Bool) -> Void)? = nil
    package var onCommit: (() -> Void)? = nil

    /// Creates a text field with a text label generated from a localized title string.
    public init(_ titleKey: LocalizedStringKey, text: Binding<String>, prompt: Text? = nil) where Label == Text {
        self.init(text: text, prompt: prompt, isSecure: false) { Text(titleKey) }
    }

    /// Creates a text field with a text label generated from a title string.
    @_disfavoredOverload
    public init<S: StringProtocol>(_ title: S, text: Binding<String>, prompt: Text? = nil) where Label == Text {
        self.init(text: text, prompt: prompt, isSecure: false) { Text(title) }
    }

    /// Creates a text field with a custom label (the prompt, or the label's text, is the placeholder).
    public init(text: Binding<String>, prompt: Text? = nil, @ViewBuilder label: () -> Label) {
        self.init(text: text, prompt: prompt, isSecure: false, label: label)
    }

    /// Creates a text field that can grow along `axis` (`.vertical` wraps the text and grows
    /// with it, within `lineLimit`).
    public init(_ titleKey: LocalizedStringKey, text: Binding<String>, prompt: Text? = nil, axis: Axis) where Label == Text {
        self.init(titleKey, text: text, prompt: prompt)
        self.axis = axis
    }

    @_disfavoredOverload
    public init<S: StringProtocol>(_ title: S, text: Binding<String>, prompt: Text? = nil, axis: Axis) where Label == Text {
        self.init(title, text: text, prompt: prompt)
        self.axis = axis
    }

    /// Creates a text field with a custom label that can grow along `axis`.
    public init(text: Binding<String>, prompt: Text? = nil, axis: Axis, @ViewBuilder label: () -> Label) {
        self.init(text: text, prompt: prompt, label: label)
        self.axis = axis
    }

    // MARK: Editing callbacks (the iOS 13 forms)

    /// Creates a text field whose `onEditingChanged` hears focus coming and going and whose
    /// `onCommit` runs when the user presses Return.
    public init(_ titleKey: LocalizedStringKey, text: Binding<String>, onEditingChanged: @escaping (Bool) -> Void, onCommit: @escaping () -> Void) where Label == Text {
        self.init(titleKey, text: text)
        self.onEditingChanged = onEditingChanged
        self.onCommit = onCommit
    }

    public init(_ titleKey: LocalizedStringKey, text: Binding<String>, onEditingChanged: @escaping (Bool) -> Void) where Label == Text {
        self.init(titleKey, text: text)
        self.onEditingChanged = onEditingChanged
    }

    public init(_ titleKey: LocalizedStringKey, text: Binding<String>, onCommit: @escaping () -> Void) where Label == Text {
        self.init(titleKey, text: text)
        self.onCommit = onCommit
    }

    @_disfavoredOverload
    public init<S: StringProtocol>(_ title: S, text: Binding<String>, onEditingChanged: @escaping (Bool) -> Void, onCommit: @escaping () -> Void) where Label == Text {
        self.init(title, text: text)
        self.onEditingChanged = onEditingChanged
        self.onCommit = onCommit
    }

    @_disfavoredOverload
    public init<S: StringProtocol>(_ title: S, text: Binding<String>, onEditingChanged: @escaping (Bool) -> Void) where Label == Text {
        self.init(title, text: text)
        self.onEditingChanged = onEditingChanged
    }

    @_disfavoredOverload
    public init<S: StringProtocol>(_ title: S, text: Binding<String>, onCommit: @escaping () -> Void) where Label == Text {
        self.init(title, text: text)
        self.onCommit = onCommit
    }

    // MARK: Values

    /// Creates a text field that applies a format style to a bound value: the value's text is
    /// shown, what the user types is parsed back into the value when they press Return or
    /// focus leaves (text that does not parse leaves the value alone).
    public init<F: ParseableFormatStyle>(_ titleKey: LocalizedStringKey, value: Binding<F.FormatInput>, format: F, prompt: Text? = nil)
    where F.FormatOutput == String, Label == Text {
        self.init(text: Self.textBinding(value, format: format), prompt: prompt, isSecure: false) { Text(titleKey) }
        commitsOnSubmit = true
    }

    @_disfavoredOverload
    public init<S: StringProtocol, F: ParseableFormatStyle>(_ title: S, value: Binding<F.FormatInput>, format: F, prompt: Text? = nil)
    where F.FormatOutput == String, Label == Text {
        self.init(text: Self.textBinding(value, format: format), prompt: prompt, isSecure: false) { Text(title) }
        commitsOnSubmit = true
    }

    public init<F: ParseableFormatStyle>(value: Binding<F.FormatInput>, format: F, prompt: Text? = nil, @ViewBuilder label: () -> Label)
    where F.FormatOutput == String {
        self.init(text: Self.textBinding(value, format: format), prompt: prompt, isSecure: false, label: label)
        commitsOnSubmit = true
    }

    /// Creates a text field that applies a formatter to a bound value.
    public init<V>(_ titleKey: LocalizedStringKey, value: Binding<V>, formatter: Formatter, prompt: Text? = nil) where Label == Text {
        self.init(text: Self.textBinding(value, formatter: formatter), prompt: prompt, isSecure: false) { Text(titleKey) }
        commitsOnSubmit = true
    }

    @_disfavoredOverload
    public init<S: StringProtocol, V>(_ title: S, value: Binding<V>, formatter: Formatter, prompt: Text? = nil) where Label == Text {
        self.init(text: Self.textBinding(value, formatter: formatter), prompt: prompt, isSecure: false) { Text(title) }
        commitsOnSubmit = true
    }

    public init<V>(value: Binding<V>, formatter: Formatter, prompt: Text? = nil, @ViewBuilder label: () -> Label) {
        self.init(text: Self.textBinding(value, formatter: formatter), prompt: prompt, isSecure: false, label: label)
        commitsOnSubmit = true
    }

    public init<V>(_ titleKey: LocalizedStringKey, value: Binding<V>, formatter: Formatter,
                   onEditingChanged: @escaping (Bool) -> Void, onCommit: @escaping () -> Void) where Label == Text {
        self.init(titleKey, value: value, formatter: formatter)
        self.onEditingChanged = onEditingChanged
        self.onCommit = onCommit
    }

    private static func textBinding<F: ParseableFormatStyle>(_ value: Binding<F.FormatInput>, format: F) -> Binding<String> where F.FormatOutput == String {
        Binding(get: { format.format(value.wrappedValue) },
                set: { text in if let parsed = try? format.parseStrategy.parse(text) { value.wrappedValue = parsed } })
    }

    private static func textBinding<V>(_ value: Binding<V>, formatter: Formatter) -> Binding<String> {
        Binding(get: { formatter.string(for: value.wrappedValue) ?? "" },
                set: { text in
                    #if os(WASI)
                    if let parsed = formatter.value(from: text) as? V { value.wrappedValue = parsed }
                    #elseif os(Linux)
                    // corelibs Foundation does not expose Formatter.getObjectValue. Use the
                    // concrete parsers it provides; unsupported formatters leave the value alone.
                    let object: Any?
                    if let number = formatter as? NumberFormatter { object = number.number(from: text) }
                    else if let date = formatter as? DateFormatter { object = date.date(from: text) }
                    else { object = nil }
                    if let parsed = object as? V { value.wrappedValue = parsed }
                    #else
                    var object: AnyObject?
                    if formatter.getObjectValue(&object, for: text, errorDescription: nil), let parsed = object as? V { value.wrappedValue = parsed }
                    #endif
                })
    }

    package init(text: Binding<String>, prompt: Text?, isSecure: Bool, @ViewBuilder label: () -> Label) {
        self.text = text
        self.prompt = prompt
        self.isSecure = isSecure
        self.label = label()
    }

    @Environment(\.textFieldStyle) private var style

    @Environment(\._formStyle) private var formStyle
    @Environment(\.labelsHidden) private var labelsHidden

    public var body: some View {
        let core = _TextFieldCore(text: text, placeholder: prompt?.resolvedString ?? _labelString, isSecure: isSecure, style: style,
                                  axis: axis, commitsOnSubmit: commitsOnSubmit, onEditingChanged: onEditingChanged, onCommit: onCommit)
        switch formStyle {
        case nil:
            core
        case .columns:
            _FormLabeledRow(label: labelsHidden ? nil : AnyView(_ControlLabel(label: label)), content: AnyView(core), mode: .firstTextBaseline)
        case .grouped:
            _FormLabeledRow(label: labelsHidden ? nil : AnyView(_ControlLabel(label: label)),
                            content: AnyView(_TextFieldCore(text: text, placeholder: prompt?.resolvedString ?? _labelString, isSecure: isSecure,
                                                            style: PlainTextFieldStyle(), fitsText: true, axis: axis, commitsOnSubmit: commitsOnSubmit,
                                                            onEditingChanged: onEditingChanged, onCommit: onCommit)),
                            mode: .grouped)
        }
    }

    private var _labelString: String {
        if let text = label as? Text { return text.resolvedString }
        return ""
    }
}

/// A control into which people securely enter private text.
public struct SecureField<Label: View>: View {
    package let field: TextField<Label>

    public init(_ titleKey: LocalizedStringKey, text: Binding<String>, prompt: Text? = nil) where Label == Text {
        field = TextField(text: text, prompt: prompt, isSecure: true) { Text(titleKey) }
    }

    @_disfavoredOverload
    public init<S: StringProtocol>(_ title: S, text: Binding<String>, prompt: Text? = nil) where Label == Text {
        field = TextField(text: text, prompt: prompt, isSecure: true) { Text(title) }
    }

    public init(text: Binding<String>, prompt: Text? = nil, @ViewBuilder label: () -> Label) {
        field = TextField(text: text, prompt: prompt, isSecure: true, label: label)
    }

    public var body: some View { field }
}

// MARK: - Styles

/// A specification for the appearance and interaction of a text field.
public protocol TextFieldStyle: Sendable {
    /// The style's bezel (macOS): rounded (the default), square (drawn like rounded on macOS 26)
    /// or none.
    var _bezel: _TextFieldBezel { get }
}

/// How a text field is drawn.
public enum _TextFieldBezel: Sendable, Equatable {
    case rounded, square, plain
}

/// The default text field style (rounded border on macOS).
public struct DefaultTextFieldStyle: TextFieldStyle {
    public init() {}
    public var _bezel: _TextFieldBezel { .rounded }
}

/// A text field style with a system-defined rounded border.
public struct RoundedBorderTextFieldStyle: TextFieldStyle {
    public init() {}
    public var _bezel: _TextFieldBezel { .rounded }
}

/// A text field style with a system-defined square border.
public struct SquareBorderTextFieldStyle: TextFieldStyle {
    public init() {}
    public var _bezel: _TextFieldBezel { .square }
}

/// A text field style with no decoration.
public struct PlainTextFieldStyle: TextFieldStyle {
    public init() {}
    public var _bezel: _TextFieldBezel { .plain }
}

extension TextFieldStyle where Self == DefaultTextFieldStyle {
    public static var automatic: DefaultTextFieldStyle { DefaultTextFieldStyle() }
}
extension TextFieldStyle where Self == RoundedBorderTextFieldStyle {
    public static var roundedBorder: RoundedBorderTextFieldStyle { RoundedBorderTextFieldStyle() }
}
extension TextFieldStyle where Self == SquareBorderTextFieldStyle {
    public static var squareBorder: SquareBorderTextFieldStyle { SquareBorderTextFieldStyle() }
}
extension TextFieldStyle where Self == PlainTextFieldStyle {
    public static var plain: PlainTextFieldStyle { PlainTextFieldStyle() }
}

package struct TextFieldStyleKey: EnvironmentKey {
    package static let defaultValue: any TextFieldStyle = DefaultTextFieldStyle()
}

extension EnvironmentValues {
    package var textFieldStyle: any TextFieldStyle {
        get { self[TextFieldStyleKey.self] }
        set { self[TextFieldStyleKey.self] = newValue }
    }
}

extension View {
    /// Sets the style for text fields within this view.
    nonisolated public func textFieldStyle<S: TextFieldStyle>(_ style: S) -> some View {
        environment(\.textFieldStyle, style)
    }
}

// MARK: - Submit

/// The types of triggers that result in a submit action.
public struct SubmitTriggers: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let text = SubmitTriggers(rawValue: 1 << 0)
    public static let search = SubmitTriggers(rawValue: 1 << 1)
}

package struct SubmitActionKey: EnvironmentKey {
    package nonisolated(unsafe) static let defaultValue: _ActionBox? = nil
}

extension EnvironmentValues {
    /// The action text fields run when the user presses Return.
    package var submitAction: _ActionBox? {
        get { self[SubmitActionKey.self] }
        set { self[SubmitActionKey.self] = newValue }
    }
}

extension View {
    /// Adds an action to perform when the user submits a value to this view (Return in a field).
    nonisolated public func onSubmit(_ action: @escaping @MainActor () -> Void) -> some View {
        environment(\.submitAction, _ActionBox(action))
    }

    /// Adds an action to perform when the user submits a value through one of the triggers.
    nonisolated public func onSubmit(of triggers: SubmitTriggers, _ action: @escaping @MainActor () -> Void) -> some View {
        environment(\.submitAction, _ActionBox(action))
    }

    /// Sets whether to disable autocorrection for this view (the host's input element).
    nonisolated public func autocorrectionDisabled(_ disable: Bool = true) -> some View {
        environment(\.autocorrectionDisabled, disable)
    }

    /// Sets the submit label for this view (the keyboard's Return key on iOS, `enterkeyhint`).
    nonisolated public func submitLabel(_ submitLabel: SubmitLabel) -> some View {
        environment(\._submitLabel, submitLabel)
    }

    /// Sets the text content type for this view, which the system uses to offer suggestions
    /// while the user enters text (the input element's `autocomplete`).
    nonisolated public func textContentType(_ textContentType: UITextContentType?) -> some View {
        environment(\._textContentType, textContentType)
    }

    /// Sets the keyboard type for this view (the input element's `inputmode` and `type`).
    nonisolated public func keyboardType(_ type: UIKeyboardType) -> some View {
        environment(\._keyboardType, type)
    }

    /// Sets how often the shift key engages on the software keyboard (`autocapitalize`).
    nonisolated public func textInputAutocapitalization(_ autocapitalization: TextInputAutocapitalization?) -> some View {
        environment(\._textInputAutocapitalization, autocapitalization)
    }
}

// MARK: - Keyboard attributes

/// A semantic label describing the label of submission within a view hierarchy.
public struct SubmitLabel: Hashable, Sendable {
    package let key: UIReturnKeyType
    public static let done = SubmitLabel(key: .done)
    public static let go = SubmitLabel(key: .go)
    public static let send = SubmitLabel(key: .send)
    public static let join = SubmitLabel(key: .join)
    public static let route = SubmitLabel(key: .route)
    public static let search = SubmitLabel(key: .search)
    public static let `return` = SubmitLabel(key: .default)
    public static let next = SubmitLabel(key: .next)
    public static let `continue` = SubmitLabel(key: .continue)
}

/// The kind of autocapitalization behavior applied during text input.
public struct TextInputAutocapitalization: Hashable, Sendable {
    package let kind: UITextAutocapitalizationType
    public init(_ type: UITextAutocapitalizationType) { kind = type }
    public static let never = TextInputAutocapitalization(.none)
    public static let words = TextInputAutocapitalization(.words)
    public static let sentences = TextInputAutocapitalization(.sentences)
    public static let characters = TextInputAutocapitalization(.allCharacters)
}

package struct SubmitLabelKey: EnvironmentKey { package static let defaultValue = SubmitLabel.return }
package struct TextContentTypeKey: EnvironmentKey { package static let defaultValue: UITextContentType? = nil }
package struct KeyboardTypeKey: EnvironmentKey { package static let defaultValue = UIKeyboardType.default }
package struct TextInputAutocapitalizationKey: EnvironmentKey { package static let defaultValue: TextInputAutocapitalization? = nil }
package struct AutocorrectionDisabledKey: EnvironmentKey { package static let defaultValue = false }

extension EnvironmentValues {
    /// A Boolean value that determines whether the view hierarchy has auto-correction disabled.
    public var autocorrectionDisabled: Bool {
        get { self[AutocorrectionDisabledKey.self] }
        set { self[AutocorrectionDisabledKey.self] = newValue }
    }

    package var _submitLabel: SubmitLabel {
        get { self[SubmitLabelKey.self] }
        set { self[SubmitLabelKey.self] = newValue }
    }

    package var _textContentType: UITextContentType? {
        get { self[TextContentTypeKey.self] }
        set { self[TextContentTypeKey.self] = newValue }
    }

    package var _keyboardType: UIKeyboardType {
        get { self[KeyboardTypeKey.self] }
        set { self[KeyboardTypeKey.self] = newValue }
    }

    package var _textInputAutocapitalization: TextInputAutocapitalization? {
        get { self[TextInputAutocapitalizationKey.self] }
        set { self[TextInputAutocapitalizationKey.self] = newValue }
    }
}

// MARK: - Primitive

/// The laid-out and painted field; the host's `<input>` mirrors it through the semantics tree.
public struct _TextFieldCore: View {
    package let text: Binding<String>
    package let placeholder: String
    package let isSecure: Bool
    package let style: any TextFieldStyle
    /// Sized to its text (the placeholder when empty) instead of the proposal: grouped form rows.
    package let fitsText: Bool
    package let axis: Axis?
    package let commitsOnSubmit: Bool
    package let onEditingChanged: ((Bool) -> Void)?
    package let onCommit: (() -> Void)?

    package init(text: Binding<String>, placeholder: String, isSecure: Bool, style: any TextFieldStyle, fitsText: Bool = false,
                 axis: Axis? = nil, commitsOnSubmit: Bool = false, onEditingChanged: ((Bool) -> Void)? = nil, onCommit: (() -> Void)? = nil) {
        self.text = text
        self.placeholder = placeholder
        self.isSecure = isSecure
        self.style = style
        self.fitsText = fitsText
        self.axis = axis
        self.commitsOnSubmit = commitsOnSubmit
        self.onEditingChanged = onEditingChanged
        self.onCommit = onCommit
    }

    public typealias Body = Never

    public static func _makeNode(_ context: _NodeContext<_TextFieldCore>) -> TypedNode<_TextFieldCore> {
        TextFieldNode(context)
    }
}
