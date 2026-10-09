// UICalendarView (Docs/elements/UIKit/DatePicker.md): the month grid an inline date picker
// shows and apps embed on its own, with single- and multi-date selection behaviours and the
// available date range. The grid's geometry (a 17 pt semibold month title 20 in, 13 pt weekday
// initials, 20 pt day numbers in columns of (width − 20) / 7 from 90 down, the selected day a
// disc of the tint at 12 %) comes from the iPhone SE simulator (iOS 26, uikit/datepicker/inline,
// uikit/datepicker/calendar).
#if os(WASI)
import WebFoundation
#else
import Foundation
#endif

/// The delegate hearing of decorations and the visible month.
@MainActor
public protocol UICalendarViewDelegate: AnyObject {
    func calendarView(_ calendarView: UICalendarView, decorationFor dateComponents: DateComponents) -> UICalendarView.Decoration?
    func calendarView(_ calendarView: UICalendarView, didChangeVisibleDateComponentsFrom previousDateComponents: DateComponents)
}

extension UICalendarViewDelegate {
    public func calendarView(_ calendarView: UICalendarView, decorationFor dateComponents: DateComponents) -> UICalendarView.Decoration? { nil }
    public func calendarView(_ calendarView: UICalendarView, didChangeVisibleDateComponentsFrom previousDateComponents: DateComponents) {}
}

/// A selection behaviour a calendar view applies to taps on its days.
@MainActor
open class UICalendarSelection: NSObject {
    public override init() { super.init() }
    /// The view the behaviour is installed on.
    public internal(set) weak var calendarView: UICalendarView?
    func isSelected(_ day: DateComponents) -> Bool { false }
    func canSelect(_ day: DateComponents) -> Bool { true }
    func tapped(_ day: DateComponents) {}
}

@MainActor
public protocol UICalendarSelectionSingleDateDelegate: AnyObject {
    func dateSelection(_ selection: UICalendarSelectionSingleDate, didSelectDate dateComponents: DateComponents?)
    func dateSelection(_ selection: UICalendarSelectionSingleDate, canSelectDate dateComponents: DateComponents?) -> Bool
}

extension UICalendarSelectionSingleDateDelegate {
    public func dateSelection(_ selection: UICalendarSelectionSingleDate, canSelectDate dateComponents: DateComponents?) -> Bool { true }
}

/// Selects one day at a time.
@MainActor
open class UICalendarSelectionSingleDate: UICalendarSelection {
    open weak var delegate: (any UICalendarSelectionSingleDateDelegate)?
    open var selectedDate: DateComponents? { didSet { calendarView?.setNeedsDisplay() } }

    public init(delegate: (any UICalendarSelectionSingleDateDelegate)?) {
        self.delegate = delegate
        super.init()
    }

    open func setSelected(_ selectedDate: DateComponents?, animated: Bool) { self.selectedDate = selectedDate }

    override func isSelected(_ day: DateComponents) -> Bool { selectedDate.map { CalendarGrid.sameDay($0, day) } ?? false }
    override func canSelect(_ day: DateComponents) -> Bool { delegate?.dateSelection(self, canSelectDate: day) ?? true }
    override func tapped(_ day: DateComponents) {
        selectedDate = day
        delegate?.dateSelection(self, didSelectDate: day)
    }
}

@MainActor
public protocol UICalendarSelectionMultiDateDelegate: AnyObject {
    func multiDateSelection(_ selection: UICalendarSelectionMultiDate, didSelectDate dateComponents: DateComponents)
    func multiDateSelection(_ selection: UICalendarSelectionMultiDate, didDeselectDate dateComponents: DateComponents)
    func multiDateSelection(_ selection: UICalendarSelectionMultiDate, canSelectDate dateComponents: DateComponents) -> Bool
    func multiDateSelection(_ selection: UICalendarSelectionMultiDate, canDeselectDate dateComponents: DateComponents) -> Bool
}

extension UICalendarSelectionMultiDateDelegate {
    public func multiDateSelection(_ selection: UICalendarSelectionMultiDate, canSelectDate dateComponents: DateComponents) -> Bool { true }
    public func multiDateSelection(_ selection: UICalendarSelectionMultiDate, canDeselectDate dateComponents: DateComponents) -> Bool { true }
}

/// Toggles days in and out of a set.
@MainActor
open class UICalendarSelectionMultiDate: UICalendarSelection {
    open weak var delegate: (any UICalendarSelectionMultiDateDelegate)?
    open var selectedDates: [DateComponents] = [] { didSet { calendarView?.setNeedsDisplay() } }

    public init(delegate: (any UICalendarSelectionMultiDateDelegate)?) {
        self.delegate = delegate
        super.init()
    }

    open func setSelectedDates(_ selectedDates: [DateComponents], animated: Bool) { self.selectedDates = selectedDates }

    override func isSelected(_ day: DateComponents) -> Bool { selectedDates.contains { CalendarGrid.sameDay($0, day) } }
    override func canSelect(_ day: DateComponents) -> Bool {
        if isSelected(day) { return delegate?.multiDateSelection(self, canDeselectDate: day) ?? true }
        return delegate?.multiDateSelection(self, canSelectDate: day) ?? true
    }
    override func tapped(_ day: DateComponents) {
        if let index = selectedDates.firstIndex(where: { CalendarGrid.sameDay($0, day) }) {
            selectedDates.remove(at: index)
            delegate?.multiDateSelection(self, didDeselectDate: day)
        } else {
            selectedDates.append(day)
            delegate?.multiDateSelection(self, didSelectDate: day)
        }
    }
}

/// A view that displays a calendar with date-specific decorations and selection.
@MainActor
open class UICalendarView: UIView {
    /// A mark under a day: a dot of a colour (the default), a symbol, or a view (drawn as a dot).
    public final class Decoration {
        public enum Size: Int, Sendable { case small = 0, medium, large }
        let color: UIColor?
        let size: Size
        let image: UIImage?
        init(color: UIColor?, size: Size, image: UIImage?) { self.color = color; self.size = size; self.image = image }
        public static func `default`(color: UIColor? = nil, size: Size = .medium) -> Decoration { Decoration(color: color, size: size, image: nil) }
        public static func image(_ image: UIImage?, color: UIColor? = nil, size: Size = .medium) -> Decoration { Decoration(color: color, size: size, image: image) }
        public static func customView(_ customViewProvider: @escaping () -> UIView) -> Decoration { Decoration(color: nil, size: .medium, image: nil) }
    }

    open var calendar = Calendar(identifier: .gregorian) { didSet { setNeedsDisplay() } }
    open var locale: Locale = Locale(identifier: "en_US") { didSet { setNeedsDisplay() } }
    open var timeZone: TimeZone? { didSet { setNeedsDisplay() } }
    open var fontDesign: UIFontDescriptor.SystemDesign = .default
    open var wantsDateDecorations = true { didSet { setNeedsDisplay() } }
    open weak var delegate: (any UICalendarViewDelegate)?
    /// The days a user may reach: the view shows the month's others greyed and skips them.
    open var availableDateRange = DateInterval(start: .distantPast, end: .distantFuture) { didSet { setNeedsDisplay() } }
    open var selectionBehavior: UICalendarSelection? {
        didSet { oldValue?.calendarView = nil; selectionBehavior?.calendarView = self; setNeedsDisplay() }
    }
    /// The month shown (its year and month; other fields are ignored).
    open var visibleDateComponents: DateComponents {
        get { _visible }
        set { setVisibleDateComponents(newValue, animated: false) }
    }
    private var _visible: DateComponents

    public override init(frame: CGRect) {
        let now = Calendar(identifier: .gregorian).dateComponents([.year, .month], from: Date())
        _visible = DateComponents(year: now.year, month: now.month)
        super.init(frame: frame)
        isAccessibilityElement = false
    }

    open func setVisibleDateComponents(_ dateComponents: DateComponents, animated: Bool) {
        let previous = _visible
        _visible = DateComponents(year: dateComponents.year ?? previous.year, month: dateComponents.month ?? previous.month)
        invalidateIntrinsicContentSize()
        setNeedsDisplay()
        if previous != _visible { delegate?.calendarView(self, didChangeVisibleDateComponentsFrom: previous) }
    }

    open func reloadDecorations(forDateComponents dateComponents: [DateComponents], animated: Bool) { setNeedsDisplay() }

    // MARK: Geometry (uikit/datepicker/calendar: 280 × 288 sized to fit, cells 37 × 36)

    static let fittedSize = CGSize(width: 280, height: 288)

    override open func sizeThatFits(_ size: CGSize) -> CGSize { Self.fittedSize }
    override open var intrinsicContentSize: CGSize { Self.fittedSize }

    /// The rows are as tall as the frame leaves for five of them under the header and above 18
    /// at the bottom (36 in the fitted size, 42.5 at 320 × 320), at most the cells' width
    /// (approximate away from those sizes: UIKit's rows at 250 × 240 and 360 × 320 measured
    /// 2 taller).
    var rowHeight: CGFloat {
        let fromHeight = CalendarGrid.halfPoints((bounds.height - 108) / 5, .toNearestOrEven)
        return max(20, min(fromHeight, CalendarGrid.halfPoints((bounds.width - 56) / 6)))
    }

    var grid: CalendarGrid {
        CalendarGrid(calendar: calendarInZone, year: _visible.year ?? 2000, month: _visible.month ?? 1, layoutWidth: bounds.width + 8, gridWidth: bounds.width, rowHeight: rowHeight, strings: .resolve(locale))
    }

    private var calendarInZone: Calendar {
        var calendar = self.calendar
        if let timeZone { calendar.timeZone = timeZone }
        return calendar
    }

    func isAvailable(_ day: DateComponents) -> Bool {
        guard let date = calendarInZone.date(from: day) else { return false }
        return availableDateRange.start <= date && date <= availableDateRange.end
    }

    /// Whether the month before or after the visible one has any available day.
    func canPage(by months: Int) -> Bool {
        let grid = self.grid
        guard let first = calendarInZone.date(from: DateComponents(year: grid.year, month: grid.month, day: 1)),
              let target = calendarInZone.date(byAdding: .month, value: months, to: first) else { return false }
        if months < 0 {
            guard let lastDay = calendarInZone.range(of: .day, in: .month, for: target)?.upperBound,
                  let last = calendarInZone.date(from: DateComponents(year: calendarInZone.component(.year, from: target), month: calendarInZone.component(.month, from: target), day: lastDay - 1)) else { return false }
            return last >= availableDateRange.start
        }
        return target <= availableDateRange.end
    }

    func page(by months: Int) {
        guard canPage(by: months), let first = calendarInZone.date(from: DateComponents(year: grid.year, month: grid.month, day: 1)),
              let target = calendarInZone.date(byAdding: .month, value: months, to: first) else { return }
        setVisibleDateComponents(calendarInZone.dateComponents([.year, .month], from: target), animated: true)
    }

    // MARK: Painting

    override func drawContent(into list: inout DisplayList, context: PaintContext, style: UIUserInterfaceStyle) {
        let grid = self.grid
        let origin = context.absoluteRect(CGRect(origin: .zero, size: bounds.size)).origin
        let tint = tintColor.rgba(for: style)
        CalendarPainter.paint(grid, at: origin, tint: tint, style: style,
                              isEnabled: { [weak self] day in self?.isAvailable(day) ?? true },
                              isSelected: { [weak self] day in self?.selectionBehavior?.isSelected(day) ?? false },
                              decoration: { [weak self] day in
                                  guard let self, self.wantsDateDecorations else { return nil }
                                  return self.delegate?.calendarView(self, decorationFor: day)
                              },
                              canPageBack: canPage(by: -1), canPageForward: canPage(by: 1), into: &list)
    }

    // MARK: Touches

    override open func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        guard let touch = touches.first else { return }
        handleTap(at: touch.location(in: self))
    }

    func handleTap(at point: CGPoint) {
        let grid = self.grid
        switch grid.hit(point) {
        case .previous: page(by: -1)
        case .next: page(by: 1)
        case .day(let day):
            let components = DateComponents(year: grid.year, month: grid.month, day: day)
            guard isAvailable(components), let selection = selectionBehavior, selection.canSelect(components) else { return }
            selection.tapped(components)
        case .title, .none: break
        }
    }

    override func decorateSemantics(_ node: inout SemanticsNode) {
        let grid = self.grid
        node.role = .group
        if node.label.isEmpty { node.label = grid.title }
    }
}

// MARK: - The grid

/// Which part of a calendar grid a point lies on.
enum CalendarHit { case title, previous, next, day(Int) }

/// A month laid out as UIKit lays it out (the simulator's view trees of uikit/datepicker/inline
/// and uikit/datepicker/calendar, plus calendar views 250, 320 and 360 wide): the header 16 down
/// and 38 tall (the title 20 in, its disclosure chevron 4 after it; the paging buttons 43.5 wide
/// ending 2 before the layout width), the weekday initials in a row of equal labels spread from
/// 16 to 16 before the layout width, then the weeks from 90 down in rows of `rowHeight` and 7
/// columns of ⌊(gridWidth − 56) / 6⌋ (to the half point), the first centred under the first
/// weekday label. A calendar view lays its header out 8 wider than its frame; an inline date
/// picker's calendar is 8 narrower than the picker.
struct CalendarGrid {
    let calendar: Calendar
    let year: Int
    let month: Int
    /// The width the header and the weekday row are laid out in.
    let layoutWidth: CGFloat
    /// The width the day cells are sized from.
    let gridWidth: CGFloat
    let rowHeight: CGFloat
    let strings: DatePickerStrings

    static let headerHeight: CGFloat = 90
    static let bottomInset: CGFloat = 10
    static let titleInset: CGFloat = 20
    static let headerCentre: CGFloat = 35
    static let weekdayCentre: CGFloat = 79.5
    static let weekdayInset: CGFloat = 16
    static let navigationButtonWidth: CGFloat = 43.5
    /// The chevrons' ink centres within their buttons (the glyphs sit off-centre in their images).
    static let previousChevronOffset: CGFloat = 20.25
    static let nextChevronOffset: CGFloat = 23.25

    init(calendar: Calendar, year: Int, month: Int, layoutWidth: CGFloat, gridWidth: CGFloat, rowHeight: CGFloat, strings: DatePickerStrings) {
        self.calendar = calendar
        self.year = year
        self.month = month
        self.layoutWidth = layoutWidth
        self.gridWidth = gridWidth
        self.rowHeight = rowHeight
        self.strings = strings
    }

    static func halfPoints(_ value: CGFloat, _ rule: FloatingPointRoundingRule = .down) -> CGFloat { (value * 2).rounded(rule) / 2 }

    var columnWidth: CGFloat { Self.halfPoints((gridWidth - 56) / 6) }
    /// The weekday labels are all as wide as the widest initial (31.5 for SUN…SAT).
    @MainActor var weekdayLabelWidth: CGFloat {
        weekdayInitials.map { CalendarPainter.width(of: $0, font: CalendarPainter.weekdayFont) }.max() ?? 31.5
    }
    @MainActor var originX: CGFloat { Self.halfPoints(Self.weekdayInset + weekdayLabelWidth / 2 - columnWidth / 2) }

    var title: String { strings.monthTitle(month: month, year: year) }

    /// The number of days and the weekday column (0-based from the calendar's first weekday) of the 1st.
    var daysInMonth: Int {
        guard let first = calendar.date(from: DateComponents(year: year, month: month, day: 1)) else { return 30 }
        return calendar.range(of: .day, in: .month, for: first)?.count ?? 30
    }
    var leadingColumns: Int {
        guard let first = calendar.date(from: DateComponents(year: year, month: month, day: 1)) else { return 0 }
        let weekday = calendar.component(.weekday, from: first)
        return (weekday - calendar.firstWeekday + 7) % 7
    }
    var weeks: Int { (leadingColumns + daysInMonth + 6) / 7 }
    var height: CGFloat { Self.headerHeight + CGFloat(weeks) * rowHeight + Self.bottomInset }
    /// The selected day's disc: the smaller of the cell's sides.
    var discDiameter: CGFloat { min(columnWidth, rowHeight) }

    @MainActor func cell(day: Int) -> CGRect {
        let index = leadingColumns + day - 1
        return CGRect(x: originX + CGFloat(index % 7) * columnWidth, y: Self.headerHeight + CGFloat(index / 7) * rowHeight, width: columnWidth, height: rowHeight)
    }

    /// The weekday labels: equal widths spread evenly between the insets.
    @MainActor func weekdayLabel(_ column: Int) -> CGRect {
        let width = weekdayLabelWidth
        let pitch = (layoutWidth - 2 * Self.weekdayInset - width) / 6
        return CGRect(x: Self.weekdayInset + CGFloat(column) * pitch, y: Self.weekdayCentre - 9.5, width: width, height: 19)
    }

    var weekdayInitials: [String] {
        (0..<7).map { strings.weekdays[(calendar.firstWeekday - 1 + $0) % 7] }
    }

    /// The paging buttons' frames and their chevrons' ink centres.
    var nextButton: CGRect { CGRect(x: layoutWidth - 2 - Self.navigationButtonWidth, y: 16, width: Self.navigationButtonWidth, height: 38) }
    var previousButton: CGRect { nextButton.offsetBy(dx: -Self.navigationButtonWidth, dy: 0) }
    var nextCentre: CGPoint { CGPoint(x: nextButton.minX + Self.nextChevronOffset, y: Self.headerCentre) }
    var previousCentre: CGPoint { CGPoint(x: previousButton.minX + Self.previousChevronOffset, y: Self.headerCentre) }

    @MainActor func hit(_ point: CGPoint) -> CalendarHit? {
        if point.y < Self.headerHeight - rowHeight / 2 {
            if previousButton.insetBy(dx: 0, dy: -8).contains(point) { return .previous }
            if nextButton.insetBy(dx: 0, dy: -8).contains(point) { return .next }
            return point.y < 60 && point.x < previousButton.minX ? .title : nil
        }
        for day in 1...daysInMonth where cell(day: day).contains(point) { return .day(day) }
        return nil
    }

    static func sameDay(_ a: DateComponents, _ b: DateComponents) -> Bool {
        a.year == b.year && a.month == b.month && a.day == b.day
    }
}

/// Paints a month grid: the title with its disclosure chevron, the paging chevrons, the weekday
/// initials and the day numbers (the selected day semibold on a disc of the tint at 12 %,
/// unavailable days in the quaternary label colour).
@MainActor
enum CalendarPainter {
    static let titleFont = UIFont.systemFont(ofSize: 17, weight: .semibold)
    static let weekdayFont = UIFont.systemFont(ofSize: 13, weight: .semibold)
    static let dayFont = UIFont.systemFont(ofSize: 20)
    static let selectedDayFont = UIFont.systemFont(ofSize: 20, weight: .semibold)
    /// iOS's tertiary (weekday initials, disabled chevrons) and quaternary (unavailable days) labels.
    static let weekdayColor = UIColor(light: RGBA(r: 60, g: 60, b: 67, a: 0.3), dark: RGBA(r: 235, g: 235, b: 245, a: 0.3))
    static let unavailableColor = UIColor(light: RGBA(r: 60, g: 60, b: 67, a: 0.18), dark: RGBA(r: 235, g: 235, b: 245, a: 0.18))

    static func paint(_ grid: CalendarGrid, at origin: CGPoint, tint: RGBA, style: UIUserInterfaceStyle,
                      isEnabled: (DateComponents) -> Bool, isSelected: (DateComponents) -> Bool,
                      decoration: (DateComponents) -> UICalendarView.Decoration?,
                      canPageBack: Bool, canPageForward: Bool, into list: inout DisplayList) {
        let ink = UIColor.label.rgba(for: style)
        let weekday = weekdayColor.rgba(for: style)
        let unavailable = unavailableColor.rgba(for: style)
        // The title, cap-centred 35 down, and its disclosure chevron (7 × 12 of ink in a 10.5
        // wide image) 4 after the label.
        let titleWidth = width(of: grid.title, font: titleFont)
        drawText(grid.title, font: titleFont, color: ink, at: CGPoint(x: origin.x + CalendarGrid.titleInset, y: origin.y + CalendarGrid.headerCentre + 0.5), centred: false, into: &list)
        let disclosure = CGPoint(x: origin.x + CalendarGrid.titleInset + titleWidth + 4 + 5.25, y: origin.y + CalendarGrid.headerCentre)
        chevron(at: disclosure, width: 7, height: 12, lineWidth: 2.5, pointsLeft: false, color: tint, into: &list)
        // The paging chevrons, 10.5 × 17.5 of ink.
        chevron(at: CGPoint(x: origin.x + grid.previousCentre.x, y: origin.y + grid.previousCentre.y - 0.25), width: 10.5, height: 17.5, lineWidth: 3, pointsLeft: true, color: canPageBack ? tint : weekday, into: &list)
        chevron(at: CGPoint(x: origin.x + grid.nextCentre.x, y: origin.y + grid.nextCentre.y - 0.25), width: 10.5, height: 17.5, lineWidth: 3, pointsLeft: false, color: canPageForward ? tint : weekday, into: &list)
        for (column, initial) in grid.weekdayInitials.enumerated() {
            let rect = grid.weekdayLabel(column).offsetBy(dx: origin.x, dy: origin.y)
            drawText(initial, font: weekdayFont, color: weekday, at: CGPoint(x: rect.midX, y: origin.y + CalendarGrid.weekdayCentre), centred: true, into: &list)
        }
        for day in 1...grid.daysInMonth {
            let components = DateComponents(year: grid.year, month: grid.month, day: day)
            let cell = grid.cell(day: day).offsetBy(dx: origin.x, dy: origin.y)
            let enabled = isEnabled(components)
            let selected = enabled && isSelected(components)
            if selected {
                let disc = CGRect(x: cell.midX - grid.discDiameter / 2, y: cell.midY - grid.discDiameter / 2, width: grid.discDiameter, height: grid.discDiameter)
                list.append(.fillPath(Path(ellipseIn: disc), tint.multiplyingAlpha(by: 0.12)))
            }
            let color = selected ? tint : (enabled ? ink : unavailable)
            drawText("\(day)", font: selected ? selectedDayFont : dayFont, color: color, at: CGPoint(x: cell.midX, y: cell.midY), centred: true, into: &list)
            if enabled, let decoration = decoration(components) {
                // The dot under the number (approximate: 5 pt, 15 below the centre).
                let dotColor = (decoration.color ?? UIColor.systemGray).rgba(for: style)
                let size: CGFloat = decoration.size == .small ? 4 : decoration.size == .large ? 7 : 5
                list.append(.fillPath(Path(ellipseIn: CGRect(x: cell.midX - size / 2, y: cell.midY + 15 - size / 2, width: size, height: size)), dotColor))
            }
        }
    }

    /// A label's width: the advance width rounded up to the half point, as UIKit sizes labels.
    static func width(of text: String, font: UIFont) -> CGFloat {
        let layout = UIKitScene.shared.textEngine.layout([StyledRun(text, font: font.resolved)], options: TextLayoutOptions(lineLimit: 1), width: nil)
        return CalendarGrid.halfPoints(layout.size.width, .up)
    }

    /// Draws one line cap-centred on `point.y`, from `point.x` or centred on it (the label's
    /// frame rounded to the pixel grid as UIKit rounds frames).
    static func drawText(_ text: String, font: UIFont, color: RGBA, at point: CGPoint, centred: Bool, into list: inout DisplayList) {
        let layout = UIKitScene.shared.textEngine.layout([StyledRun(text, font: font.resolved)], options: TextLayoutOptions(lineLimit: 1), width: nil)
        guard let line = layout.lines.first else { return }
        let scale = UIScreen.main.scale
        let x = centred ? ((point.x - layout.size.width / 2) * scale).rounded(.up) / scale : point.x
        let baseline = ((point.y + font.capHeight / 2) * scale).rounded() / scale
        for fragment in line.fragments {
            list.append(.drawText(fragment.text, DisplayFont(font.resolved), origin: CGPoint(x: x + fragment.x, y: baseline), color))
        }
    }

    static func chevron(at centre: CGPoint, width: CGFloat, height: CGFloat, lineWidth: CGFloat, pointsLeft: Bool, color: RGBA, into list: inout DisplayList) {
        let inset = lineWidth / 2
        let tip = pointsLeft ? centre.x - width / 2 + inset : centre.x + width / 2 - inset
        let back = pointsLeft ? centre.x + width / 2 - inset : centre.x - width / 2 + inset
        var path = Path()
        path.move(to: CGPoint(x: back, y: centre.y - height / 2 + inset))
        path.addLine(to: CGPoint(x: tip, y: centre.y))
        path.addLine(to: CGPoint(x: back, y: centre.y + height / 2 - inset))
        list.append(.strokePath(path, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round), color))
    }
}

// MARK: - Strings

/// What a date picker's text looks like in a locale: the compact capsules' date and time, the
/// calendar's month title and weekday initials. en_US, en_GB, de, fr and ja are measured
/// (uikit/datepicker/locales); other languages take the day-month-year form with English names.
struct DatePickerStrings {
    enum DateForm { case monthDayYear, dayMonthYear, numericDayMonthYear, numericYearMonthDay }
    let form: DateForm
    let uses24Hour: Bool
    let shortMonths: [String]
    let months: [String]
    let weekdays: [String]
    let yearMonthTitle: Bool

    static let englishShortMonths = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    static let englishMonths = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
    static let englishWeekdays = ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"]

    static let english = DatePickerStrings(form: .monthDayYear, uses24Hour: false, shortMonths: englishShortMonths, months: englishMonths, weekdays: englishWeekdays, yearMonthTitle: false)

    static func resolve(_ locale: Locale?) -> DatePickerStrings {
        guard let locale else { return english }
        // The identifier's own parts ("fr_CA", "zh-Hant_TW"): the same on every platform.
        let parts = locale.identifier.split { $0 == "_" || $0 == "-" }.map(String.init)
        let language = parts.first?.lowercased() ?? "en"
        let region = parts.dropFirst().last { $0.count == 2 }?.uppercased() ?? ""
        switch language {
        case "en":
            if region.isEmpty || ["US", "CA", "PH"].contains(region) { return english }
            return DatePickerStrings(form: .dayMonthYear, uses24Hour: !["AU", "NZ", "IN", "IE"].contains(region), shortMonths: englishShortMonths, months: englishMonths, weekdays: englishWeekdays, yearMonthTitle: false)
        case "de":
            return DatePickerStrings(form: .numericDayMonthYear, uses24Hour: true, shortMonths: ["Jan.", "Feb.", "März", "Apr.", "Mai", "Juni", "Juli", "Aug.", "Sept.", "Okt.", "Nov.", "Dez."],
                                     months: ["Januar", "Februar", "März", "April", "Mai", "Juni", "Juli", "August", "September", "Oktober", "November", "Dezember"],
                                     weekdays: ["SO.", "MO.", "DI.", "MI.", "DO.", "FR.", "SA."], yearMonthTitle: false)
        case "fr":
            return DatePickerStrings(form: .dayMonthYear, uses24Hour: true, shortMonths: ["janv.", "févr.", "mars", "avr.", "mai", "juin", "juil.", "août", "sept.", "oct.", "nov.", "déc."],
                                     months: ["janvier", "février", "mars", "avril", "mai", "juin", "juillet", "août", "septembre", "octobre", "novembre", "décembre"],
                                     weekdays: ["DIM.", "LUN.", "MAR.", "MER.", "JEU.", "VEN.", "SAM."], yearMonthTitle: false)
        case "ja", "zh", "ko":
            return DatePickerStrings(form: .numericYearMonthDay, uses24Hour: true, shortMonths: englishShortMonths, months: (1...12).map { "\($0)月" },
                                     weekdays: language == "ja" ? ["日", "月", "火", "水", "木", "金", "土"] : englishWeekdays, yearMonthTitle: true)
        default:
            return DatePickerStrings(form: .dayMonthYear, uses24Hour: true, shortMonths: englishShortMonths, months: englishMonths, weekdays: englishWeekdays, yearMonthTitle: false)
        }
    }

    private static func two(_ value: Int) -> String { value < 10 ? "0\(value)" : "\(value)" }

    /// "Sep 11, 2026", "11 Sep 2026", "11.09.2026" or "2026/09/11".
    func date(year: Int, month: Int, day: Int) -> String {
        let name = shortMonths[max(0, min(11, month - 1))]
        switch form {
        case .monthDayYear: return "\(name) \(day), \(year)"
        case .dayMonthYear: return "\(day) \(name) \(year)"
        case .numericDayMonthYear: return "\(Self.two(day)).\(Self.two(month)).\(year)"
        case .numericYearMonthDay: return "\(year)/\(Self.two(month))/\(Self.two(day))"
        }
    }

    /// The numeric date a compact picker falls back to when the long one does not fit ("9/11/26").
    func shortDate(year: Int, month: Int, day: Int) -> String {
        let yy = Self.two(year % 100)
        switch form {
        case .monthDayYear: return "\(month)/\(day)/\(yy)"
        case .dayMonthYear: return "\(Self.two(day))/\(Self.two(month))/\(year)"
        case .numericDayMonthYear: return "\(Self.two(day)).\(Self.two(month)).\(yy)"
        case .numericYearMonthDay: return "\(year)/\(Self.two(month))/\(Self.two(day))"
        }
    }

    /// "11:30 AM" (a narrow no-break space before the period) or "11:30".
    func time(hour: Int, minute: Int) -> String {
        if uses24Hour { return "\(Self.two(hour)):\(Self.two(minute))" }
        let twelve = hour % 12 == 0 ? 12 : hour % 12
        return "\(twelve):\(Self.two(minute))\u{202F}\(hour < 12 ? "AM" : "PM")"
    }

    /// "September 2026" or "2026年9月".
    func monthTitle(month: Int, year: Int) -> String {
        let name = months[max(0, min(11, month - 1))]
        return yearMonthTitle ? "\(year)年\(name)" : "\(name) \(year)"
    }
}
