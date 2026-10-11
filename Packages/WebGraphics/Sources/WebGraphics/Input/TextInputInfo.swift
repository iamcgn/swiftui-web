/// A range of UTF-16 offsets in an input's text.
public struct TextRange: Equatable, Sendable {
    public var start: Int
    public var end: Int
    public init(start: Int, end: Int) {
        self.start = start
        self.end = end
    }
}

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
    /// Whether Return submits (a text field, single- or multi-line) rather than inserting a
    /// newline (an editor).
    public var submitsOnReturn = true
    /// Whether the scene paints the caret and selection itself (the host hides the element's).
    public var paintsCaret = false
    /// The input element's attributes: `inputmode`, `type` (a single-line field's kind),
    /// `autocomplete`, `autocapitalize`, `enterkeyhint`; `autocorrect` on or off.
    public var inputMode: String?
    public var inputType: String?
    public var autocomplete: String?
    public var autocapitalize: String?
    public var enterKeyHint: String?
    public var autocorrect = true
    /// A selection the scene sets programmatically (UTF-16 offsets); the host applies it once.
    public var selection: TextRange?
    /// How far a multi-line editor's content is scrolled (the host's textarea follows).
    public var scrollOffset: CGFloat = 0

    public init(text: String, placeholder: String, isSecure: Bool, textRect: CGRect, font: DisplayFont, isEnabled: Bool) {
        self.text = text
        self.placeholder = placeholder
        self.isSecure = isSecure
        self.textRect = textRect
        self.font = font
        self.isEnabled = isEnabled
    }
}
