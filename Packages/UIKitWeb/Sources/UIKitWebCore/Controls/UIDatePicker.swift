// UIDatePicker (Docs/elements/UIKit/DatePicker.md): the compact style's capsules ("Sep 11, 2026"
// and "11:30 AM" in 17 pt on the tertiary fill with 8 pt corners, 12 in and 7 down), the inline
// style's calendar (Controls/UICalendarView.swift) with its time row, the wheels (date, time and
// the count-down timer) and the popovers a compact picker presents. Geometry from UIKit on the
// iPhone SE simulator (iOS 26).
#if os(WASI)
import WebFoundation
#else
import Foundation
#endif

/// The date picker's presentation style.
public enum UIDatePickerStyle: Int, Sendable { case automatic = 0, wheels, compact, inline }

/// A control for inputting date and time values.
@MainActor
open class UIDatePicker: UIControl {
    public enum Mode: Int, Sendable { case time = 0, date, dateAndTime, countDownTimer }

    /// The date, kept between `minimumDate` and `maximumDate` as UIKit keeps it.
    open var date: Date {
        get { _date }
        set { _date = clamped(newValue); setNeedsDisplay(); invalidateIntrinsicContentSize() }
    }
    private var _date = Date()
    open var datePickerMode: Mode = .dateAndTime { didSet { invalidateIntrinsicContentSize(); setNeedsDisplay() } }
    open var preferredDatePickerStyle: UIDatePickerStyle = .automatic { didSet { invalidateIntrinsicContentSize(); setNeedsDisplay() } }
    /// The style in use: `automatic` resolves to the compact style, a count-down timer to the
    /// wheels, and an inline time-only picker to the compact capsule.
    open var datePickerStyle: UIDatePickerStyle {
        if datePickerMode == .countDownTimer { return .wheels }
        if preferredDatePickerStyle == .automatic || (preferredDatePickerStyle == .inline && datePickerMode == .time) { return .compact }
        return preferredDatePickerStyle
    }
    open var minimumDate: Date? { didSet { _date = clamped(_date); setNeedsDisplay() } }
    open var maximumDate: Date? { didSet { _date = clamped(_date); setNeedsDisplay() } }
    open var minuteInterval = 1 { didSet { setNeedsDisplay() } }
    open var countDownDuration: TimeInterval = 0 { didSet { setNeedsDisplay() } }
    open var roundsToMinuteInterval = true
    open var calendar = Calendar(identifier: .gregorian) { didSet { setNeedsDisplay() } }
    open var locale: Locale? { didSet { invalidateIntrinsicContentSize(); setNeedsDisplay() } }
    open var timeZone: TimeZone? { didSet { setNeedsDisplay() } }

    public override init(frame: CGRect) {
        super.init(frame: frame)
        isAccessibilityElement = true
    }

    open func setDate(_ date: Date, animated: Bool) { self.date = date }

    private func clamped(_ date: Date) -> Date {
        var date = date
        if let minimumDate, date < minimumDate { date = minimumDate }
        if let maximumDate, date > maximumDate { date = maximumDate }
        return date
    }

    // MARK: Formatting ("Sep 11, 2026", "11:30 AM" with a narrow no-break space; other locales
    // per DatePickerStrings)

    var strings: DatePickerStrings { .resolve(locale) }

    var calendarInZone: Calendar {
        var calendar = self.calendar
        if let timeZone { calendar.timeZone = timeZone }
        return calendar
    }

    private var components: DateComponents {
        calendarInZone.dateComponents([.year, .month, .day, .hour, .minute], from: date)
    }

    /// "Sep 11, 2026"
    var dateText: String {
        let c = components
        return strings.date(year: c.year ?? 1, month: c.month ?? 1, day: c.day ?? 1)
    }

    /// "9/11/26": what the date capsule shows when the long date does not fit the frame.
    var shortDateText: String {
        let c = components
        return strings.shortDate(year: c.year ?? 1, month: c.month ?? 1, day: c.day ?? 1)
    }

    /// "11:30 AM"
    var timeText: String {
        let c = components
        return strings.time(hour: c.hour ?? 0, minute: c.minute ?? 0)
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
    private var shortDateCapsuleWidth: CGFloat { labelWidth(shortDateText) + 2 * Self.capsuleInset }
    /// The time label uses monospaced digits, each as wide as a zero (86.5 for "2:30 PM", not
    /// 86): the text stack has no tabular figures, so the width is measured with zeros.
    private var timeCapsuleWidth: CGFloat { labelWidth(Self.tabular(timeText)) + 2 * Self.capsuleInset }

    static func tabular(_ text: String) -> String {
        String(text.map { $0.isNumber ? "0" : $0 })
    }
    private var compactHeight: CGFloat { showsTime ? 40 : 38.5 }

    /// A compact picker fits both capsules whatever its mode (223.5 for 11 September 2026,
    /// 11:30: 122 + 4 + 97.5), the capsules right-aligned; a wheels picker is 320 × 216; an
    /// inline picker is 320 wide and as tall as its calendar (327.5 for a five-week month, 46
    /// more with the time row). iOS 26 sizes a compact picker's capsules for the current date
    /// and time instead (the fixture pins those widths); the picker's own date stands in here.
    override open func sizeThatFits(_ size: CGSize) -> CGSize {
        switch datePickerStyle {
        case .wheels: return CGSize(width: 320, height: 216)
        case .inline: return CGSize(width: Self.inlineWidth, height: inlineGrid(width: Self.inlineWidth).height + (showsTime ? Self.inlineTimeRowHeight : 0))
        default: return CGSize(width: dateCapsuleWidth + Self.capsuleGap + timeCapsuleWidth, height: compactHeight)
        }
    }

    override open var intrinsicContentSize: CGSize { sizeThatFits(.zero) }

    /// The capsules' rectangles: the time capsule ends at the trailing edge, the date capsule 4
    /// before it; when the long date would not fit the frame the capsule shows the numeric date.
    private func capsules(in bounds: CGRect) -> [(rect: CGRect, text: String, kind: CapsuleKind)] {
        var result: [(CGRect, String, CapsuleKind)] = []
        var right = bounds.maxX
        let top = bounds.minY
        if showsTime {
            let width = timeCapsuleWidth
            result.append((CGRect(x: right - width, y: top, width: width, height: compactHeight), timeText, .time))
            right -= width + Self.capsuleGap
        }
        if showsDate {
            let fits = dateCapsuleWidth <= right - bounds.minX
            let width = fits ? dateCapsuleWidth : shortDateCapsuleWidth
            result.append((CGRect(x: right - width, y: top, width: width, height: compactHeight), fits ? dateText : shortDateText, .date))
        }
        return result
    }

    enum CapsuleKind { case date, time }

    // MARK: Inline geometry (uikit/datepicker/inline, uikit/datepicker/inline-time)

    static let inlineWidth: CGFloat = 320
    static let inlineRowHeight: CGFloat = 45.5
    /// The time row under the calendar: a 17 pt semibold "Time" 16 in (its label 8 down, 24.5
    /// tall) and the time capsule 16 from the trailing edge, 6 below the grid, 10 above the bottom.
    static let inlineTimeRowHeight: CGFloat = 46

    /// The picker's calendar is 8 narrower than the picker, its header as wide.
    func inlineGrid(width: CGFloat) -> CalendarGrid {
        let c = components
        return CalendarGrid(calendar: calendarInZone, year: c.year ?? 2000, month: c.month ?? 1, layoutWidth: width, gridWidth: width - 8, rowHeight: Self.inlineRowHeight, strings: strings)
    }

    /// The month the inline calendar shows: the date's until the chevrons page away from it.
    private var visibleMonth: (year: Int, month: Int)?

    private var inlineCalendarGrid: CalendarGrid {
        var grid = inlineGrid(width: bounds.width)
        if let visibleMonth { grid = CalendarGrid(calendar: grid.calendar, year: visibleMonth.year, month: visibleMonth.month, layoutWidth: grid.layoutWidth, gridWidth: grid.gridWidth, rowHeight: grid.rowHeight, strings: grid.strings) }
        return grid
    }

    private func isAvailable(_ day: DateComponents) -> Bool {
        var components = day
        let c = self.components
        components.hour = c.hour
        components.minute = c.minute
        guard let candidate = calendarInZone.date(from: components) else { return false }
        if let minimumDate, calendarInZone.startOfDay(for: candidate) < calendarInZone.startOfDay(for: minimumDate) { return false }
        if let maximumDate, calendarInZone.startOfDay(for: candidate) > calendarInZone.startOfDay(for: maximumDate) { return false }
        return true
    }

    private func pageInline(by months: Int) {
        let grid = inlineCalendarGrid
        guard let first = calendarInZone.date(from: DateComponents(year: grid.year, month: grid.month, day: 1)),
              let target = calendarInZone.date(byAdding: .month, value: months, to: first) else { return }
        visibleMonth = (calendarInZone.component(.year, from: target), calendarInZone.component(.month, from: target))
        invalidateIntrinsicContentSize()
        setNeedsDisplay()
    }

    private func selectInline(day: Int) {
        let grid = inlineCalendarGrid
        let c = components
        var components = DateComponents(year: grid.year, month: grid.month, day: day)
        guard isAvailable(components) else { return }
        components.hour = c.hour
        components.minute = c.minute
        guard let selected = calendarInZone.date(from: components) else { return }
        visibleMonth = nil
        date = selected
        sendActions(for: .valueChanged)
    }

    // MARK: Painting

    override func drawContent(into list: inout DisplayList, context: PaintContext, style: UIUserInterfaceStyle) {
        switch datePickerStyle {
        case .wheels: drawWheels(into: &list, context: context, style: style)
        case .inline: drawInline(into: &list, context: context, style: style)
        default: drawCompact(capsules(in: CGRect(origin: .zero, size: bounds.size)), into: &list, context: context, style: style)
        }
    }

    private func drawCompact(_ capsules: [(rect: CGRect, text: String, kind: CapsuleKind)], into list: inout DisplayList, context: PaintContext, style: UIUserInterfaceStyle) {
        let fill = UIColor.tertiarySystemFill.rgba(for: style)
        let ink = UIColor.label.rgba(for: style)
        let scale = UIScreen.main.scale
        for capsule in capsules {
            let rect = context.absoluteRect(capsule.rect)
            if isEnabled { list.append(.fillRRect(rect, cornerRadius: Self.capsuleCorner, fill)) }
            // The label sits 7 down; its line box is the label's height (24.5 or 26), the text
            // centred in it. The time is set in tabular figures (the width was measured with zeros).
            let font = capsule.kind == .time ? UIFont.monospacedDigitSystemFont(ofSize: 17, weight: .regular) : self.font
            let labelHeight = compactHeight - 14
            let top = 7 + ((labelHeight - font.lineHeight) / 2).rounded()
            let baseline = rect.minY + top + (font.ascender * scale).rounded() / scale
            let layout = UIKitScene.shared.textEngine.layout([StyledRun(capsule.text, font: font.resolved)], options: TextLayoutOptions(lineLimit: 1), width: nil)
            for line in layout.lines.prefix(1) {
                for fragment in line.fragments {
                    list.append(.drawText(fragment.text, DisplayFont(font.resolved), origin: CGPoint(x: rect.minX + Self.capsuleInset + fragment.x, y: baseline), ink))
                }
            }
        }
    }

    /// The inline style: the calendar grid and, with a time component, the time row under it.
    private func drawInline(into list: inout DisplayList, context: PaintContext, style: UIUserInterfaceStyle) {
        let grid = inlineCalendarGrid
        let origin = context.absoluteRect(CGRect(origin: .zero, size: bounds.size)).origin
        let tint = tintColor.rgba(for: style)
        let c = components
        CalendarPainter.paint(grid, at: origin, tint: tint, style: style,
                              isEnabled: { [weak self] day in self?.isAvailable(day) ?? true },
                              isSelected: { day in day.year == c.year && day.month == c.month && day.day == c.day },
                              decoration: { _ in nil },
                              canPageBack: canPageInline(by: -1), canPageForward: canPageInline(by: 1), into: &list)
        guard showsTime else { return }
        let rowTop = grid.height - CalendarGrid.bottomInset + 6
        CalendarPainter.drawText("Time", font: .systemFont(ofSize: 17, weight: .semibold), color: UIColor.label.rgba(for: style),
                                 at: CGPoint(x: origin.x + 16, y: origin.y + rowTop + 20.25), centred: false, into: &list)
        let width = timeCapsuleWidth
        drawCompact([(CGRect(x: bounds.width - 16 - width, y: rowTop, width: width, height: 40), timeText, .time)], into: &list, context: context, style: style)
    }

    private func canPageInline(by months: Int) -> Bool {
        let grid = inlineCalendarGrid
        guard let first = calendarInZone.date(from: DateComponents(year: grid.year, month: grid.month, day: 1)),
              let target = calendarInZone.date(byAdding: .month, value: months, to: first) else { return false }
        if months < 0, let minimumDate {
            guard let next = calendarInZone.date(byAdding: .month, value: 1, to: target) else { return false }
            return next > calendarInZone.startOfDay(for: minimumDate)
        }
        if months > 0, let maximumDate { return target <= maximumDate }
        return true
    }

    /// The wheels: three columns (month, day, year) of 21 pt rows on a 32 pt pitch, the selected
    /// row over a rounded band, the rows above and below shrinking and fading as on a drum
    /// (approximate: the frame is pinned, the pixels are not). A time picker shows hours,
    /// minutes and the period; the count-down timer hours and minutes with their unit labels.
    private func drawWheels(into list: inout DisplayList, context: PaintContext, style: UIUserInterfaceStyle) {
        let bounds = context.absoluteRect(CGRect(origin: .zero, size: self.bounds.size))
        WheelPainter.paint(columns: wheelColumns.map { column in
            WheelPainter.Column(centre: bounds.minX + column.centre, rows: column.rows, label: column.label.map { (bounds.minX + $0.x, $0.text) })
        }, in: bounds, style: style, into: &list)
    }

    /// A wheel column: its centre, the text `offset` rows from the selected one, a unit label
    /// after it, and how a drag by `rows` changes the value.
    struct WheelColumn {
        let centre: CGFloat
        let rows: (Int) -> String?
        var label: (x: CGFloat, text: String)? = nil
        let spin: (Int) -> Void
    }

    private var wheelColumns: [WheelColumn] {
        let strings = self.strings
        switch datePickerMode {
        case .countDownTimer:
            let total = Int(countDownDuration / 60)
            let hours = total / 60, minutes = total % 60
            let interval = max(1, minuteInterval)
            return [
                WheelColumn(centre: 99, rows: { offset in let h = hours + offset; return (0...23).contains(h) ? "\(h)" : nil },
                            label: (114, hours == 1 ? "hour" : "hours"), spin: { [weak self] rows in
                                guard let self else { return }
                                let h = max(0, min(23, hours + rows))
                                self.countDownDuration = TimeInterval((h * 60 + minutes) * 60)
                            }),
                WheelColumn(centre: 177.5, rows: { offset in let m = minutes + offset * interval; return (0...59).contains(m) ? "\(m)" : nil },
                            label: (199, "min"), spin: { [weak self] rows in
                                guard let self else { return }
                                let m = max(0, min(59, minutes + rows * interval))
                                self.countDownDuration = TimeInterval((hours * 60 + m) * 60)
                            }),
            ]
        case .time, .dateAndTime:
            let c = components
            let hour = c.hour ?? 0, minute = c.minute ?? 0
            let interval = max(1, minuteInterval)
            if strings.uses24Hour {
                return [
                    WheelColumn(centre: 120, rows: { offset in let h = hour + offset; return (0...23).contains(h) ? (h < 10 ? "0\(h)" : "\(h)") : nil }, spin: { [weak self] rows in self?.adjust(.hour, by: rows) }),
                    WheelColumn(centre: 200, rows: { offset in let m = minute + offset * interval; return (0...59).contains(m) ? (m < 10 ? "0\(m)" : "\(m)") : nil }, spin: { [weak self] rows in self?.adjust(.minute, by: rows * interval) }),
                ]
            }
            let twelve = hour % 12 == 0 ? 12 : hour % 12
            return [
                WheelColumn(centre: 100, rows: { offset in let h = twelve + offset; return (1...12).contains(h) ? "\(h)" : nil }, spin: { [weak self] rows in self?.adjust(.hour, by: rows) }),
                WheelColumn(centre: 160, rows: { offset in let m = minute + offset * interval; return (0...59).contains(m) ? (m < 10 ? "0\(m)" : "\(m)") : nil }, spin: { [weak self] rows in self?.adjust(.minute, by: rows * interval) }),
                WheelColumn(centre: 220, rows: { offset in
                    let period = hour < 12 ? 0 : 1
                    let p = period + offset
                    return p == 0 ? "AM" : p == 1 ? "PM" : nil
                }, spin: { [weak self] rows in
                    guard let self, rows != 0 else { return }
                    let wantsPM = rows > 0
                    if wantsPM != (hour >= 12) { self.adjust(.hour, by: wantsPM ? 12 : -12) }
                }),
            ]
        case .date:
            let c = components
            let month = max(1, min(12, c.month ?? 1)), day = c.day ?? 1, year = c.year ?? 2000
            return [
                WheelColumn(centre: 96, rows: { offset in let m = month + offset; return (1...12).contains(m) ? strings.months[m - 1] : nil }, spin: { [weak self] rows in self?.adjust(.month, by: rows) }),
                WheelColumn(centre: 200, rows: { offset in let d = day + offset; return (1...31).contains(d) ? "\(d)" : nil }, spin: { [weak self] rows in self?.adjust(.day, by: rows) }),
                WheelColumn(centre: 272, rows: { offset in "\(year + offset)" }, spin: { [weak self] rows in self?.adjust(.year, by: rows) }),
            ]
        }
    }

    private func adjust(_ component: Calendar.Component, by value: Int) {
        guard value != 0, let adjusted = calendarInZone.date(byAdding: component, value: value, to: date) else { return }
        date = adjusted
    }

    // MARK: Touches (uk-datepicker)

    private var wheelDragStart: CGPoint?

    override open func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        wheelDragStart = datePickerStyle == .wheels ? touch.location(in: self) : nil
        return true
    }

    override open func endTracking(_ touch: UITouch?, with event: UIEvent?) {
        guard let touch, point(inside: touch.location(in: self), with: event) else { wheelDragStart = nil; return }
        let point = touch.location(in: self)
        switch datePickerStyle {
        case .compact:
            if let capsule = capsules(in: CGRect(origin: .zero, size: bounds.size)).first(where: { $0.rect.contains(point) }) {
                presentEditor(for: capsule.kind, from: capsule.rect)
            }
        case .inline:
            let grid = inlineCalendarGrid
            switch grid.hit(point) {
            case .previous: if canPageInline(by: -1) { pageInline(by: -1) }
            case .next: if canPageInline(by: 1) { pageInline(by: 1) }
            case .day(let day): selectInline(day: day)
            case .title, .none:
                if showsTime, point.y >= grid.height - CalendarGrid.bottomInset, point.x > bounds.width / 2 {
                    presentEditor(for: .time, from: CGRect(x: bounds.width - 16 - timeCapsuleWidth, y: grid.height - CalendarGrid.bottomInset + 6, width: timeCapsuleWidth, height: 40))
                }
            }
        case .wheels:
            guard let start = wheelDragStart else { return }
            wheelDragStart = nil
            let columns = wheelColumns
            guard let column = columns.min(by: { abs($0.centre - start.x) < abs($1.centre - start.x) }) else { return }
            // A drag spins the wheel by the rows it covers; a tap picks the row under the finger.
            let dragged = abs(point.y - start.y) > 8
            let rows = dragged ? Int(((start.y - point.y) / WheelPainter.rowPitch).rounded()) : Int(((point.y - bounds.midY) / WheelPainter.rowPitch).rounded())
            guard rows != 0 else { return }
            let before = (date, countDownDuration)
            column.spin(rows)
            if before.0 != date || before.1 != countDownDuration { sendActions(for: .valueChanged) }
        case .automatic: break
        }
    }

    override open func cancelTracking(with event: UIEvent?) { wheelDragStart = nil }

    /// Presents the calendar (or the time wheels) in a popover anchored to the capsule, as
    /// UIKit does from a compact picker; the editor's changes come back as `valueChanged`.
    private func presentEditor(for kind: CapsuleKind, from rect: CGRect) {
        guard let window, let presenter = window.rootViewController?.topmostPresented, presenter.presentedViewController == nil else { return }
        let editor = DatePickerEditorController(owner: self, kind: kind)
        editor.modalPresentationStyle = .popover
        editor.popoverPresentationController?.sourceView = self
        editor.popoverPresentationController?.sourceRect = rect
        editor.popoverPresentationController?.permittedArrowDirections = [.up, .down]
        editor.popoverPresentationController?.delegate = editor
        presenter.present(editor, animated: true)
    }

    // MARK: Semantics

    override func decorateSemantics(_ node: inout SemanticsNode) {
        node.role = datePickerStyle == .wheels ? .slider : .button
        if datePickerMode == .countDownTimer {
            let total = Int(countDownDuration / 60)
            if node.label.isEmpty { node.label = "\(total / 60) hours \(total % 60) minutes" }
            return
        }
        let parts = [showsDate ? dateText : nil, showsTime ? timeText : nil].compactMap { $0 }
        if node.label.isEmpty { node.label = parts.joined(separator: " ") }
    }

    override open func accessibilityIncrement() { stepFromAssistiveTechnology(1) }
    override open func accessibilityDecrement() { stepFromAssistiveTechnology(-1) }

    private func stepFromAssistiveTechnology(_ delta: Int) {
        guard datePickerStyle == .wheels, let column = wheelColumns.first else { return }
        let before = (date, countDownDuration)
        column.spin(delta)
        if before.0 != date || before.1 != countDownDuration { sendActions(for: .valueChanged) }
    }
}

/// The popover a compact picker presents: an inline calendar for the date capsule, the time
/// wheels for the time capsule; 320 wide, as tall as its content, staying a popover on the iPhone.
@MainActor
final class DatePickerEditorController: UIViewController, UIPopoverPresentationControllerDelegate {
    private weak var owner: UIDatePicker?
    private let kind: UIDatePicker.CapsuleKind
    let picker = UIDatePicker()

    init(owner: UIDatePicker, kind: UIDatePicker.CapsuleKind) {
        self.owner = owner
        self.kind = kind
        super.init(nibName: nil, bundle: nil)
        picker.calendar = owner.calendar
        picker.locale = owner.locale
        picker.timeZone = owner.timeZone
        picker.minimumDate = owner.minimumDate
        picker.maximumDate = owner.maximumDate
        picker.minuteInterval = owner.minuteInterval
        picker.datePickerMode = kind == .date ? .date : .time
        picker.preferredDatePickerStyle = kind == .date ? .inline : .wheels
        picker.date = owner.date
        picker.sizeToFit()
        preferredContentSize = picker.bounds.size
        picker.addTarget(self, action: { [weak self] _ in
            guard let self, let owner = self.owner else { return }
            owner.date = self.picker.date
            owner.sendActions(for: .valueChanged)
        }, for: .valueChanged)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        view.addSubview(picker)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        picker.frame = CGRect(origin: .zero, size: view.bounds.size)
    }

    func adaptivePresentationStyle(for controller: UIPresentationController, traitCollection: UITraitCollection) -> UIModalPresentationStyle { .none }
}

/// The drum a wheels picker draws: a selection band across the middle and, per column, the rows
/// around the selected one on a 32 pt pitch, shrinking and fading with the angle
/// (approximate: UIKit renders a real cylinder). A column may carry a unit label after its
/// selected row (the count-down timer's "hour" and "min", 17 pt semibold).
@MainActor
enum WheelPainter {
    struct Column {
        let centre: CGFloat
        /// The text `offset` rows from the selected one (nil past the ends).
        let rows: (Int) -> String?
        var label: (x: CGFloat, text: String)? = nil
        /// A view drawn in place of the text, when the picker's delegate supplies one.
        var view: ((Int) -> UIView?)? = nil
    }

    static let rowPitch: CGFloat = 32
    static let fontSize: CGFloat = 21

    static func paint(columns: [Column], in bounds: CGRect, style: UIUserInterfaceStyle, rowHeight: CGFloat = rowPitch, into list: inout DisplayList) {
        let band = CGRect(x: bounds.minX + 13, y: bounds.midY - rowHeight / 2, width: bounds.width - 26, height: rowHeight)
        list.append(.fillRRect(band, cornerRadius: 8, UIColor.tertiarySystemFill.rgba(for: style)))
        list.withSavedState { list in
            list.append(.clipRect(bounds))
            for column in columns {
                for offset in -3...3 {
                    let angle = Double(offset) * 0.32 * rowHeight / rowPitch
                    guard abs(angle) < .pi / 2 else { continue }
                    let scale = CGFloat(_cos(angle))
                    let y = bounds.midY + CGFloat(_sin(angle)) * bounds.height / 2
                    let alpha = offset == 0 ? 1 : max(0.25, 0.75 - 0.15 * Double(abs(offset)))
                    if let view = column.view?(offset) {
                        paint(view, centre: CGPoint(x: column.centre, y: y), scale: scale, alpha: alpha, style: style, into: &list)
                        continue
                    }
                    guard let text = column.rows(offset) else { continue }
                    let font = UIFont.systemFont(ofSize: fontSize * scale)
                    let layout = UIKitScene.shared.textEngine.layout([StyledRun(text, font: font.resolved)], options: TextLayoutOptions(lineLimit: 1), width: nil)
                    guard let line = layout.lines.first else { continue }
                    let ink = (offset == 0 ? UIColor.label : UIColor.secondaryLabel).rgba(for: style).multiplyingAlpha(by: alpha)
                    let x = column.centre - line.inkWidth / 2
                    let baseline = y + font.ascender - font.lineHeight / 2
                    for fragment in line.fragments {
                        list.append(.drawText(fragment.text, DisplayFont(font.resolved), origin: CGPoint(x: x + fragment.x, y: baseline), ink))
                    }
                }
                if let label = column.label {
                    let font = UIFont.systemFont(ofSize: 17, weight: .semibold)
                    list.append(.drawText(label.text, DisplayFont(font.resolved), origin: CGPoint(x: label.x, y: bounds.midY + font.ascender - font.lineHeight / 2), UIColor.label.rgba(for: style)))
                }
            }
        }
    }

    /// Paints a row view (laid out at its frame's size) centred on `centre`, scaled and faded as
    /// the drum turns it.
    private static func paint(_ view: UIView, centre: CGPoint, scale: CGFloat, alpha: Double, style: UIUserInterfaceStyle, into list: inout DisplayList) {
        view.layoutIfNeeded()
        let size = view.bounds.size
        list.append(.save)
        if alpha < 1 { list.append(.beginGroup(opacity: alpha)) }
        list.append(.concat(CGAffineTransform(translationX: centre.x, y: centre.y).scaledBy(x: scale, y: scale).translatedBy(x: -centre.x, y: -centre.y)))
        let origin = CGPoint(x: centre.x - size.width / 2, y: centre.y - size.height / 2)
        view.layer.paint(into: &list, context: PaintContext(origin: CGPoint(x: origin.x - view.frame.minX, y: origin.y - view.frame.minY), scale: UIScreen.main.scale), style: style)
        if alpha < 1 { list.append(.endGroup) }
        list.append(.restore)
    }
}
