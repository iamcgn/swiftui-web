/// What a host needs to place and drive a real input element over a text field.
public struct TextInputInfo: Equatable, Sendable {
    /// The field's text and placeholder.
    public var text: String
    public var placeholder: String
    public var isSecure: Bool
    /// The rectangle the text occupies (window coordinates): the input goes there.
    public var textRect: CGRect
    public var font: DisplayFont
    public var isEnabled: Bool
    /// A multi-line editor: the host gives it a multi-line input and Return inserts a newline.
    public var isMultiline = false
    /// The editor's distance between baselines and its first baseline below the text rect's
    /// top (0 for a single-line field, whose text line is the rect).
    public var lineHeight: CGFloat = 0
    public var firstBaseline: CGFloat = 0

    public init(text: String, placeholder: String, isSecure: Bool, textRect: CGRect, font: DisplayFont, isEnabled: Bool) {
        self.text = text
        self.placeholder = placeholder
        self.isSecure = isSecure
        self.textRect = textRect
        self.font = font
        self.isEnabled = isEnabled
    }
}
