// UIDatePicker (Docs/elements/UIKit/DatePicker.md): the compact style's date, time and
// date-and-time capsules, a disabled one, and the wheels style, at a fixed date, measured
// against UIKit on the simulator.
#if canImport(UIKit)
import UIKit
import UIKitFixtureKit

public enum DatePickerFixtures {
    public static let all = [compact, wheels] + looks

    /// 11 September 2026, 11:30 in the Gregorian calendar (the harness runs in en_US). The hour
    /// has two digits on purpose: iOS 26 sizes a compact picker's time capsule for the wider of
    /// its own time and the current time (a golden made in the afternoon measured 212.5, one
    /// made at 10 PM 222.5), so a two-digit fixture hour keeps the width the same all day.
    static var fixedDate: Date {
        var components = DateComponents()
        components.year = 2026; components.month = 9; components.day = 11; components.hour = 11; components.minute = 30
        return Calendar(identifier: .gregorian).date(from: components)!
    }

    public static let compact = UIKitFixture("uikit/datepicker/compact", size: CGSize(width: 320, height: 400)) {
        let root = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 400))
        root.backgroundColor = .white
        // iOS 26 sizes a compact picker's capsules for the current date and time rather than
        // the picker's (a golden made at 10 PM is 10 wider than one made at 3 PM, one made in
        // October 6.5 narrower than one made on the fixture's day), so every picker gets a
        // fixed 240 pt width and its capsules right-align inside it; a 200 pt one is too narrow
        // for "Sep 11, 2026" and shows the numeric date instead.
        @MainActor func picker(_ mode: UIDatePicker.Mode, _ style: UIDatePickerStyle, y: CGFloat, width: CGFloat = 240, probe: String, enabled: Bool = true) {
            let picker = UIDatePicker()
            picker.preferredDatePickerStyle = style
            picker.datePickerMode = mode
            picker.date = fixedDate
            picker.isEnabled = enabled
            picker.sizeToFit()
            picker.frame = CGRect(x: 16, y: y, width: width, height: picker.frame.height)
            root.addSubview(picker.probe(probe))
        }
        picker(.date, .compact, y: 16, probe: "date")
        picker(.time, .compact, y: 64, probe: "time")
        picker(.dateAndTime, .compact, y: 112, probe: "dateAndTime")
        picker(.date, .compact, y: 160, probe: "disabled", enabled: false)
        picker(.dateAndTime, .compact, y: 208, width: 200, probe: "narrow")
        return root
    }

    /// The wheels style: three columns of 21 pt rows on a 32 pt pitch under a selection band.
    /// The frame is pinned; the wheel's perspective is approximated, so the pixels are not.
    public static let wheels = UIKitFixture("uikit/datepicker/wheels", size: CGSize(width: 320, height: 240)) {
        let root = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 240))
        root.backgroundColor = .white
        let picker = UIDatePicker()
        picker.preferredDatePickerStyle = .wheels
        picker.datePickerMode = .date
        picker.date = fixedDate
        picker.sizeToFit()
        picker.frame.origin = CGPoint(x: 0, y: 12)
        root.addSubview(picker.probe("wheels"))
        return root
    }
}
#endif
