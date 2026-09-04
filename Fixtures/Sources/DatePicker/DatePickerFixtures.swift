// DatePicker fixtures: the macOS field with a stepper (default), the displayed components,
// hidden labels, a range, disabled, the compact/field/stepperField styles, the graphical
// calendar and clock, and a behaviour fixture whose date follows the model. Every fixture pins
// the time zone to UTC (the shown date is local time) and the locale to en_US.
import SwiftUI
import FixtureKit

/// Drives `datepicker/steps`.
@Observable
public final class DateModel {
    public var date = DatePickerFixtures.fixed
    public init() {}
}

public enum DatePickerFixtures {
    /// 15 March 2025, 15:09 UTC.
    public static let fixed = Date(timeIntervalSinceReferenceDate: 763744140)
    static let utc = TimeZone(identifier: "UTC")!

    public static let basic = Fixture("datepicker/basic", size: CGSize(width: 360, height: 320)) {
        VStack(alignment: .leading, spacing: 12) {
            DatePicker("Date", selection: .constant(fixed), displayedComponents: .date).probe("date")
            DatePicker("When", selection: .constant(fixed)).probe("dateTime")
            DatePicker("Time", selection: .constant(fixed), displayedComponents: .hourAndMinute).probe("time")
            DatePicker("Date", selection: .constant(fixed), displayedComponents: .date).labelsHidden().probe("hidden")
            DatePicker("Range", selection: .constant(fixed), in: fixed...fixed.addingTimeInterval(86400 * 30), displayedComponents: .date).probe("range")
            DatePicker("Off", selection: .constant(fixed), displayedComponents: .date).disabled(true).probe("disabled")
            HStack(spacing: 8) {
                Text("Row").probe("rowLabel")
                DatePicker("Date", selection: .constant(fixed), displayedComponents: .date).labelsHidden().probe("rowPicker")
                Button("OK") {}.probe("rowButton")
            }
            .probe("row")
        }
        .padding(20)
        .environment(\.timeZone, utc)
        .probe("stack")
    }

    public static let styles = Fixture("datepicker/styles", size: CGSize(width: 360, height: 240)) {
        VStack(alignment: .leading, spacing: 12) {
            DatePicker("Compact", selection: .constant(fixed), displayedComponents: .date).datePickerStyle(.compact).probe("compact")
            DatePicker("Field", selection: .constant(fixed), displayedComponents: .date).datePickerStyle(.field).probe("field")
            DatePicker("Stepper", selection: .constant(fixed), displayedComponents: .date).datePickerStyle(.stepperField).probe("stepper")
            DatePicker("Both", selection: .constant(fixed)).datePickerStyle(.field).probe("fieldBoth")
            DatePicker("Clock", selection: .constant(fixed), displayedComponents: .hourAndMinute).datePickerStyle(.compact).probe("compactTime")
        }
        .padding(20)
        .environment(\.timeZone, utc)
        .probe("stack")
    }

    public static let graphical = Fixture("datepicker/graphical", size: CGSize(width: 360, height: 300)) {
        DatePicker("Calendar", selection: .constant(fixed), displayedComponents: .date).datePickerStyle(.graphical)
            .padding(20)
            .environment(\.timeZone, utc)
            .probe("calendar")
    }

    public static let clock = Fixture("datepicker/clock", size: CGSize(width: 360, height: 240)) {
        DatePicker("Clock", selection: .constant(fixed), displayedComponents: .hourAndMinute).datePickerStyle(.graphical)
            .padding(20)
            .environment(\.timeZone, utc)
            .probe("clock")
    }

    public static let steps = Fixture(
        "datepicker/steps", size: CGSize(width: 360, height: 120),
        model: { DateModel() },
        steps: [
            FixtureStep("nextDay") { $0.date = DatePickerFixtures.fixed.addingTimeInterval(86400) },
            FixtureStep("newYear") { $0.date = Date(timeIntervalSinceReferenceDate: 788918400 + 12 * 3600) },
        ]
    ) { model in
        VStack(alignment: .leading, spacing: 12) {
            DatePicker("Date", selection: Binding(get: { model.date }, set: { model.date = $0 })).probe("picker")
            Text("Echo").probe("echo")
        }
        .padding(20)
        .environment(\.timeZone, utc)
        .probe("stack")
    }

    public static let all: [Fixture] = [basic, styles, graphical, clock, steps]
}
