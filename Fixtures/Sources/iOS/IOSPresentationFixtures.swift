// iOS presentation fixtures (`ios/sheet/`, `ios/alert/`, `ios/dialog/`, `ios/tabs/`,
// `ios/datepicker/`, `ios/list/selection`, `ios/representable/sheet`): the sheet, alert and confirmation dialog captured
// as the whole iPhone window after a step presents them, the tab bar, the compact date picker's
// pills and a list's selection, rendered on the iPhone SE simulator (decision 0015) and
// reproduced by the runtime's iOS profile (Docs/elements/iOS.md). The presenting screens are
// white (`Color.white` behind the button): the glass materials blur what is behind them, and
// the goldens must show them over an app's white, not the harness window's clear.
import SwiftUI
import FixtureKit

@Observable
public final class IOSPresentationModel {
    public var sheet = false
    public var alert = false
    public var dialog = false
    public var tab = 0
    public var selection: Int?
    public init() {}
}

private struct SheetBody: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 12) {
            Text("Sheet title").font(.headline)
            Text("Some content under the title.")
            Button("Done") { dismiss() }
        }
        
    }
}

public enum IOSPresentationFixtures {
    static let phone = CGSize(width: 375, height: 667)
    static let utc = TimeZone(secondsFromGMT: 0)!
    /// Four hours before the shared fixture date: 11:09 AM, a two-digit hour, because iOS 26
    /// sizes a compact picker's time pill for the wider of its own time and the current time
    /// (`Docs/elements/UIKit/DatePicker.md`), so a one-digit hour would vary by the time of day.
    static let fixed = DatePickerFixtures.fixed.addingTimeInterval(-4 * 3600)

    /// The default sheet (large detent): the dimmed window, the card's top corners and inset.
    public static let sheet = Fixture(
        "ios/sheet/basic", size: phone,
        model: { IOSPresentationModel() },
        steps: [FixtureStep("present") { $0.sheet = true }]
    ) { model in
        ZStack {
            Color.white.ignoresSafeArea()
            Button("Show sheet") { model.sheet = true }.probe("button")
        }
        .sheet(isPresented: Binding(get: { model.sheet }, set: { model.sheet = $0 })) { SheetBody() }
        .probe("stack")
    }.platform(.iOS).capturesWindow()

    /// A medium detent and a hidden drag indicator's opposite: the visible grabber.
    public static let sheetMedium = Fixture(
        "ios/sheet/medium", size: phone,
        model: { IOSPresentationModel() },
        steps: [FixtureStep("present") { $0.sheet = true }]
    ) { model in
        ZStack {
            Color.white.ignoresSafeArea()
            Button("Show sheet") { model.sheet = true }.probe("button")
        }
        .sheet(isPresented: Binding(get: { model.sheet }, set: { model.sheet = $0 })) {
            SheetBody().presentationDetents([.medium]).presentationDragIndicator(.visible)
        }
        .probe("stack")
    }.platform(.iOS).capturesWindow()

    #if canImport(UIKit)
    /// A representable inside a sheet (ix-containers left it here): the UIKit label sits in
    /// the sheet's content like any leaf.
    public static let sheetRepresentable = Fixture(
        "ios/representable/sheet", size: phone,
        model: { IOSPresentationModel() },
        steps: [FixtureStep("present") { $0.sheet = true }]
    ) { model in
        ZStack {
            Color.white.ignoresSafeArea()
            Button("Show sheet") { model.sheet = true }.probe("button")
        }
        .sheet(isPresented: Binding(get: { model.sheet }, set: { model.sheet = $0 })) {
            VStack(spacing: 12) {
                Text("Above")
                LabelBox(text: "UILabel in a sheet", hugging: 1000, resistance: 1000)
                Text("Below")
            }
            
        }
        .probe("stack")
    }.platform(.iOS).capturesWindow()
    #endif

    /// The alert: title, message, a destructive and a cancel button.
    public static let alert = Fixture(
        "ios/alert/basic", size: phone,
        model: { IOSPresentationModel() },
        steps: [FixtureStep("present") { $0.alert = true }]
    ) { model in
        ZStack {
            Color.white.ignoresSafeArea()
            Button("Delete…") { model.alert = true }.probe("button")
        }
        .alert("Delete the item?", isPresented: Binding(get: { model.alert }, set: { model.alert = $0 })) {
            Button("Delete", role: .destructive) {}
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone.")
        }
        .probe("stack")
    }.platform(.iOS).capturesWindow()

    /// The confirmation dialog: a titled action sheet with three actions and a cancel button.
    public static let dialog = Fixture(
        "ios/dialog/basic", size: phone,
        model: { IOSPresentationModel() },
        steps: [FixtureStep("present") { $0.dialog = true }]
    ) { model in
        ZStack {
            Color.white.ignoresSafeArea()
            Button("Options…") { model.dialog = true }.probe("button")
        }
        .confirmationDialog("Item options", isPresented: Binding(get: { model.dialog }, set: { model.dialog = $0 }), titleVisibility: .visible) {
            Button("Copy") {}
            Button("Duplicate") {}
            Button("Delete", role: .destructive) {}
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Choose what to do with the item.")
        }
        .probe("stack")
    }.platform(.iOS).capturesWindow()

    /// The tab bar: three tabs with symbols, the first selected. No step selects another: a
    /// programmatic selection change leaves iOS 26's pill raised as glass for seconds, so
    /// `ios/tabs/second` starts on the second tab instead.
    public static let tabs = Fixture("ios/tabs/basic", size: phone) {
        TabView(selection: .constant(0)) {
            Text("Home content").probe("home").tabItem { Label("Home", systemImage: "house") }.tag(0)
            Text("Search content").tabItem { Label("Search", systemImage: "magnifyingglass") }.tag(1)
            Text("Settings content").tabItem { Label("Settings", systemImage: "gear") }.tag(2)
        }
        .probe("tabs")
    }.platform(.iOS).capturesWindow()

    public static let tabsSecond = Fixture("ios/tabs/second", size: phone) {
        TabView(selection: .constant(1)) {
            Text("Home content").tabItem { Label("Home", systemImage: "house") }.tag(0)
            Text("Search content").probe("search").tabItem { Label("Search", systemImage: "magnifyingglass") }.tag(1)
            Text("Settings content").tabItem { Label("Settings", systemImage: "gear") }.tag(2)
        }
        .probe("tabs")
    }.platform(.iOS).capturesWindow()

    /// Five tabs with badges: a count on the second, a text on the fourth (the bar's slots
    /// narrow; badges sit on the symbols).
    public static let tabsBadges = Fixture("ios/tabs/badges", size: phone) {
        TabView(selection: .constant(0)) {
            Tab("Home", systemImage: "house", value: 0) { Text("Home content").probe("home") }
            Tab("Alerts", systemImage: "bell", value: 1) { Text("Alerts content") }.badge(3)
            Tab("Search", systemImage: "magnifyingglass", value: 2) { Text("Search content") }
            Tab("Mail", systemImage: "envelope", value: 3) { Text("Mail content") }.badge("New")
            Tab("More", systemImage: "ellipsis", value: 4) { Text("More content") }
        }
        .probe("tabs")
    }.platform(.iOS).capturesWindow()

    /// The page style on iPhone: three pages, the page indicator at the bottom.
    public static let tabsPage = Fixture("ios/tabs/page", size: phone) {
        TabView(selection: .constant(1)) {
            Color.red.frame(width: 120, height: 80).tag(0)
            Color.blue.frame(width: 120, height: 80).probe("page1").tag(1)
            Color.green.frame(width: 120, height: 80).tag(2)
        }
        .fixturePageTabStyle()
        .probe("tabs")
    }.platform(.iOS).capturesWindow()

    /// The compact date picker in a form: date, date and time, time; the tinted pills.
    public static let datePicker = Fixture("ios/datepicker/compact", size: CGSize(width: 375, height: 360)) {
        Form {
            DatePicker("Date", selection: .constant(fixed), displayedComponents: .date).probe("date")
            DatePicker("When", selection: .constant(fixed)).probe("dateTime")
            DatePicker("Time", selection: .constant(fixed), displayedComponents: .hourAndMinute).probe("time")
            DatePicker("Off", selection: .constant(fixed), displayedComponents: .date).disabled(true).probe("disabled")
        }
        .environment(\.timeZone, utc)
        .probe("form")
    }.platform(.iOS)

    /// A list with a selection binding: the selected row's look after a step selects it.
    /// The wheel style (iOS only): the date's three columns and the time's, captured as the window.
    public static let dateWheel = Fixture("ios/datepicker/wheel", size: CGSize(width: 375, height: 520)) {
        VStack(spacing: 12) {
            DatePicker("Date", selection: .constant(fixed), displayedComponents: .date).fixtureWheelDateStyle().labelsHidden().probe("dateWheel")
            DatePicker("Time", selection: .constant(fixed), displayedComponents: .hourAndMinute).fixtureWheelDateStyle().labelsHidden().probe("timeWheel")
        }
        .environment(\.timeZone, utc)
        .probe("stack")
    }.platform(.iOS).capturesWindow()

    public static let listSelection = Fixture(
        "ios/list/selection", size: CGSize(width: 375, height: 360),
        model: { IOSPresentationModel() },
        steps: [FixtureStep("select") { $0.selection = 2 }]
    ) { model in
        List(selection: Binding(get: { model.selection }, set: { model.selection = $0 })) {
            Text("First").tag(1).probe("first")
            Text("Second").tag(2).probe("second")
            Text("Third").tag(3).probe("third")
        }
        .probe("list")
    }.platform(.iOS)

    public static var all: [Fixture] {
        var fixtures = [sheet, sheetMedium, alert, dialog, tabs, tabsSecond, tabsBadges, tabsPage, datePicker, listSelection]
        #if canImport(UIKit)
        fixtures.append(sheetRepresentable)
        #endif
        fixtures.append(dateWheel)
        return fixtures
    }
}
