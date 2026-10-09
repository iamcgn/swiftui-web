// UIDatePicker and UICalendarView looks (uk-datepicker): the inline style (date, and date and
// time), a calendar view with a limited range and a selection, the count-down timer wheels,
// compact pickers in other locales, and a picker view with custom row views.
#if canImport(UIKit)
import UIKit
import UIKitFixtureKit

final class CustomRowSource: NSObject, UIPickerViewDataSource, UIPickerViewDelegate {
    let colours: [(String, UIColor)] = [("Red", .systemRed), ("Green", .systemGreen), ("Blue", .systemBlue), ("Orange", .systemOrange)]
    func numberOfComponents(in pickerView: UIPickerView) -> Int { 2 }
    func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int { component == 0 ? colours.count : 5 }
    func pickerView(_ pickerView: UIPickerView, widthForComponent component: Int) -> CGFloat { component == 0 ? 180 : 80 }
    func pickerView(_ pickerView: UIPickerView, rowHeightForComponent component: Int) -> CGFloat { component == 0 ? 44 : 32 }
    func pickerView(_ pickerView: UIPickerView, viewForRow row: Int, forComponent component: Int, reusing view: UIView?) -> UIView {
        let label = (view as? UILabel) ?? UILabel()
        if component == 0 {
            label.text = colours[row].0
            label.textColor = colours[row].1
            label.font = .boldSystemFont(ofSize: 24)
            label.textAlignment = .center
        } else {
            label.text = "\(row + 1)"
            label.font = .systemFont(ofSize: 21)
            label.textAlignment = .center
        }
        return label
    }
}

extension DatePickerFixtures {
    static let looks = [inline, inlineTime, calendar, countdown, locales]

    @MainActor static var customSources: [CustomRowSource] = []

    /// The inline style for a date: a calendar with a month header, weekday row and day grid.
    public static let inline = UIKitFixture("uikit/datepicker/inline", size: CGSize(width: 320, height: 400)) {
        let root = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 400))
        root.backgroundColor = .white
        let picker = UIDatePicker()
        picker.preferredDatePickerStyle = .inline
        picker.datePickerMode = .date
        picker.date = fixedDate
        picker.sizeToFit()
        picker.frame.origin = CGPoint(x: 0, y: 8)
        root.addSubview(picker.probe("inline"))
        return root
    }

    /// The inline style for a date and time: the time capsule row above the calendar.
    public static let inlineTime = UIKitFixture("uikit/datepicker/inline-time", size: CGSize(width: 320, height: 440)) {
        let root = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 440))
        root.backgroundColor = .white
        let picker = UIDatePicker()
        picker.preferredDatePickerStyle = .inline
        picker.datePickerMode = .dateAndTime
        picker.date = fixedDate
        picker.sizeToFit()
        picker.frame.origin = CGPoint(x: 0, y: 8)
        root.addSubview(picker.probe("inlineTime"))
        return root
    }

    /// A calendar view limited to 5–25 September 2026 with the 11th selected.
    public static let calendar = UIKitFixture("uikit/datepicker/calendar", size: CGSize(width: 320, height: 400)) {
        let root = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 400))
        root.backgroundColor = .white
        let view = UICalendarView()
        view.calendar = Calendar(identifier: .gregorian)
        view.locale = Locale(identifier: "en_US")
        var start = DateComponents(); start.year = 2026; start.month = 9; start.day = 5
        var end = DateComponents(); end.year = 2026; end.month = 9; end.day = 25
        let gregorian = Calendar(identifier: .gregorian)
        view.availableDateRange = DateInterval(start: gregorian.date(from: start)!, end: gregorian.date(from: end)!)
        let selection = UICalendarSelectionSingleDate(delegate: nil)
        var selected = DateComponents(); selected.year = 2026; selected.month = 9; selected.day = 11
        selection.selectedDate = selected
        view.selectionBehavior = selection
        view.visibleDateComponents = DateComponents(year: 2026, month: 9)
        view.sizeToFit()
        view.frame.origin = CGPoint(x: 0, y: 8)
        root.addSubview(view.probe("calendar"))
        return root
    }

    /// The count-down timer: hours and minutes wheels with their unit labels.
    public static let countdown = UIKitFixture("uikit/datepicker/countdown", size: CGSize(width: 320, height: 240)) {
        let root = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 240))
        root.backgroundColor = .white
        let picker = UIDatePicker()
        picker.preferredDatePickerStyle = .wheels
        picker.datePickerMode = .countDownTimer
        picker.countDownDuration = 90 * 60
        picker.sizeToFit()
        picker.frame.origin = CGPoint(x: 0, y: 12)
        root.addSubview(picker.probe("countdown"))
        return root
    }

    /// Compact date-and-time pickers in en_GB, de_DE, fr_FR and ja_JP, each 300 wide.
    public static let locales = UIKitFixture("uikit/datepicker/locales", size: CGSize(width: 320, height: 400)) {
        let root = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 400))
        root.backgroundColor = .white
        var y: CGFloat = 16
        for (identifier, probe) in [("en_GB", "gb"), ("de_DE", "de"), ("fr_FR", "fr"), ("ja_JP", "jp")] {
            let picker = UIDatePicker()
            picker.preferredDatePickerStyle = .compact
            picker.datePickerMode = .dateAndTime
            picker.locale = Locale(identifier: identifier)
            picker.date = fixedDate
            picker.sizeToFit()
            picker.frame = CGRect(x: 10, y: y, width: 300, height: picker.frame.height)
            root.addSubview(picker.probe(probe))
            y += 56
        }
        let range = UIDatePicker()
        range.preferredDatePickerStyle = .compact
        range.datePickerMode = .date
        range.minimumDate = fixedDate.addingTimeInterval(86_400 * 3)   // the date is before the minimum: clamped on display?
        range.date = fixedDate
        range.sizeToFit()
        range.frame = CGRect(x: 10, y: y, width: 300, height: range.frame.height)
        root.addSubview(range.probe("clamped"))
        return root
    }
}

extension PickerFixtures {
    /// Custom row views (coloured bold labels in a 44 pt row, 180 wide) beside plain titles.
    public static let custom = UIKitFixture("uikit/picker/custom", size: CGSize(width: 320, height: 240)) {
        let root = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 240))
        root.backgroundColor = .white
        let source = CustomRowSource()
        DatePickerFixtures.customSources.append(source)
        let picker = UIPickerView()
        picker.dataSource = source
        picker.delegate = source
        picker.sizeToFit()
        picker.frame.origin = CGPoint(x: 0, y: 12)
        picker.selectRow(2, inComponent: 0, animated: false)
        picker.selectRow(3, inComponent: 1, animated: false)
        root.addSubview(picker.probe("custom"))
        return root
    }
}
#endif
