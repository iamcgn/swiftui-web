// The accessibility tree a scene exposes to its host.

/// One element of the accessibility tree hosts expose (DOM overlay in the browser).
public struct SemanticsNode: Equatable, Sendable {
    public enum Role: String, Sendable {
        case button, checkbox, textField
        case text, heading, image, group, link
        case `switch`, slider, stepper, popUpButton, radioGroup, segmented
        /// A list with a selection: a focusable listbox whose rows are their own elements.
        case list
    }
    public var role: Role
    public var label: String
    public var frame: CGRect
    public var identifier: Int
    /// The state of a checkbox or switch.
    public var isOn: Bool?
    /// What a text field's input element shows and where.
    public var textInput: TextInputInfo?
    /// A description of the element's value (`accessibilityValue`, a slider's percentage).
    public var value: String?
    /// What happens on activation (`accessibilityHint`).
    public var hint: String?
    /// The developer identifier (`accessibilityIdentifier`).
    public var accessibilityIdentifier: String?
    /// A slider's range and current value, for `<input type=range>`.
    public var range: SemanticsRange?
    /// Whether the element can be incremented and decremented (steppers, sliders).
    public var isAdjustable = false
    /// Whether a static-looking element takes keyboard focus (`focusable` views, lists).
    public var isFocusable = false

    public init(role: Role, label: String, frame: CGRect, identifier: Int, isOn: Bool? = nil, textInput: TextInputInfo? = nil) {
        self.role = role
        self.label = label
        self.frame = frame
        self.identifier = identifier
        self.isOn = isOn
        self.textInput = textInput
    }
}

public struct SemanticsRange: Equatable, Sendable {
    public var minimum: Double, maximum: Double, value: Double, step: Double?
    public init(minimum: Double, maximum: Double, value: Double, step: Double? = nil) {
        self.minimum = minimum; self.maximum = maximum; self.value = value; self.step = step
    }
}
