// UITextView (Docs/elements/UIKit/TextView.md): a scroll view showing wrapped text, editable
// through the host's multi-line input. The geometry is UIKit's on the iPhone SE simulator
// (uikit/textview/*): the container insets (8 above and below), the 5 pt line fragment padding,
// lines on the font's pitch with the first baseline an ascender below the top inset, and
// `sizeThatFits` giving the text's used width plus the insets and the label height for the
// lines plus the insets. Attributed runs, links (attributed or detected) in iOS 26's link
// blue, a selection painted while editing, text wrapping around exclusion paths and the
// Helvetica 12 default font are measured on uikit/textview/looks.
#if os(WASI)
import WebFoundation
#else
import Foundation
#endif

/// The methods a text view's delegate implements.
@MainActor
public protocol UITextViewDelegate: UIScrollViewDelegate {
    func textViewShouldBeginEditing(_ textView: UITextView) -> Bool
    func textViewDidBeginEditing(_ textView: UITextView)
    func textViewShouldEndEditing(_ textView: UITextView) -> Bool
    func textViewDidEndEditing(_ textView: UITextView)
    func textViewDidChange(_ textView: UITextView)
    func textViewDidChangeSelection(_ textView: UITextView)
    /// A link was tapped: return false to keep UIKitWeb from opening it.
    func textView(_ textView: UITextView, shouldInteractWith URL: URL, in characterRange: NSRange, interaction: UITextItemInteraction) -> Bool
}

extension UITextViewDelegate {
    public func textViewShouldBeginEditing(_ textView: UITextView) -> Bool { true }
    public func textViewDidBeginEditing(_ textView: UITextView) {}
    public func textViewShouldEndEditing(_ textView: UITextView) -> Bool { true }
    public func textViewDidEndEditing(_ textView: UITextView) {}
    public func textViewDidChange(_ textView: UITextView) {}
    public func textViewDidChangeSelection(_ textView: UITextView) {}
    public func textView(_ textView: UITextView, shouldInteractWith URL: URL, in characterRange: NSRange, interaction: UITextItemInteraction) -> Bool { true }
}

/// How a text item was interacted with (a tap invokes the default action).
public enum UITextItemInteraction: Int, Sendable { case invokeDefaultAction = 0, presentActions, preview }

/// The kinds of data a non-editable text view turns into links; only `.link` (URLs starting
/// `http://`, `https://` or `www.`) is detected here.
public struct UIDataDetectorTypes: OptionSet, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let phoneNumber = UIDataDetectorTypes(rawValue: 1 << 0)
    public static let link = UIDataDetectorTypes(rawValue: 1 << 1)
    public static let address = UIDataDetectorTypes(rawValue: 1 << 2)
    public static let calendarEvent = UIDataDetectorTypes(rawValue: 1 << 3)
    public static let shipmentTrackingNumber = UIDataDetectorTypes(rawValue: 1 << 4)
    public static let flightNumber = UIDataDetectorTypes(rawValue: 1 << 5)
    public static let lookupSuggestion = UIDataDetectorTypes(rawValue: 1 << 6)
    public static let all = UIDataDetectorTypes(rawValue: UInt.max)
}

/// The part of a text container UIKit code touches: the padding either side of each line,
/// and the paths (in the container's coordinates: the view's inside its insets) lines flow
/// around, by their bounds: a line whose band a path crosses starts after it when it lies in
/// the left half, ends before it when in the right.
@MainActor
public final class NSTextContainer {
    public var lineFragmentPadding: CGFloat = 5 { didSet { owner?.textDidChange() } }
    public var maximumNumberOfLines = 0 { didSet { owner?.textDidChange() } }
    public var lineBreakMode: NSLineBreakMode = .byWordWrapping
    public var exclusionPaths: [UIBezierPath] = [] { didSet { owner?.textDidChange() } }
    weak var owner: UITextView?
    init() {}
}

/// A scrollable, multiline text region.
@MainActor
open class UITextView: UIScrollView, HostTextInput {
    open var text: String! = "" {
        didSet {
            if !settingAttributedText { storedAttributedText = nil }
            if text != oldValue { textDidChange() }
            if selectedRange.location + selectedRange.length > (text ?? "").utf16.count {
                selectedRange = NSRange(location: (text ?? "").utf16.count, length: 0)
            }
        }
    }
    /// Attributed text: its runs' fonts, colours and links draw as they are; `text` and `font`
    /// follow the string and its first run.
    open var attributedText: NSAttributedString! {
        get { storedAttributedText ?? NSAttributedString(string: text ?? "", attributes: [.font: resolvedFont, .foregroundColor: textColor ?? UIColor.label]) }
        set {
            storedAttributedText = newValue
            settingAttributedText = true
            text = newValue?.string ?? ""
            settingAttributedText = false
            if let first = newValue?.uniformAttributes {
                if let font = first[.font] as? UIFont { self.font = font }
                if let color = first[.foregroundColor] as? UIColor { textColor = color }
            }
            textDidChange()
        }
    }
    private var storedAttributedText: NSAttributedString?
    private var settingAttributedText = false
    /// The font; nil draws UIKit's default, Helvetica 12 (its iOS metrics: 13.8 pt lines).
    open var font: UIFont? { didSet { textDidChange() } }
    open var textColor: UIColor? = .label { didSet { setNeedsDisplay() } }
    /// The kinds of data a non-editable view shows as links.
    open var dataDetectorTypes: UIDataDetectorTypes = [] { didSet { textDidChange() } }
    /// The attributes links draw with: a `.foregroundColor` replaces the link blue.
    open var linkTextAttributes: [NSAttributedString.Key: Any] = [:] { didSet { setNeedsDisplay() } }
    /// The selection (UTF-16 offsets), painted while the view is editing.
    open var selectedRange = NSRange(location: 0, length: 0) {
        didSet {
            guard selectedRange != oldValue else { return }
            setNeedsDisplay()
            textViewDelegate?.textViewDidChangeSelection(self)
        }
    }
    /// iOS 26's link colour in a text view (uikit/textview/looks: 0/136/255).
    static let linkColor = UIColor(light: RGBA(r: 0, g: 136, b: 255), dark: RGBA(r: 10, g: 132, b: 255))
    /// The selection highlight and its handles (the highlight darkens the ground like a
    /// multiply: 194/210/231 over systemGray6, 204/221/238 over white).
    static let selectionColor = RGBA(r: 204, g: 221, b: 238)
    static let selectionHandleColor = RGBA(r: 20, g: 111, b: 225)
    open var textAlignment: NSTextAlignment = .natural { didSet { setNeedsDisplay() } }
    open var isEditable = true
    open var isSelectable = true
    open var textContainerInset = UIEdgeInsets(top: 8, left: 0, bottom: 8, right: 0) { didSet { textDidChange() } }
    public let textContainer = NSTextContainer()
    open var keyboardType: UIKeyboardType = .default
    open var returnKeyType: UIReturnKeyType = .default
    open var autocapitalizationType: UITextAutocapitalizationType = .sentences
    open var autocorrectionType: UITextAutocorrectionType = .default
    open var spellCheckingType: UITextSpellCheckingType = .default
    open var textContentType: UITextContentType?
    /// The delegate is a text view delegate too (`UITextViewDelegate` refines the scroll
    /// view's, as in UIKit).
    open override weak var delegate: (any UIScrollViewDelegate)? {
        didSet { textViewDelegate = delegate as? any UITextViewDelegate }
    }
    private weak var textViewDelegate: (any UITextViewDelegate)?

    public override init(frame: CGRect) {
        super.init(frame: frame)
        isAccessibilityElement = true
        backgroundColor = .systemBackground
        textContainer.owner = self
    }

    func textDidChange() {
        invalidateIntrinsicContentSize()
        setNeedsLayout()
        setNeedsDisplay()
    }

    // MARK: Editing

    open var isEditing: Bool { isFirstResponder }
    override open var canBecomeFirstResponder: Bool { isEditable }

    @discardableResult
    override open func becomeFirstResponder() -> Bool {
        guard !isFirstResponder else { return true }
        guard textViewDelegate?.textViewShouldBeginEditing(self) ?? true, super.becomeFirstResponder() else { return false }
        setNeedsDisplay()
        textViewDelegate?.textViewDidBeginEditing(self)
        return true
    }

    @discardableResult
    override open func resignFirstResponder() -> Bool {
        guard isFirstResponder else { return true }
        guard textViewDelegate?.textViewShouldEndEditing(self) ?? true, super.resignFirstResponder() else { return false }
        setNeedsDisplay()
        textViewDelegate?.textViewDidEndEditing(self)
        return true
    }

    override open func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)
        guard point(inside: location, with: event) else { return }
        if let (url, range) = link(at: location) {
            if textViewDelegate?.textView(self, shouldInteractWith: url, in: range, interaction: .invokeDefaultAction) ?? true {
                UIKitScene.shared.openURL?(url.absoluteString)
            }
            return
        }
        if isEditable { becomeFirstResponder() }
    }

    /// The host's input element changed the text: the selection follows the end.
    func hostDidChange(_ newText: String) {
        guard newText != text else { return }
        text = newText
        selectedRange = NSRange(location: newText.utf16.count, length: 0)
        textViewDelegate?.textViewDidChange(self)
        textViewDelegate?.textViewDidChangeSelection(self)
    }

    // MARK: Runs

    /// One run of the text with its font, colour and link.
    struct Run {
        var text: String
        var font: UIFont
        var color: UIColor?
        var link: URL?
    }

    /// The text's runs: the attributed string's (its `.font`, `.foregroundColor` and `.link`),
    /// else one in the view's font, with detected links split into runs of their own in a
    /// non-editable view.
    var runs: [Run] {
        var result: [Run] = []
        if let attributed = storedAttributedText, attributed.length > 0 {
            let utf16 = Array(attributed.string.utf16)
            attributed.enumerateAttributes(in: NSRange(location: 0, length: attributed.length), options: []) { attributes, range, _ in
                let piece = String(decoding: utf16[range.location..<min(utf16.count, range.location + range.length)], as: UTF16.self)
                let link = (attributes[.link] as? URL) ?? (attributes[.link] as? String).flatMap { URL(string: $0) }
                result.append(Run(text: piece, font: attributes[.font] as? UIFont ?? resolvedFont, color: attributes[.foregroundColor] as? UIColor, link: link))
            }
        } else if let text, !text.isEmpty {
            result = [Run(text: text, font: resolvedFont, color: nil)]
        }
        guard !isEditable, dataDetectorTypes.contains(.link) else { return result }
        return result.flatMap { run -> [Run] in
            guard run.link == nil else { return [run] }
            var pieces: [Run] = []
            var plain = ""
            for word in Self.split(run.text) {
                if let url = Self.detectedURL(in: word) {
                    if !plain.isEmpty { pieces.append(Run(text: plain, font: run.font, color: run.color)); plain = "" }
                    pieces.append(Run(text: word, font: run.font, color: run.color, link: url))
                } else {
                    plain += word
                }
            }
            if !plain.isEmpty { pieces.append(Run(text: plain, font: run.font, color: run.color)) }
            return pieces
        }
    }

    /// The text cut into words and the whitespace between them, with a URL's trailing
    /// punctuation split off.
    private static func split(_ text: String) -> [String] {
        var pieces: [String] = []
        var current = ""
        var inSpace = false
        for character in text {
            let space = character.isWhitespace || character.isNewline
            if !current.isEmpty, space != inSpace {
                pieces.append(contentsOf: splitTrailingPunctuation(current))
                current = ""
            }
            current.append(character)
            inSpace = space
        }
        if !current.isEmpty { pieces.append(contentsOf: splitTrailingPunctuation(current)) }
        return pieces
    }

    private static func splitTrailingPunctuation(_ word: String) -> [String] {
        guard detectedURL(in: word) == nil, let last = word.last, ".,;:!?)".contains(last), word.count > 1 else { return [word] }
        let head = String(word.dropLast())
        guard detectedURL(in: head) != nil else { return [word] }
        return [head, String(last)]
    }

    /// A URL when the word is one (`http://`, `https://` or `www.`, which gets `https://`).
    static func detectedURL(in word: String) -> URL? {
        let lower = word.lowercased()
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") { return word.count > 8 ? URL(string: word) : nil }
        if lower.hasPrefix("www."), word.count > 4 { return URL(string: "https://" + word) }
        return nil
    }

    /// The font whose lines are tallest among the runs: the pitch every line uses.
    var layoutFont: UIFont {
        guard storedAttributedText != nil else { return resolvedFont }
        return runs.map(\.font).max { $0.lineHeight < $1.lineHeight } ?? resolvedFont
    }

    /// Return in a multi-line input is a newline the host inserts itself.
    func hostDidSubmit() {}

    // MARK: Geometry

    var resolvedFont: UIFont { font ?? UIFont(name: "Helvetica", size: 12) ?? .systemFont(ofSize: 12) }
    private var padding: CGFloat { textContainer.lineFragmentPadding }

    /// The width lines wrap to in a view `width` wide: the insets and the padding taken off.
    func containerWidth(for width: CGFloat) -> CGFloat {
        max(0, width - textContainerInset.left - textContainerInset.right - 2 * padding)
    }

    /// The pitch between lines: the font's line height on the pixel grid (TextKit's line
    /// fragments are pixel-aligned: 20.5 for 17 pt, 15.5 for 13 pt).
    var linePitch: CGFloat { (layoutFont.lineHeight + layoutFont.leading).roundedUp(to: UIScreen.main.scale) }

    /// The lines of text at `width` (the container width: inside the insets and the padding).
    private func layout(width: CGFloat) -> TextLayout? {
        let styled = runs.map { StyledRun($0.text, font: $0.font.resolved) }
        guard !styled.isEmpty, styled.contains(where: { !$0.string.isEmpty }) else { return nil }
        if !textContainer.exclusionPaths.isEmpty { return excludedLayout(styled, width: width) }
        let limit = textContainer.maximumNumberOfLines > 0 ? textContainer.maximumNumberOfLines : nil
        return UIKitScene.shared.textEngine.layout(styled, options: Self.layoutOptions(lineLimit: limit), width: width > 0 ? width : nil)
    }

    /// A text view's lines wrap greedily: a two-line paragraph keeps its last word where it
    /// falls (uikit/textview/looks fits "…red end, a" on the first line), unlike SwiftUI's text.
    static func layoutOptions(lineLimit: Int?) -> TextLayoutOptions {
        var options = TextLayoutOptions(lineLimit: lineLimit)
        options.balancesTwoLines = false
        return options
    }

    /// Lines flowing around the exclusion paths: paragraph by paragraph, each line laid out in
    /// the band's free width (a path crossing the band from the left half pushes the line
    /// start after it, one in the right half ends the line before it; both halves taken, the
    /// wider side wins) and shifted to where it starts. Fragment positions stay relative to
    /// the usual text origin (the padding in from the inset).
    private func excludedLayout(_ styled: [StyledRun], width: CGFloat) -> TextLayout {
        let engine = UIKitScene.shared.textEngine
        let pitch = linePitch
        let padding = self.padding
        let containerWidth = width + 2 * padding
        let exclusions = textContainer.exclusionPaths.map(\.bounds)
        var lines: [TextLayout.Line] = []
        var widest: CGFloat = 0
        let limit = textContainer.maximumNumberOfLines > 0 ? textContainer.maximumNumberOfLines : Int.max
        paragraphs: for paragraph in Self.paragraphs(styled) {
            var remaining = paragraph
            repeat {
                guard lines.count < limit else { break paragraphs }
                let band = CGRect(x: 0, y: CGFloat(lines.count) * pitch, width: containerWidth, height: pitch)
                var left: CGFloat = 0
                var right = containerWidth
                for rect in exclusions where rect.intersects(band) {
                    if rect.midX < containerWidth / 2 { left = max(left, rect.maxX) } else { right = min(right, rect.minX) }
                }
                if right - left < containerWidth / 4 { left = 0; right = containerWidth }   // too little room: ignore the path
                let available = max(1, right - left - 2 * padding)
                let layout = engine.layout(remaining, options: Self.layoutOptions(lineLimit: nil), width: available)
                guard var line = layout.lines.first else { break }
                line.fragments = line.fragments.map { fragment in
                    var shifted = fragment
                    shifted.x += left
                    return shifted
                }
                line.baseline = CGFloat(lines.count) * pitch + layoutFont.ascender
                widest = max(widest, left + line.width)
                lines.append(line)
                let joined = remaining.map(\.string).joined()
                let consumed = joined.distance(from: joined.startIndex, to: min(line.range.upperBound, joined.endIndex))
                guard consumed > 0 else { break }
                remaining = Self.dropping(consumed, from: remaining)
                remaining = Self.droppingLeadingSpace(from: remaining)
            } while remaining.contains(where: { !$0.string.isEmpty })
        }
        let height = pitch * CGFloat(lines.count)
        return TextLayout(size: CGSize(width: widest, height: height), firstBaseline: layoutFont.ascender,
                          lastBaseline: lines.last?.baseline ?? 0, lines: lines)
    }

    /// The runs cut at newlines into paragraphs (the newlines dropped).
    private static func paragraphs(_ styled: [StyledRun]) -> [[StyledRun]] {
        var result: [[StyledRun]] = [[]]
        for run in styled {
            let parts = run.string.split(separator: "\n", omittingEmptySubsequences: false)
            for (index, part) in parts.enumerated() {
                if index > 0 { result.append([]) }
                if !part.isEmpty { result[result.count - 1].append(StyledRun(String(part), font: run.font)) }
            }
        }
        return result.filter { $0.contains(where: { !$0.string.isEmpty }) }
    }

    /// The runs with their first `count` characters removed.
    private static func dropping(_ count: Int, from styled: [StyledRun]) -> [StyledRun] {
        var left = count
        var result: [StyledRun] = []
        for run in styled {
            if left >= run.string.count { left -= run.string.count; continue }
            var rest = run
            rest.string = String(run.string.dropFirst(left))
            left = 0
            result.append(rest)
        }
        return result
    }

    private static func droppingLeadingSpace(from styled: [StyledRun]) -> [StyledRun] {
        var result = styled
        while let first = result.first {
            let trimmed = String(first.string.drop(while: { $0 == " " }))
            if trimmed.isEmpty { result.removeFirst(); continue }
            if trimmed.count != first.string.count { result[0].string = trimmed }
            break
        }
        return result
    }

    /// How many lines the view shows: a text view that does not scroll lays out only the lines
    /// its container holds, without an ellipsis (uikit/textview/basic `fitted`: two of three
    /// lines in 41 pt); a scrolling one shows them all.
    private var visibleLineLimit: Int? {
        guard !isScrollEnabled else { return nil }
        let available = bounds.height - textContainerInset.top - textContainerInset.bottom
        return max(1, Int((available / linePitch).rounded(.down)))
    }

    /// The lines the text makes at `width` (the recorded engine answers a wrapped request as one
    /// line of the recorded height, so a single line's count comes from that height).
    private func lineCount(of layout: TextLayout?) -> Int {
        guard let layout else { return 1 }
        let pitch = layoutFont.lineHeight + layoutFont.leading
        return layout.lines.count > 1 ? layout.lines.count : max(1, Int((layout.size.height / pitch).rounded()))
    }

    /// The text's height in a view `width` wide: the label height for the lines plus the insets.
    open func contentHeight(for width: CGFloat) -> CGFloat {
        let lines = lineCount(of: layout(width: containerWidth(for: width)))
        return layoutFont.labelHeight(lines: lines, scale: UIScreen.main.scale) + textContainerInset.top + textContainerInset.bottom
    }

    /// The used width plus the insets (not the padding) by the height for the lines at the
    /// proposed width (uikit/textview/basic `fitted`: 90.5 × 57 for "Two lines of / text").
    override open func sizeThatFits(_ size: CGSize) -> CGSize {
        let scale = UIScreen.main.scale
        let proposed = size.width > 0 && size.width < CGFloat.greatestFiniteMagnitude ? size.width : bounds.width
        let layout = layout(width: containerWidth(for: proposed))
        let used = (layout?.size.width ?? 0).roundedUp(to: scale)
        let height = layoutFont.labelHeight(lines: lineCount(of: layout), scale: scale)
        return CGSize(width: used + textContainerInset.left + textContainerInset.right,
                      height: height + textContainerInset.top + textContainerInset.bottom)
    }

    /// A scrolling text view has no intrinsic size; one that does not scroll is its content.
    override open var intrinsicContentSize: CGSize {
        guard !isScrollEnabled else { return CGSize(width: UIView.noIntrinsicMetric, height: UIView.noIntrinsicMetric) }
        return CGSize(width: UIView.noIntrinsicMetric, height: contentHeight(for: bounds.width))
    }

    override open func layoutSubviews() {
        super.layoutSubviews()
        let height = max(bounds.height, contentHeight(for: bounds.width))
        let size = CGSize(width: bounds.width, height: height)
        if contentSize != size { contentSize = size }
    }

    /// The rectangle the lines occupy at the top of the content: inside the insets and the padding.
    var textRect: CGRect {
        let width = containerWidth(for: bounds.width)
        let lines = lineCount(of: layout(width: width))
        return CGRect(x: textContainerInset.left + padding, y: textContainerInset.top, width: width,
                      height: layoutFont.labelHeight(lines: lines, scale: UIScreen.main.scale))
    }

    /// The first baseline: the top inset plus the ascender, rounded up to the pixel (24.5 for
    /// 17 pt under the 8 pt inset).
    var firstBaseline: CGFloat { (textContainerInset.top + layoutFont.ascender).roundedUp(to: UIScreen.main.scale) }

    override func textBaselines(in size: CGSize) -> (first: CGFloat, last: CGFloat) {
        let lines = lineCount(of: layout(width: containerWidth(for: size.width)))
        return (firstBaseline, firstBaseline + linePitch * CGFloat(lines - 1))
    }

    // MARK: Painting

    /// The horizontal inset a line's alignment gives it.
    private func alignmentInset(_ line: TextLayout.Line, in width: CGFloat) -> CGFloat {
        switch textAlignment {
        case .center: return (width - line.inkWidth) / 2
        case .right: return width - line.inkWidth
        default: return 0
        }
    }

    /// The lines drawn: a non-scrolling view shows only those its container holds.
    private func visibleLines(_ layout: TextLayout) -> [TextLayout.Line] {
        visibleLineLimit.map { Array(layout.lines.prefix($0)) } ?? layout.lines
    }

    /// The width of the first `count` characters of a line's runs (the selection's edges).
    private func width(ofFirst count: Int, in line: TextLayout.Line, runs: [Run]) -> CGFloat {
        guard count > 0 else { return 0 }
        var styled: [StyledRun] = []
        var left = count
        for fragment in line.fragments {
            guard left > 0 else { break }
            let piece = String(fragment.text.prefix(left))
            left -= piece.count
            let font = runs.indices.contains(fragment.run) ? runs[fragment.run].font : layoutFont
            styled.append(StyledRun(piece, font: font.resolved))
        }
        guard !styled.isEmpty else { return 0 }
        return UIKitScene.shared.textEngine.layout(styled, options: .default, width: nil).size.width
    }

    /// The highlight rectangles of the selection (view coordinates) with the lines they are on.
    func selectionRects() -> [CGRect] {
        guard selectedRange.length > 0, let layout = layout(width: textRect.width) else { return [] }
        let runs = runs
        let rect = textRect
        let pitch = linePitch
        let utf16 = Array((text ?? "").utf16)
        var result: [CGRect] = []
        var lineStart = 0   // characters before the line
        let characters = Array(text ?? "")
        let selectionStart = String(decoding: utf16.prefix(selectedRange.location), as: UTF16.self).count
        let selectionEnd = String(decoding: utf16.prefix(selectedRange.location + selectedRange.length), as: UTF16.self).count
        for (index, line) in visibleLines(layout).enumerated() {
            let shown = line.fragments.reduce(0) { $0 + $1.text.count }
            let lineEnd = lineStart + shown
            // The characters between lines (a space or newline the line does not show).
            var next = lineEnd
            while next < characters.count, characters[next] == " " || characters[next] == "\n" { next += 1 }
            defer { lineStart = next }
            let from = max(selectionStart, lineStart)
            let to = min(selectionEnd, lineEnd)
            guard from < to || (selectionStart <= lineStart && selectionEnd > lineEnd) else { continue }
            let inset = alignmentInset(line, in: rect.width)
            let origin = rect.minX + inset + (line.fragments.first?.x ?? 0)
            let x0 = width(ofFirst: max(0, from - lineStart), in: line, runs: runs)
            let x1 = width(ofFirst: max(0, to - lineStart), in: line, runs: runs)
            // The highlight starts a point above the line's band (347 for the band at 348).
            let top = textContainerInset.top + pitch * CGFloat(index)
            result.append(CGRect(x: origin + x0, y: top - 1, width: max(0, x1 - x0), height: pitch + 1))
        }
        return result
    }

    /// The link under a point in the view, with its character range.
    func link(at point: CGPoint) -> (URL, NSRange)? {
        guard let layout = layout(width: textRect.width) else { return nil }
        let runs = runs
        let rect = textRect
        let pitch = linePitch
        var offset = 0
        var runStarts: [Int] = []
        for run in runs { runStarts.append(offset); offset += run.text.utf16.count }
        for (index, line) in visibleLines(layout).enumerated() {
            let top = textContainerInset.top + pitch * CGFloat(index)
            guard point.y >= top, point.y < top + pitch else { continue }
            let inset = alignmentInset(line, in: rect.width)
            for fragment in line.fragments where runs.indices.contains(fragment.run) {
                let run = runs[fragment.run]
                guard let url = run.link else { continue }
                let x = rect.minX + inset + fragment.x
                if point.x >= x, point.x < x + fragment.width {
                    return (url, NSRange(location: runStarts[fragment.run], length: run.text.utf16.count))
                }
            }
        }
        return nil
    }

    override func drawContent(into list: inout DisplayList, context: PaintContext, style: UIUserInterfaceStyle) {
        let rect = textRect
        guard let layout = layout(width: rect.width), !layout.lines.isEmpty else { return }
        let runs = runs
        let pitch = linePitch
        let color = (textColor ?? .label).rgba(for: style)
        let linkColor = (linkTextAttributes[.foregroundColor] as? UIColor ?? Self.linkColor).rgba(for: style)
        let selection = isFirstResponder ? selectionRects() : []
        for highlight in selection {
            list.append(.fillRect(context.absoluteRect(highlight), Self.selectionColor))
        }
        for (index, line) in visibleLines(layout).enumerated() {
            let baseline = context.origin.y + firstBaseline + pitch * CGFloat(index)
            let inset = alignmentInset(line, in: rect.width)
            for fragment in line.fragments where !fragment.text.isEmpty {
                let run = runs.indices.contains(fragment.run) ? runs[fragment.run] : Run(text: "", font: layoutFont, color: nil)
                let fragmentColor = run.link != nil ? linkColor : (run.color?.rgba(for: style) ?? color)
                list.append(.drawText(fragment.text, DisplayFont(run.font.resolved), origin: CGPoint(x: context.origin.x + rect.minX + inset + fragment.x, y: baseline), fragmentColor))
            }
        }
        // The selection's handles: 2 pt bars at its ends with 10 pt knobs, the start's above
        // and the end's below.
        if let first = selection.first, let last = selection.last {
            let handle = Self.selectionHandleColor
            let startBar = context.absoluteRect(CGRect(x: first.minX - 1, y: first.minY, width: 2, height: first.height))
            let endBar = context.absoluteRect(CGRect(x: last.maxX - 1, y: last.minY, width: 2, height: last.height))
            list.append(.fillRect(startBar, handle))
            list.append(.fillRect(endBar, handle))
            list.append(.fillPath(Path(ellipseIn: CGRect(x: startBar.midX - 5, y: startBar.minY - 10, width: 10, height: 10)), handle))
            list.append(.fillPath(Path(ellipseIn: CGRect(x: endBar.midX - 5, y: endBar.maxY, width: 10, height: 10)), handle))
        }
    }

    // MARK: Semantics

    override func decorateSemantics(_ node: inout SemanticsNode) {
        node.role = .textField
        let font = resolvedFont
        var info = TextInputInfo(text: text ?? "", placeholder: "", isSecure: false, textRect: convert(textRect, to: nil),
                                 font: DisplayFont(font.resolved), isEnabled: isEditable)
        info.isMultiline = true
        info.lineHeight = linePitch
        info.firstBaseline = firstBaseline - textContainerInset.top
        info.inputMode = keyboardType.inputMode
        info.autocomplete = textContentType?.rawValue
        info.autocapitalize = autocapitalizationType.token
        info.enterKeyHint = returnKeyType.enterKeyHint
        info.autocorrect = autocorrectionType != .no
        node.textInput = info
    }
}

/// A view the host types into: the text field and the text view.
@MainActor
protocol HostTextInput: UIView {
    func hostDidChange(_ newText: String)
    func hostDidSubmit()
}

extension UITextField: HostTextInput {}
