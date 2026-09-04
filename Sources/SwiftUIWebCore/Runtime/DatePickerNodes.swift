// DatePicker nodes (Docs/elements/DatePicker.md): the textual field (component slots in a bezel
// with a mini stepper), the month calendar and the analogue clock, plus the Gregorian date
// arithmetic they share (Foundation's calendar in the environment's time zone).
#if os(WASI)
import FoundationEssentials   // never full Foundation on wasm: it links ICU (decision 0006)
#else
import Foundation
#endif

// MARK: - Date arithmetic

package struct _DateParts: Equatable {
    package var year: Int, month: Int, day: Int, hour: Int, minute: Int
    /// 1 = Sunday.
    package var weekday: Int
}

extension EnvironmentValues {
    /// The Gregorian calendar in the environment's time zone (the only calendar drawn here).
    package var _gregorian: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }
}

package enum _DateMath {
    package static let monthAbbreviations = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    package static let weekdayAbbreviations = ["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"]

    package static func parts(of date: Date, calendar: Calendar) -> _DateParts {
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .weekday], from: date)
        return _DateParts(year: c.year ?? 2001, month: c.month ?? 1, day: c.day ?? 1, hour: c.hour ?? 0, minute: c.minute ?? 0, weekday: c.weekday ?? 1)
    }

    package static func date(from parts: _DateParts, calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: parts.year, month: parts.month, day: parts.day, hour: parts.hour, minute: parts.minute)) ?? Date()
    }

    package static func adding(_ component: Calendar.Component, _ value: Int, to date: Date, calendar: Calendar) -> Date {
        calendar.date(byAdding: component, value: value, to: date) ?? date
    }

    package static func daysInMonth(year: Int, month: Int, calendar: Calendar) -> Int {
        let first = calendar.date(from: DateComponents(year: year, month: month, day: 1)) ?? Date()
        return calendar.range(of: .day, in: .month, for: first)?.count ?? 30
    }

    /// The six weeks a month calendar shows, Sunday first: each day with whether it belongs to
    /// the month.
    package static func grid(year: Int, month: Int, calendar: Calendar) -> [[(day: Int, inMonth: Bool)]] {
        let first = calendar.date(from: DateComponents(year: year, month: month, day: 1)) ?? Date()
        let leading = ((calendar.component(.weekday, from: first) - 1) + 7) % 7
        let count = daysInMonth(year: year, month: month, calendar: calendar)
        let previous = adding(.month, -1, to: first, calendar: calendar)
        let previousCount = daysInMonth(year: calendar.component(.year, from: previous), month: calendar.component(.month, from: previous), calendar: calendar)
        var cells: [(day: Int, inMonth: Bool)] = []
        for i in 0..<leading { cells.append((previousCount - leading + 1 + i, false)) }
        for day in 1...count { cells.append((day, true)) }
        var next = 1
        while cells.count < 42 { cells.append((next, false)); next += 1 }
        return (0..<6).map { Array(cells[$0 * 7..<$0 * 7 + 7]) }
    }
}

// MARK: - Text helpers

extension ViewNode {
    package func _fontFor(size: CGFloat, weight: Font.Weight = .regular) -> ResolvedFont {
        Font.system(size: size, weight: weight).resolve(profile: environment.platformProfile)
    }

    package func _textWidth(_ string: String, font: ResolvedFont) -> CGFloat {
        string.isEmpty ? 0 : runtime.layoutText(string, font: font, width: nil).size.width
    }

    /// Draws `string` with its line box's top-left at `origin` (the baseline from the font table).
    package func _drawText(_ string: String, font: ResolvedFont, lineTop origin: CGPoint, color: RGBA, into list: inout DisplayList) {
        let baseline = environment.platformProfile.systemFontMetrics(for: font).baseline
        list.append(.drawText(string, DisplayFont(font), origin: CGPoint(x: origin.x, y: origin.y + baseline), color))
    }
}

// MARK: - The field

@MainActor
private var nextDateIdentifier = 9_000_000

/// The textual field: the shown components sit in fixed slots (two tabular digits for month,
/// day, hour and minute, four for the year, 17 pt for the period) separated by "/", ", ", ":"
/// and a space; numbers are right-aligned in their slots. With a stepper the bezel is inset 1,
/// 72 pt wide for a date (the content starts 1 further in), then a 9 pt gap and the 13 × 20
/// stepper; without one (the field style) the bezel is the control with 3 pt insets and 21 tall.
@MainActor
package final class DateFieldNode: LeafNode<_DateFieldHost>, _Interactive, _KeyHandling, _Adjustable {
    private let identifier: Int
    /// The component a press selected (the stepper and arrow keys adjust it; none adjusts the first).
    package private(set) var selectedComponent: Calendar.Component?

    override package init(_ context: _NodeContext<_DateFieldHost>) {
        nextDateIdentifier += 1
        identifier = nextDateIdentifier
        super.init(context)
    }

    package enum Segment {
        case value(Calendar.Component, String, width: CGFloat)
        case separator(String, width: CGFloat)
        package var width: CGFloat {
            switch self {
            case .value(_, _, let width), .separator(_, let width): return width
            }
        }
    }

    private var calendar: Calendar { environment._gregorian }
    private var font: ResolvedFont { _fontFor(size: PlatformMetrics.buttonLabelSize) }

    /// The segments for the shown components.
    package var segments: [Segment] {
        let parts = _DateMath.parts(of: view.date, calendar: calendar)
        let digit = PlatformMetrics.dateDigitWidth, separator = PlatformMetrics.dateSeparatorWidth
        var result: [Segment] = []
        if view.components.contains(.date) {
            result += [.value(.month, "\(parts.month)", width: 2 * digit), .separator("/", width: separator),
                       .value(.day, "\(parts.day)", width: 2 * digit), .separator("/", width: separator),
                       .value(.year, "\(parts.year)", width: 4 * digit)]
        }
        if view.components.contains(.hourAndMinute) {
            if !result.isEmpty { result.append(.separator(", ", width: PlatformMetrics.dateCommaWidth)) }
            let hour12 = parts.hour % 12 == 0 ? 12 : parts.hour % 12
            let minute = parts.minute < 10 ? "0\(parts.minute)" : "\(parts.minute)"
            result += [.value(.hour, "\(hour12)", width: 2 * digit), .separator(":", width: separator),
                       .value(.minute, minute, width: 2 * digit), .separator(" ", width: separator),
                       .value(.era, parts.hour < 12 ? "AM" : "PM", width: PlatformMetrics.datePeriodWidth)]
        }
        return result
    }

    private var contentWidth: CGFloat { segments.reduce(0) { $0 + $1.width } }

    /// The bezel (its fill; the border is drawn outside) and where the content starts.
    package var bezel: CGRect {
        if view.stepper {
            return CGRect(x: PlatformMetrics.dateStepperBezelInset + PlatformMetrics.textFieldBorderWidth, y: 0,
                          width: contentWidth - 2 * PlatformMetrics.textFieldBorderWidth, height: frame.height)
        }
        return CGRect(x: PlatformMetrics.textFieldBorderWidth, y: 0, width: contentWidth + 2 * PlatformMetrics.dateFieldInset - 2 * PlatformMetrics.textFieldBorderWidth,
                      height: frame.height)
    }

    package var contentStart: CGFloat {
        view.stepper ? PlatformMetrics.dateStepperBezelInset + 2 * PlatformMetrics.textFieldBorderWidth : PlatformMetrics.dateFieldInset
    }

    package var stepperRect: CGRect? {
        guard view.stepper else { return nil }
        return CGRect(x: frame.width - PlatformMetrics.dateStepperSize.width, y: (frame.height - PlatformMetrics.dateStepperSize.height) / 2,
                      width: PlatformMetrics.dateStepperSize.width, height: PlatformMetrics.dateStepperSize.height)
    }

    override package func computeSizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
        if view.stepper {
            let width = PlatformMetrics.dateStepperBezelInset + contentWidth + PlatformMetrics.dateStepperGap + PlatformMetrics.dateStepperSize.width
            return CGSize(width: width, height: PlatformMetrics.dateFieldHeight)
        }
        return CGSize(width: contentWidth + 2 * PlatformMetrics.dateFieldInset, height: PlatformMetrics.dateFieldHeight - 1)
    }

    override package var layoutSpacing: ViewSpacing { .textLikeControl }

    /// The text line is centred in the 22 pt stepper styles and a point down in the 21 pt field.
    private func lineTop(_ lineHeight: CGFloat) -> CGFloat {
        view.stepper ? (frame.height - lineHeight) / 2 : PlatformMetrics.dateFieldTextTop
    }

    override package func dimensions(in proposal: ProposedViewSize) -> ViewDimensions {
        let size = sizeThatFits(proposal)
        let metrics = environment.platformProfile.systemFontMetrics(for: font)
        let baseline = (view.stepper ? (size.height - metrics.lineHeight) / 2 : PlatformMetrics.dateFieldTextTop) + metrics.baseline
        return ViewDimensions(size: size, explicit: [VerticalAlignment.firstTextBaseline.key: baseline, VerticalAlignment.lastTextBaseline.key: baseline])
    }

    /// The slot rectangles of the value segments, in the node's coordinates.
    package var slots: [(component: Calendar.Component, rect: CGRect)] {
        var x = contentStart
        var result: [(Calendar.Component, CGRect)] = []
        let lineHeight = environment.platformProfile.systemFontMetrics(for: font).lineHeight
        let y = lineTop(lineHeight)
        for segment in segments {
            if case .value(let component, _, let width) = segment {
                result.append((component, CGRect(x: x, y: y, width: width, height: lineHeight)))
            }
            x += segment.width
        }
        return result
    }

    override package func paintSelf(into list: inout DisplayList, context: PaintContext) {
        let bounds = absoluteBounds(context)
        let enabled = environment.isEnabled
        let black = { (alpha: Double) in RGBA(red: 0, green: 0, blue: 0, alpha: alpha) }
        let bezel = context.absoluteRect(self.bezel)
        let outer = bezel.insetBy(dx: -PlatformMetrics.textFieldBorderWidth, dy: -PlatformMetrics.textFieldBorderWidth)
        list.append(.fillRRect(outer, cornerRadius: PlatformMetrics.textFieldCornerRadius + PlatformMetrics.textFieldBorderWidth, black(PlatformMetrics.dateFieldBorderAlpha)))
        list.append(.fillRRect(bezel, cornerRadius: PlatformMetrics.textFieldCornerRadius, environment._controlBackground))
        let focused = runtime.focusedIdentifier == identifier
        if focused {
            let ring = outer.insetBy(dx: -PlatformMetrics.focusRingWidth / 2, dy: -PlatformMetrics.focusRingWidth / 2)
            list.append(.strokePath(Path(roundedRect: ring, cornerRadius: PlatformMetrics.textFieldCornerRadius + PlatformMetrics.focusRingWidth, style: .circular),
                                    style: StrokeStyle(lineWidth: PlatformMetrics.focusRingWidth),
                                    Color.accentColor.opacity(PlatformMetrics.focusRingOpacity).resolve(in: environment)))
        }
        // Components: numbers right-aligned in their slots, the period a point before its slot.
        var color = (environment.foregroundColor ?? .primary).resolve(in: environment)
        if !enabled { color = color.multiplyingAlpha(by: PlatformMetrics.disabledLabelOpacity) }
        let font = font
        let lineHeight = environment.platformProfile.systemFontMetrics(for: font).lineHeight
        var x = bounds.minX + contentStart
        let lineTop = bounds.minY + self.lineTop(lineHeight)
        for segment in segments {
            switch segment {
            case .separator(let text, let width):
                _drawText(text, font: font, lineTop: CGPoint(x: x, y: lineTop), color: color, into: &list)
                x += width
            case .value(let component, let text, let width):
                let textWidth = _textWidth(text, font: font)
                let origin: CGFloat = component == .era ? x - PlatformMetrics.datePeriodLead : x + width - textWidth
                var textColor = color
                if focused, selectedComponent == component {
                    list.append(.fillRRect(CGRect(x: x, y: lineTop, width: width, height: lineHeight), cornerRadius: PlatformMetrics.dateSelectionCornerRadius,
                                           Color.accentColor.resolve(in: environment)))
                    textColor = RGBA(red: 1, green: 1, blue: 1, alpha: 1)
                }
                _drawText(text, font: font, lineTop: CGPoint(x: origin, y: lineTop), color: textColor, into: &list)
                x += width
            }
        }
        // The mini stepper: a rounded box with a divider and two chevrons.
        if let stepper = stepperRect.map(context.absoluteRect) {
            list.append(.fillRRect(stepper, cornerRadius: PlatformMetrics.dateStepperCornerRadius,
                                   black(enabled ? PlatformMetrics.stepperFill : PlatformMetrics.stepperDisabledFill)))
            let divider = CGRect(x: stepper.minX + PlatformMetrics.dateStepperDividerInset, y: context.round(stepper.midY),
                                 width: stepper.width - 2 * PlatformMetrics.dateStepperDividerInset, height: 1)
            list.append(.fillRect(divider, black(PlatformMetrics.stepperDividerAlpha)))
            let x0 = stepper.minX + PlatformMetrics.dateStepperChevronInset, x1 = stepper.maxX - PlatformMetrics.dateStepperChevronInset
            var chevrons = Path()
            chevrons.move(to: CGPoint(x: x0, y: stepper.minY + PlatformMetrics.dateStepperUpChevronBase))
            chevrons.addLine(to: CGPoint(x: stepper.midX, y: stepper.minY + PlatformMetrics.dateStepperUpChevronBase - PlatformMetrics.dateStepperChevronRise))
            chevrons.addLine(to: CGPoint(x: x1, y: stepper.minY + PlatformMetrics.dateStepperUpChevronBase))
            chevrons.move(to: CGPoint(x: x0, y: stepper.minY + PlatformMetrics.dateStepperDownChevronBase))
            chevrons.addLine(to: CGPoint(x: stepper.midX, y: stepper.minY + PlatformMetrics.dateStepperDownChevronBase + PlatformMetrics.dateStepperChevronRise))
            chevrons.addLine(to: CGPoint(x: x1, y: stepper.minY + PlatformMetrics.dateStepperDownChevronBase))
            list.append(.strokePath(chevrons, style: StrokeStyle(lineWidth: PlatformMetrics.stepperChevronStroke, lineCap: .round, lineJoin: .round),
                                    black(enabled ? PlatformMetrics.stepperChevronAlpha : PlatformMetrics.stepperDisabledChevronAlpha)))
        }
    }

    // MARK: Interaction

    /// Steps the selected component (the first when none is selected).
    package func step(_ direction: Int) {
        let component = selectedComponent ?? slots.first?.component ?? .day
        let date = view.date
        let next: Date
        switch component {
        case .era:
            next = _DateMath.adding(.hour, direction > 0 ? 12 : -12, to: date, calendar: calendar)
        default:
            next = _DateMath.adding(component, direction, to: date, calendar: calendar)
        }
        view.binding.set(next)
        // Re-read so a binding nobody observes still shows the new date.
        view = _DateFieldHost(date: view.binding.get(), binding: view.binding, components: view.components, stepper: view.stepper)
        runtime.setNeedsDisplay()
    }

    package func pressBegan() {}
    package func pressEnded(inside: Bool) {}

    package func pressEnded(inside: Bool, at point: CGPoint) {
        guard inside, environment.isEnabled else { return }
        if let stepper = stepperRect, stepper.contains(point) {
            step(point.y < stepper.midY ? 1 : -1)
            return
        }
        if let slot = slots.first(where: { $0.rect.insetBy(dx: -2, dy: -4).contains(point) }) {
            selectedComponent = slot.component
        } else if let last = slots.last, point.x > last.rect.maxX {
            selectedComponent = last.component
        } else {
            selectedComponent = slots.first?.component
        }
        runtime.focus(semanticsIdentifier: identifier)
        runtime.setNeedsDisplay()
    }

    /// Up/Down step the selected component, Left/Right move the selection.
    package func handleKey(_ press: KeyPress) -> Bool {
        guard environment.isEnabled, press.modifiers.shortcutModifiers.isEmpty else { return false }
        let components = slots.map(\.component)
        switch press.key {
        case .upArrow: step(1); return true
        case .downArrow: step(-1); return true
        case .leftArrow, .rightArrow:
            let current = components.firstIndex { $0 == selectedComponent } ?? 0
            let next = press.key == .rightArrow ? min(current + 1, components.count - 1) : max(current - 1, 0)
            selectedComponent = components.isEmpty ? nil : components[next]
            runtime.setNeedsDisplay()
            return true
        default: return false
        }
    }

    package func adjust(increment: Bool) { step(increment ? 1 : -1) }
    package func setValue(_ value: Double) {}

    /// The shown text, for assistive technology.
    package var text: String {
        segments.map { segment -> String in
            switch segment {
            case .value(_, let text, _), .separator(let text, _): return text
            }
        }.joined()
    }

    package var semantics: SemanticsNode {
        var node = SemanticsNode(role: .group, label: text, frame: frameInRoot, identifier: identifier)
        node.isFocusable = true
        node.isAdjustable = view.stepper
        node.value = text
        return node
    }
}

// MARK: - The calendar

/// The month calendar: a 137.5 × 148 box (in a 138.5 pt view) holding the month's name and
/// year in 13 pt bold, previous/today/next controls, the weekday row in 10 pt bold grey and six
/// weeks of 18.5 × 18 cells with 11 pt day numbers right-aligned, the selected day on a grey
/// rounded highlight and the neighbouring months' days in grey.
@MainActor
package final class CalendarNode: LeafNode<_CalendarHost>, _Interactive {
    private let identifier: Int
    /// The month shown when the user paged away from the selection's month.
    package private(set) var shown: (year: Int, month: Int)?

    override package init(_ context: _NodeContext<_CalendarHost>) {
        nextDateIdentifier += 1
        identifier = nextDateIdentifier
        super.init(context)
    }

    private var calendar: Calendar { environment._gregorian }

    package var visibleMonth: (year: Int, month: Int) {
        if let shown { return shown }
        let parts = _DateMath.parts(of: view.date, calendar: calendar)
        return (parts.year, parts.month)
    }

    override package func computeSizeThatFits(_ proposal: ProposedViewSize) -> CGSize { PlatformMetrics.calendarSize }
    override package var layoutSpacing: ViewSpacing { .plainControl }

    package var box: CGRect {
        CGRect(x: PlatformMetrics.calendarBoxInset.width, y: PlatformMetrics.calendarBoxInset.height,
               width: PlatformMetrics.calendarBoxSize.width, height: PlatformMetrics.calendarBoxSize.height)
    }

    package func cell(row: Int, column: Int) -> CGRect {
        let box = box
        return CGRect(x: box.minX + PlatformMetrics.calendarCellMargin + CGFloat(column) * PlatformMetrics.calendarCellSize.width,
                      y: box.minY + PlatformMetrics.calendarFirstRowCenter - PlatformMetrics.calendarCellSize.height / 2 + CGFloat(row) * PlatformMetrics.calendarCellSize.height,
                      width: PlatformMetrics.calendarCellSize.width, height: PlatformMetrics.calendarCellSize.height)
    }

    /// The previous-month, today and next-month controls, trailing in the header row.
    package var controls: (previous: CGRect, today: CGRect, next: CGRect) {
        let box = box
        let centerY = box.minY + PlatformMetrics.calendarHeaderCenter
        let arrow = PlatformMetrics.calendarArrowSize, dot = PlatformMetrics.calendarDotDiameter, gap = PlatformMetrics.calendarControlGap
        let next = CGRect(x: box.maxX - PlatformMetrics.calendarControlTrailing - arrow.width, y: centerY - arrow.height / 2, width: arrow.width, height: arrow.height)
        let today = CGRect(x: next.minX - gap - dot, y: centerY - dot / 2, width: dot, height: dot)
        let previous = CGRect(x: today.minX - gap - arrow.width, y: centerY - arrow.height / 2, width: arrow.width, height: arrow.height)
        return (previous, today, next)
    }

    override package func paintSelf(into list: inout DisplayList, context: PaintContext) {
        let black = { (alpha: Double) in RGBA(red: 0, green: 0, blue: 0, alpha: alpha) }
        let box = context.absoluteRect(self.box)
        list.append(.strokePath(Path(roundedRect: box.insetBy(dx: 0.5, dy: 0.5), cornerRadius: PlatformMetrics.calendarBoxCornerRadius, style: .circular),
                                style: StrokeStyle(lineWidth: 1), black(PlatformMetrics.calendarBoxBorderAlpha)))
        let primary = Color.primary.resolve(in: environment)
        let grey = black(PlatformMetrics.calendarMutedAlpha)
        // Header: "Mar 2025" in 13 pt bold, the controls in the secondary colour.
        let (year, month) = visibleMonth
        let header = _fontFor(size: PlatformMetrics.buttonLabelSize, weight: .bold)
        let headerLine = environment.platformProfile.systemFontMetrics(for: header).lineHeight
        _drawText("\(_DateMath.monthAbbreviations[month - 1]) \(year)", font: header,
                  lineTop: CGPoint(x: box.minX + PlatformMetrics.calendarHeaderLeading, y: box.minY + PlatformMetrics.calendarHeaderCenter - headerLine / 2),
                  color: primary, into: &list)
        let controls = controls
        let secondary = Color.secondary.resolve(in: environment)
        for (rect, forward) in [(controls.previous, false), (controls.next, true)] {
            let r = context.absoluteRect(rect)
            var triangle = Path()
            if forward {
                triangle.move(to: CGPoint(x: r.minX, y: r.minY)); triangle.addLine(to: CGPoint(x: r.maxX, y: r.midY)); triangle.addLine(to: CGPoint(x: r.minX, y: r.maxY))
            } else {
                triangle.move(to: CGPoint(x: r.maxX, y: r.minY)); triangle.addLine(to: CGPoint(x: r.minX, y: r.midY)); triangle.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
            }
            triangle.closeSubpath()
            list.append(.fillPath(triangle, secondary))
        }
        let today = context.absoluteRect(controls.today)
        list.append(.fillRRect(today, cornerRadius: today.width / 2, secondary))
        // Weekdays, centred in their columns.
        let weekdayFont = _fontFor(size: PlatformMetrics.calendarWeekdaySize, weight: .bold)
        let weekdayLine = environment.platformProfile.systemFontMetrics(for: weekdayFont).lineHeight
        for (column, name) in _DateMath.weekdayAbbreviations.enumerated() {
            let cell = context.absoluteRect(self.cell(row: 0, column: column))
            let width = _textWidth(name, font: weekdayFont)
            _drawText(name, font: weekdayFont, lineTop: CGPoint(x: cell.midX - width / 2, y: box.minY + PlatformMetrics.calendarWeekdayCenter - weekdayLine / 2),
                      color: grey, into: &list)
        }
        // Days, right-aligned 3 pt before the cell's trailing edge; the selection highlighted.
        let dayFont = _fontFor(size: PlatformMetrics.calendarDaySize)
        let dayLine = environment.platformProfile.systemFontMetrics(for: dayFont).lineHeight
        let selected = _DateMath.parts(of: view.date, calendar: calendar)
        for (row, week) in _DateMath.grid(year: year, month: month, calendar: calendar).enumerated() {
            for (column, day) in week.enumerated() {
                let cell = context.absoluteRect(self.cell(row: row, column: column))
                if day.inMonth, selected.year == year, selected.month == month, selected.day == day.day {
                    let highlight = cell.insetBy(dx: 0, dy: PlatformMetrics.calendarHighlightInset)
                    list.append(.fillRRect(highlight, cornerRadius: PlatformMetrics.calendarHighlightCornerRadius, black(PlatformMetrics.calendarHighlightAlpha)))
                }
                let text = "\(day.day)"
                let width = _textWidth(text, font: dayFont)
                _drawText(text, font: dayFont, lineTop: CGPoint(x: cell.maxX - PlatformMetrics.calendarDayTrailing - width, y: cell.midY - dayLine / 2),
                          color: day.inMonth ? primary : grey, into: &list)
            }
        }
    }

    // MARK: Interaction

    package func pressBegan() {}
    package func pressEnded(inside: Bool) {}

    package func pressEnded(inside: Bool, at point: CGPoint) {
        guard inside, environment.isEnabled else { return }
        let controls = controls
        let (year, month) = visibleMonth
        if controls.previous.insetBy(dx: -4, dy: -4).contains(point) || controls.next.insetBy(dx: -4, dy: -4).contains(point) {
            let first = calendar.date(from: DateComponents(year: year, month: month, day: 1)) ?? view.date
            let moved = _DateMath.adding(.month, controls.next.insetBy(dx: -4, dy: -4).contains(point) ? 1 : -1, to: first, calendar: calendar)
            shown = (calendar.component(.year, from: moved), calendar.component(.month, from: moved))
            runtime.setNeedsDisplay()
            return
        }
        if controls.today.insetBy(dx: -4, dy: -4).contains(point) {
            shown = nil
            select(_DateMath.parts(of: Date(), calendar: calendar))
            return
        }
        let grid = _DateMath.grid(year: year, month: month, calendar: calendar)
        for row in 0..<6 {
            for column in 0..<7 where cell(row: row, column: column).contains(point) {
                let day = grid[row][column]
                var parts = _DateMath.parts(of: view.date, calendar: calendar)
                if day.inMonth {
                    parts.year = year; parts.month = month
                } else {
                    let first = calendar.date(from: DateComponents(year: year, month: month, day: 1)) ?? view.date
                    let moved = _DateMath.adding(.month, row == 0 ? -1 : 1, to: first, calendar: calendar)
                    parts.year = calendar.component(.year, from: moved); parts.month = calendar.component(.month, from: moved)
                }
                parts.day = day.day
                shown = nil
                select(parts)
                return
            }
        }
    }

    /// Sets the selection's year, month and day (keeping the time).
    private func select(_ target: _DateParts) {
        var parts = _DateMath.parts(of: view.date, calendar: calendar)
        parts.year = target.year; parts.month = target.month; parts.day = target.day
        view.binding.set(_DateMath.date(from: parts, calendar: calendar))
        view = _CalendarHost(date: view.binding.get(), binding: view.binding)
        runtime.setNeedsDisplay()
    }

    package var semantics: SemanticsNode {
        let parts = _DateMath.parts(of: view.date, calendar: calendar)
        var node = SemanticsNode(role: .group, label: "\(_DateMath.monthAbbreviations[parts.month - 1]) \(parts.day), \(parts.year)", frame: frameInRoot, identifier: identifier)
        node.isFocusable = true
        return node
    }
}

// MARK: - The clock

/// The analogue clock: a 120 pt dial in a 119 pt square, a 6 pt bezel ring with a light-blue
/// to grey vertical gradient over a faint inner shadow, 13 pt numerals at radius 48.5, the
/// period under the centre in 13 pt medium grey, and black hands. Display only.
@MainActor
package final class ClockNode: LeafNode<_ClockHost> {
    private var calendar: Calendar { environment._gregorian }

    override package func computeSizeThatFits(_ proposal: ProposedViewSize) -> CGSize { PlatformMetrics.clockSize }
    override package var layoutSpacing: ViewSpacing { .plainControl }

    override package func paintSelf(into list: inout DisplayList, context: PaintContext) {
        let bounds = absoluteBounds(context)
        let center = CGPoint(x: bounds.minX + PlatformMetrics.clockCenter.x, y: bounds.minY + PlatformMetrics.clockCenter.y)
        let radius = PlatformMetrics.clockRadius
        let black = { (alpha: Double) in RGBA(red: 0, green: 0, blue: 0, alpha: alpha) }
        func circle(_ r: CGFloat) -> Path { Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r)) }
        // The face, the bezel ring (a vertical gradient) and the inner shadow fading downwards.
        list.append(.fillPath(circle(radius), PlatformMetrics.clockFaceColor))
        let ring = PlatformMetrics.clockRingWidth
        let ringGradient = DisplayGradient(kind: .linear(start: CGPoint(x: center.x, y: center.y - radius), end: CGPoint(x: center.x, y: center.y + radius)),
                                           stops: [.init(location: 0, color: PlatformMetrics.clockRingTop), .init(location: 1, color: PlatformMetrics.clockRingBottom)])
        list.append(.strokeGradient(circle(radius - ring / 2), style: StrokeStyle(lineWidth: ring), ringGradient))
        let shadowGradient = DisplayGradient(kind: .linear(start: CGPoint(x: center.x, y: center.y - radius), end: CGPoint(x: center.x, y: center.y + radius)),
                                             stops: [.init(location: 0, color: black(PlatformMetrics.clockInnerShadowAlpha)), .init(location: 1, color: black(0))])
        list.append(.strokeGradient(circle(radius - ring - PlatformMetrics.clockInnerShadowWidth / 2), style: StrokeStyle(lineWidth: PlatformMetrics.clockInnerShadowWidth), shadowGradient))
        // Numerals around the dial and the period under the centre.
        let font = _fontFor(size: PlatformMetrics.buttonLabelSize)
        let line = environment.platformProfile.systemFontMetrics(for: font).lineHeight
        let primary = Color.primary.resolve(in: environment)
        for hour in 1...12 {
            let angle = Double.pi / 2 - Double(hour) * .pi / 6
            let text = "\(hour)"
            let width = _textWidth(text, font: font)
            let position = CGPoint(x: center.x + PlatformMetrics.clockNumeralRadius * CGFloat(_cos(angle)), y: center.y - PlatformMetrics.clockNumeralRadius * CGFloat(_sin(angle)))
            _drawText(text, font: font, lineTop: CGPoint(x: position.x - width / 2, y: position.y - line / 2), color: primary, into: &list)
        }
        let parts = _DateMath.parts(of: view.date, calendar: calendar)
        let periodFont = _fontFor(size: PlatformMetrics.buttonLabelSize, weight: .medium)
        let period = parts.hour < 12 ? "AM" : "PM"
        let periodWidth = _textWidth(period, font: periodFont)
        _drawText(period, font: periodFont, lineTop: CGPoint(x: center.x - periodWidth / 2, y: center.y + PlatformMetrics.clockPeriodOffset - line / 2),
                  color: black(PlatformMetrics.clockPeriodAlpha), into: &list)
        // Hands and the centre cap.
        let hourAngle = Double.pi / 2 - (Double(parts.hour % 12) + Double(parts.minute) / 60) * .pi / 6
        let minuteAngle = Double.pi / 2 - Double(parts.minute) * .pi / 30
        for (angle, length, width) in [(hourAngle, PlatformMetrics.clockHourHandLength, PlatformMetrics.clockHourHandWidth),
                                       (minuteAngle, PlatformMetrics.clockMinuteHandLength, PlatformMetrics.clockMinuteHandWidth)] {
            var hand = Path()
            hand.move(to: center)
            hand.addLine(to: CGPoint(x: center.x + length * CGFloat(_cos(angle)), y: center.y - length * CGFloat(_sin(angle))))
            list.append(.strokePath(hand, style: StrokeStyle(lineWidth: width, lineCap: .round), primary))
        }
        list.append(.fillPath(circle(PlatformMetrics.clockCapRadius), primary))
    }
}
