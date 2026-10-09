// uk-datepicker (Controls/UIDatePicker.swift, Controls/UICalendarView.swift): locales and the
// 24-hour clock, the minimum and maximum dates, the numeric date a narrow picker falls back to,
// the inline style's size and taps, the calendar view's selection and range, the count-down
// timer, the wheels spun by touch, and the popover a compact picker presents.
import Testing
import UIKit
@testable import UIKitWebCore
#if os(WASI)
import WebFoundation
#else
import Foundation
#endif
#if canImport(AppKit)
import WebGraphicsNative
#endif

@Suite @MainActor struct DatePickerLooksTests {
    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 11, _ minute: Int = 30) -> Date {
        var components = DateComponents()
        components.year = year; components.month = month; components.day = day; components.hour = hour; components.minute = minute
        return Calendar(identifier: .gregorian).date(from: components)!
    }

    private func scene() -> UIKitScene {
        let scene = UIKitScene.shared
        scene.removeAllWindows()
        #if canImport(AppKit)
        scene.textEngine = CoreTextEngine()
        #else
        scene.textEngine = SyntheticTextEngine()
        #endif
        scene.configureScreen(size: CGSize(width: 320, height: 480), scale: 2)
        return scene
    }

    private func host(_ view: UIView, scene: UIKitScene) -> UIViewController {
        let root = UIViewController()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        window.rootViewController = root
        window.makeKeyAndVisible()
        root.view.addSubview(view)
        scene.layout(in: CGSize(width: 320, height: 480))
        return root
    }

    private func tap(_ scene: UIKitScene, at point: CGPoint) {
        scene.pointerDown(at: point, type: .touch, time: 0)
        scene.pointerUp(at: point, time: 0.05)
    }

    private func drag(_ scene: UIKitScene, from start: CGPoint, to end: CGPoint) {
        scene.pointerDown(at: start, type: .touch, time: 0)
        scene.pointerMoved(to: CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2), time: 0.05)
        scene.pointerMoved(to: end, time: 0.1)
        scene.pointerUp(at: end, time: 0.12)
    }

    @Test func localesFormatTheCapsules() {
        _ = scene()
        let picker = UIDatePicker()
        picker.datePickerMode = .dateAndTime
        picker.date = date(2026, 9, 11)
        #expect(picker.dateText == "Sep 11, 2026" && picker.timeText == "11:30\u{202F}AM")
        picker.locale = Locale(identifier: "en_GB")
        #expect(picker.dateText == "11 Sep 2026" && picker.timeText == "11:30")
        picker.locale = Locale(identifier: "de_DE")
        #expect(picker.dateText == "11.09.2026")
        picker.locale = Locale(identifier: "fr_FR")
        #expect(picker.dateText == "11 sept. 2026")
        picker.locale = Locale(identifier: "ja_JP")
        #expect(picker.dateText == "2026/09/11")
        picker.locale = Locale(identifier: "en_US")
        picker.date = date(2026, 9, 11, 14, 5)
        #expect(picker.timeText == "2:05\u{202F}PM")
        #expect(picker.shortDateText == "9/11/26")
    }

    @Test func minimumAndMaximumDatesClamp() {
        _ = scene()
        let picker = UIDatePicker()
        picker.datePickerMode = .date
        picker.minimumDate = date(2026, 9, 14)
        picker.date = date(2026, 9, 11)
        #expect(picker.date == date(2026, 9, 14))
        #expect(picker.dateText == "Sep 14, 2026")
        picker.maximumDate = date(2026, 9, 20)
        picker.date = date(2026, 10, 1)
        #expect(picker.date == date(2026, 9, 20))
        picker.maximumDate = nil
        picker.minimumDate = date(2026, 9, 25)   // moving a bound moves the date
        #expect(picker.date == date(2026, 9, 25))
    }

    @Test func narrowCompactPickerShowsTheNumericDate() {
        let scene = scene()
        let picker = UIDatePicker()
        picker.datePickerMode = .dateAndTime
        picker.date = date(2026, 9, 11)
        picker.frame = CGRect(x: 16, y: 16, width: 200, height: 40)
        _ = host(picker, scene: scene)
        let texts = scene.render(scale: 2, background: false).commands.compactMap { command -> String? in
            if case .drawText(let text, _, _, _) = command { return text }
            return nil
        }
        #expect(texts.contains("9/11/26") && !texts.contains("Sep 11, 2026"))
        picker.frame.size.width = 240
        let wide = scene.render(scale: 2, background: false).commands.compactMap { command -> String? in
            if case .drawText(let text, _, _, _) = command { return text }
            return nil
        }
        #expect(wide.contains("Sep 11, 2026"))
    }

    @Test func inlineStyleSizesToItsMonthAndTakesTaps() {
        let scene = scene()
        let picker = UIDatePicker()
        picker.preferredDatePickerStyle = .inline
        picker.datePickerMode = .date
        picker.date = date(2026, 9, 11)
        picker.sizeToFit()
        #expect(picker.frame.size == CGSize(width: 320, height: 327.5))   // five weeks
        picker.date = date(2026, 8, 11)   // August 2026 spans six weeks
        #expect(picker.sizeThatFits(.zero).height == 373)
        picker.datePickerMode = .dateAndTime
        picker.date = date(2026, 9, 11)
        #expect(picker.sizeThatFits(.zero).height == 373.5)
        picker.frame = CGRect(x: 0, y: 8, width: 320, height: 373.5)
        var changes = 0
        picker.addTarget(nil, action: { _ in changes += 1 }, for: .valueChanged)
        _ = host(picker, scene: scene)
        // The 18th: row 3 (13…19), column 5 (FRI): cells 42.5 wide from 10.5, rows 45.5 from 90.
        tap(scene, at: CGPoint(x: 10.5 + 5.5 * 42.5, y: 8 + 90 + 2.5 * 45.5))
        #expect(picker.date == date(2026, 9, 18) && changes == 1)
        // The next-month chevron pages the calendar without changing the date.
        tap(scene, at: CGPoint(x: 320 - 22.25, y: 8 + 35))
        #expect(picker.date == date(2026, 9, 18) && changes == 1)
        let texts = scene.render(scale: 2, background: false).commands.compactMap { command -> String? in
            if case .drawText(let text, _, _, _) = command { return text }
            return nil
        }
        #expect(texts.contains("October 2026") && texts.contains("Time") && texts.contains("11:30\u{202F}AM"))
        // A day of the paged month is selected with the picker's time of day.
        tap(scene, at: CGPoint(x: 10.5 + 4.5 * 42.5, y: 8 + 90 + 0.5 * 45.5))   // Thursday 1 October
        #expect(picker.date == date(2026, 10, 1) && changes == 2)
        #expect(picker.sizeThatFits(.zero).height == 373.5)
    }

    @Test func calendarViewSelectsWithinItsRange() {
        let scene = scene()
        final class Delegate: UICalendarSelectionSingleDateDelegate {
            var selected: [DateComponents?] = []
            func dateSelection(_ selection: UICalendarSelectionSingleDate, didSelectDate dateComponents: DateComponents?) { selected.append(dateComponents) }
        }
        let delegate = Delegate()
        let view = UICalendarView()
        view.availableDateRange = DateInterval(start: date(2026, 9, 5, 0, 0), end: date(2026, 9, 25, 0, 0))
        view.visibleDateComponents = DateComponents(year: 2026, month: 9)
        let selection = UICalendarSelectionSingleDate(delegate: delegate)
        selection.selectedDate = DateComponents(year: 2026, month: 9, day: 11)
        view.selectionBehavior = selection
        view.sizeToFit()
        #expect(view.frame.size == CGSize(width: 280, height: 288))
        #expect(view.grid.columnWidth == 37 && view.rowHeight == 36)
        #if canImport(AppKit)
        #expect(view.grid.originX == 13)   // under the first weekday label, whose width CoreText measures
        #endif
        view.frame.origin = CGPoint(x: 0, y: 8)
        _ = host(view, scene: scene)
        tap(scene, at: CGPoint(x: 13 + 2.5 * 37, y: 8 + 90 + 0.5 * 36))   // 1 September: before the range
        #expect(delegate.selected.isEmpty && selection.selectedDate?.day == 11)
        tap(scene, at: CGPoint(x: 13 + 0.5 * 37, y: 8 + 90 + 2.5 * 36))   // 13 September
        #expect(delegate.selected.last??.day == 13 && selection.selectedDate?.day == 13)
        #expect(!view.canPage(by: 1) && !view.canPage(by: -1))
        view.availableDateRange = DateInterval(start: date(2026, 1, 1), end: date(2026, 12, 31))
        #expect(view.canPage(by: 1) && view.canPage(by: -1))
        view.page(by: 1)
        #expect(view.visibleDateComponents.month == 10)
        let multi = UICalendarSelectionMultiDate(delegate: nil)
        view.selectionBehavior = multi
        tap(scene, at: CGPoint(x: 13 + 4.5 * 37, y: 8 + 90 + 0.5 * 36))   // Thursday 1 October
        tap(scene, at: CGPoint(x: 13 + 5.5 * 37, y: 8 + 90 + 0.5 * 36))   // Friday 2 October
        #expect(multi.selectedDates.map(\.day) == [1, 2])
        tap(scene, at: CGPoint(x: 13 + 4.5 * 37, y: 8 + 90 + 0.5 * 36))
        #expect(multi.selectedDates.map(\.day) == [2])
    }

    @Test func countDownTimerAndWheelsSpin() {
        let scene = scene()
        let picker = UIDatePicker()
        picker.datePickerMode = .countDownTimer
        picker.countDownDuration = 90 * 60
        #expect(picker.datePickerStyle == .wheels)
        picker.sizeToFit()
        #expect(picker.frame.size == CGSize(width: 320, height: 216))
        picker.frame.origin = CGPoint(x: 0, y: 12)
        var changes = 0
        picker.addTarget(nil, action: { _ in changes += 1 }, for: .valueChanged)
        _ = host(picker, scene: scene)
        let texts = scene.render(scale: 2, background: false).commands.compactMap { command -> String? in
            if case .drawText(let text, _, _, _) = command { return text }
            return nil
        }
        #expect(texts.contains("hour") && texts.contains("min") && texts.contains("30"))
        // Dragging the hours wheel up by two rows adds two hours; a tap on the row below picks it.
        drag(scene, from: CGPoint(x: 99, y: 12 + 108 + 64), to: CGPoint(x: 99, y: 12 + 108))
        #expect(picker.countDownDuration == (3 * 60 + 30) * 60 && changes == 1)
        tap(scene, at: CGPoint(x: 177.5, y: 12 + 108 + 32))
        #expect(picker.countDownDuration == (3 * 60 + 31) * 60 && changes == 2)

        let wheels = UIDatePicker()
        wheels.preferredDatePickerStyle = .wheels
        wheels.datePickerMode = .date
        wheels.date = date(2026, 9, 11)
        wheels.frame = CGRect(x: 0, y: 12, width: 320, height: 216)
        var dates: [Date] = []
        wheels.addTarget(nil, action: { dates.append(($0 as! UIDatePicker).date) }, for: .valueChanged)
        picker.removeFromSuperview()
        _ = host(wheels, scene: scene)
        drag(scene, from: CGPoint(x: 200, y: 12 + 108), to: CGPoint(x: 200, y: 12 + 108 + 32))   // the day wheel down one row
        #expect(dates == [date(2026, 9, 10)])
        tap(scene, at: CGPoint(x: 96, y: 12 + 108 - 32))   // the month above
        #expect(wheels.date == date(2026, 8, 10))
    }

    @Test func compactPickerPresentsTheCalendarInAPopover() {
        let scene = scene()
        let picker = UIDatePicker()
        picker.datePickerMode = .dateAndTime
        picker.date = date(2026, 9, 11)
        picker.frame = CGRect(x: 16, y: 100, width: 240, height: 40)
        var changes = 0
        picker.addTarget(nil, action: { _ in changes += 1 }, for: .valueChanged)
        let root = host(picker, scene: scene)
        tap(scene, at: CGPoint(x: 100, y: 120))   // the date capsule
        let editor = root.presentedViewController as? DatePickerEditorController
        #expect(editor != nil)
        #expect(editor?.modalPresentationStyle == .popover && editor?.popoverPresentationController?.staysPopover == true)
        #expect(editor?.preferredContentSize == CGSize(width: 320, height: 327.5))
        #expect(editor?.picker.datePickerStyle == .inline)
        scene.layout(in: CGSize(width: 320, height: 480))
        // Picking a day in the popover changes the compact picker and fires its action.
        editor?.picker.date = date(2026, 9, 18)
        editor?.picker.sendActions(for: .valueChanged)
        #expect(picker.date == date(2026, 9, 18) && changes == 1)
        editor?.dismiss(animated: false)
        #expect(root.presentedViewController == nil)
        tap(scene, at: CGPoint(x: 220, y: 120))   // the time capsule
        let time = root.presentedViewController as? DatePickerEditorController
        #expect(time?.picker.datePickerStyle == .wheels && time?.picker.datePickerMode == .time)
    }
}
