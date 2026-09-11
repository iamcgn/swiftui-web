// UIDatePicker (Docs/elements/UIKit/DatePicker.md): the compact style's date, time and
// date-and-time capsules, a disabled one, and the wheels style, at a fixed date, measured
// against UIKit on the simulator.
#if canImport(UIKit)
import UIKit
import UIKitFixtureKit

public enum DatePickerFixtures {
    public static let all = [compact, wheels]

    /// 11 September 2026, 14:30 in the Gregorian calendar (the harness runs in en_US).
    static var fixedDate: Date {
        var components = DateComponents()
        components.year = 2026; components.month = 9; components.day = 11; components.hour = 14; components.minute = 30
        return Calendar(identifier: .gregorian).date(from: components)!
    }

    public static let compact = UIKitFixture("uikit/datepicker/compact", size: CGSize(width: 320, height: 400)) {
        let root = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 400))
        root.backgroundColor = .white
        @MainActor func picker(_ mode: UIDatePicker.Mode, _ style: UIDatePickerStyle, y: CGFloat, probe: String, enabled: Bool = true) {
            let picker = UIDatePicker()
            picker.preferredDatePickerStyle = style
            picker.datePickerMode = mode
            picker.date = fixedDate
            picker.isEnabled = enabled
            picker.sizeToFit()
            picker.frame.origin = CGPoint(x: 16, y: y)
            root.addSubview(picker.probe(probe))
        }
        picker(.date, .compact, y: 16, probe: "date")
        picker(.time, .compact, y: 64, probe: "time")
        picker(.dateAndTime, .compact, y: 112, probe: "dateAndTime")
        picker(.date, .compact, y: 160, probe: "disabled", enabled: false)
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
