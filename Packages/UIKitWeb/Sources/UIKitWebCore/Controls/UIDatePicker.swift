// UIDatePicker (Docs/elements/UIKit/DatePicker.md): the compact style's capsules ("Sep 11, 2026"
// and "2:30 PM" in 17 pt on the tertiary fill with 8 pt corners, 12 in and 7 down) and the
// wheels style's three columns. Geometry from UIKit on the iPhone SE simulator (iOS 26).
#if os(WASI)
import FoundationEssentials
#else
import Foundation
#endif

/// The date picker's presentation style.
public enum UIDatePickerStyle: Int, Sendable { case automatic = 0, wheels, compact, inline }

/// A control for inputting date and time values.
@MainActor
open class UIDatePicker: UIControl {
    public enum Mode: Int, Sendable { case time = 0, date, dateAndTime, countDownTimer }

    open var date = Date() { didSet { setNeedsDisplay(); invalidateIntrinsicContentSize() } }
    open var datePickerMode: Mode = .dateAndTime { didSet { invalidateIntrinsicContentSize(); setNeedsDisplay() } }
    open var preferredDatePickerStyle: UIDatePickerStyle = .automatic { didSet { invalidateIntrinsicContentSize(); setNeedsDisplay() } }
    /// The style in use: `automatic` resolves to the compact style (a count-down timer to wheels).
    open var datePickerStyle: UIDatePickerStyle {
        if preferredDatePickerStyle == .automatic { return datePickerMode == .countDownTimer ? .wheels : .compact }
        return preferredDatePickerStyle
    }
    open var minimumDate: Date?
    open var maximumDate: Date?
    open var minuteInterval = 1
    open var countDownDuration: TimeInterval = 0
    open var roundsToMinuteInterval = true
    open var calendar = Calendar(identifier: .gregorian)
    open var locale: Locale?
    open var timeZone: TimeZone?

    public override init(frame: CGRect) {
        super.init(frame: frame)
        isAccessibilityElement = true
    }

    open func setDate(_ date: Date, animated: Bool) { self.date = date }

    // MARK: Formatting (en_US: "Sep 11, 2026", "2:30 PM" with a narrow no-break space)

    static let monthAbbreviations = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    static let monthNames = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]

    private var components: DateComponents {
        var calendar = self.calendar
        if let timeZone { calendar.timeZone = timeZone }
        return calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
    }

    /// "Sep 11, 2026"
    var dateText: String {
        let c = components
        return "\(Self.monthAbbreviations[max(0, min(11, (c.month ?? 1) - 1))]) \(c.day ?? 1), \(c.year ?? 1)"
    }

    /// "2:30 PM"
    var timeText: String {
        let c = components
        let hour = c.hour ?? 0
        let minute = c.minute ?? 0
        let twelve = hour % 12 == 0 ? 12 : hour % 12
        let minutes = minute < 10 ? "0\(minute)" : "\(minute)"
        return "\(twelve):\(minutes)\u{202F}\(hour < 12 ? "AM" : "PM")"
    }

    // MARK: Compact geometry (uikit/datepicker/compact)

    static let capsuleCorner: CGFloat = 8
    static let capsuleInset: CGFloat = 12
    static let capsuleGap: CGFloat = 4
    private var font: UIFont { .systemFont(ofSize: 17) }

    private func labelWidth(_ text: String) -> CGFloat {
        let layout = UIKitScene.shared.textEngine.layout([StyledRun(text, font: font.resolved)], options: TextLayoutOptions(lineLimit: 1), width: nil)
        return layout.size.width.roundedUp(to: UIScreen.main.scale)
    }

    private var showsDate: Bool { datePickerMode == .date || datePickerMode == .dateAndTime }
    private var showsTime: Bool { datePickerMode == .time || datePickerMode == .dateAndTime }

    /// The date capsule is its label plus 24 wide; the time capsule too. A date-only picker is
    /// 38.5 tall (a 24.5 pt label 7 down); one with a time capsule is 40 (the time label is 26 tall).
    private var dateCapsuleWidth: CGFloat { labelWidth(dateText) + 2 * Self.capsuleInset }
    /// The time label uses monospaced digits, each as wide as a zero (86.5 for "2:30 PM", not
    /// 86): the text stack has no tabular figures, so the width is measured with zeros.
    private var timeCapsuleWidth: CGFloat { labelWidth(Self.tabular(timeText)) + 2 * Self.capsuleInset }

    static func tabular(_ text: String) -> String {
        String(text.map { $0.isNumber ? "0" : $0 })
    }
    private var compactHeight: CGFloat { showsTime ? 40 : 38.5 }

    /// A compact picker fits both capsules whatever its mode (223.5 for 11 September 2026,
    /// 11:30: 122 + 4 + 97.5), the capsules right-aligned; a wheels picker is 320 × 216. iOS 26
    /// sizes a date-only or time-only picker's hidden capsule for the current time instead
    /// (the fixture pins those widths); the picker's own time stands in for it here.
    override open func sizeThatFits(_ size: CGSize) -> CGSize {
        switch datePickerStyle {
        case .wheels: return CGSize(width: 320, height: 216)
        case .inline: return CGSize(width: 320, height: 320)
        default: return CGSize(width: dateCapsuleWidth + Self.capsuleGap + timeCapsuleWidth, height: compactHeight)
        }
    }

    override open var intrinsicContentSize: CGSize { sizeThatFits(.zero) }

    /// The capsules' rectangles: the time capsule ends at the trailing edge, the date capsule 4 before it.
    private var capsules: [(rect: CGRect, text: String)] {
        var result: [(CGRect, String)] = []
        var right = bounds.width
        if showsTime {
            let width = timeCapsuleWidth
            result.append((CGRect(x: right - width, y: 0, width: width, height: compactHeight), timeText))
            right -= width + Self.capsuleGap
        }
        if showsDate {
            let width = dateCapsuleWidth
            result.append((CGRect(x: right - width, y: 0, width: width, height: compactHeight), dateText))
        }
        return result
    }

    // MARK: Painting

    override func drawContent(into list: inout DisplayList, context: PaintContext, style: UIUserInterfaceStyle) {
        switch datePickerStyle {
        case .wheels, .inline: drawWheels(into: &list, context: context, style: style)
        default: drawCompact(into: &list, context: context, style: style)
        }
    }

    private func drawCompact(into list: inout DisplayList, context: PaintContext, style: UIUserInterfaceStyle) {
        let fill = UIColor.tertiarySystemFill.rgba(for: style)
        let ink = UIColor.label.rgba(for: style)
        let displayFont = DisplayFont(font.resolved)
        let scale = UIScreen.main.scale
        for capsule in capsules {
            let rect = context.absoluteRect(capsule.rect)
            if isEnabled { list.append(.fillRRect(rect, cornerRadius: Self.capsuleCorner, fill)) }
            // The label sits 7 down; its line box is the label's height (24.5 or 26), the text centred in it.
            let labelHeight = compactHeight - 14
            let top = 7 + ((labelHeight - font.lineHeight) / 2).rounded()
            let baseline = rect.minY + top + (font.ascender * scale).rounded() / scale
            let layout = UIKitScene.shared.textEngine.layout([StyledRun(capsule.text, font: font.resolved)], options: TextLayoutOptions(lineLimit: 1), width: nil)
            for line in layout.lines.prefix(1) {
                for fragment in line.fragments {
                    list.append(.drawText(fragment.text, displayFont, origin: CGPoint(x: rect.minX + Self.capsuleInset + fragment.x, y: baseline), ink))
                }
            }
        }
    }

    /// The wheels: three columns (month, day, year) of 21 pt rows on a 32 pt pitch, the selected
    /// row over a rounded band, the rows above and below shrinking and fading as on a drum
    /// (approximate: the frame is pinned, the pixels are not).
    private func drawWheels(into list: inout DisplayList, context: PaintContext, style: UIUserInterfaceStyle) {
        let bounds = context.absoluteRect(CGRect(origin: .zero, size: self.bounds.size))
        let c = components
        let month = max(1, min(12, c.month ?? 1))
        let day = c.day ?? 1
        let year = c.year ?? 2000
        let columns: [WheelPainter.Column] = [
            WheelPainter.Column(centre: bounds.minX + 96, rows: { offset in let m = month + offset; return (1...12).contains(m) ? Self.monthNames[m - 1] : nil }),
            WheelPainter.Column(centre: bounds.minX + 200, rows: { offset in let d = day + offset; return (1...31).contains(d) ? "\(d)" : nil }),
            WheelPainter.Column(centre: bounds.minX + 272, rows: { offset in "\(year + offset)" }),
        ]
        WheelPainter.paint(columns: columns, in: bounds, style: style, into: &list)
    }

    // MARK: Semantics

    override func decorateSemantics(_ node: inout SemanticsNode) {
        node.role = .button
        let parts = [showsDate ? dateText : nil, showsTime ? timeText : nil].compactMap { $0 }
        if node.label.isEmpty { node.label = parts.joined(separator: " ") }
    }
}

/// The drum a wheels picker draws: a selection band across the middle and, per column, the rows
/// around the selected one on a 32 pt pitch, shrinking and fading with the angle
/// (approximate: UIKit renders a real cylinder).
@MainActor
enum WheelPainter {
    struct Column {
        let centre: CGFloat
        /// The text `offset` rows from the selected one (nil past the ends).
        let rows: (Int) -> String?
    }

    static let rowPitch: CGFloat = 32
    static let fontSize: CGFloat = 21

    static func paint(columns: [Column], in bounds: CGRect, style: UIUserInterfaceStyle, into list: inout DisplayList) {
        let band = CGRect(x: bounds.minX + 13, y: bounds.midY - rowPitch / 2, width: bounds.width - 26, height: rowPitch)
        list.append(.fillRRect(band, cornerRadius: 8, UIColor.tertiarySystemFill.rgba(for: style)))
        list.withSavedState { list in
            list.append(.clipRect(bounds))
            for column in columns {
                for offset in -3...3 {
                    guard let text = column.rows(offset) else { continue }
                    let angle = Double(offset) * 0.32
                    let scale = CGFloat(_cos(angle))
                    let y = bounds.midY + CGFloat(_sin(angle)) * bounds.height / 2
                    let font = UIFont.systemFont(ofSize: fontSize * scale)
                    let layout = UIKitScene.shared.textEngine.layout([StyledRun(text, font: font.resolved)], options: TextLayoutOptions(lineLimit: 1), width: nil)
                    guard let line = layout.lines.first else { continue }
                    let alpha = offset == 0 ? 1 : max(0.25, 0.75 - 0.15 * Double(abs(offset)))
                    let ink = (offset == 0 ? UIColor.label : UIColor.secondaryLabel).rgba(for: style).multiplyingAlpha(by: alpha)
                    let x = column.centre - line.inkWidth / 2
                    let baseline = y + font.ascender - font.lineHeight / 2
                    for fragment in line.fragments {
                        list.append(.drawText(fragment.text, DisplayFont(font.resolved), origin: CGPoint(x: x + fragment.x, y: baseline), ink))
                    }
                }
            }
        }
    }
}
