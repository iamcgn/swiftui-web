// Dark appearance (Docs/elements/UIKit/Dark.md): light fixtures rendered again with the window's
// interface style dark, so the system colours' dark values, the bars' and cards' dark looks and
// the controls' dark tints are measured against UIKit on the simulator.
#if canImport(UIKit)
import UIKit
import UIKitFixtureKit

public enum DarkFixtures {
    public static let all = [table, plainTable, controls, navigation, alert, list, textView, toolbar, search, tabs, datePicker, buttons, basicControls,
                             inline, calendar, wheels, materials, pageSheet, popover, refresh, imageTints, looks]

    public static let table = TableFixtures.grouped.renamed("uikit/dark/table").style(.dark)
    public static let plainTable = TableFixtures.plain.renamed("uikit/dark/plaintable").style(.dark)
    public static let controls = MoreControlFixtures.controls.renamed("uikit/dark/controls").style(.dark)
    public static let navigation = NavigationFixtures.basic.renamed("uikit/dark/nav").style(.dark)
    public static let alert = PresentationFixtures.alert.renamed("uikit/dark/alert").style(.dark)
    public static let list = CollectionFixtures.list.renamed("uikit/dark/list").style(.dark)
    public static let textView = TextViewFixtures.basic.renamed("uikit/dark/textview").style(.dark)
    public static let toolbar = BarFixtures.toolbar.renamed("uikit/dark/toolbar").style(.dark)
    public static let search = BarFixtures.search.renamed("uikit/dark/search").style(.dark)
    public static let tabs = NavigationFixtures.tabs.renamed("uikit/dark/tabs").style(.dark)
    public static let datePicker = DatePickerFixtures.compact.renamed("uikit/dark/datepicker").style(.dark)
    public static let buttons = ButtonFixtures.basic.renamed("uikit/dark/buttons").style(.dark)
    public static let basicControls = ControlFixtures.basic.renamed("uikit/dark/basiccontrols").style(.dark)
    // 2026-10-09 (uk-traits): the inline calendar and the calendar view, the wheels, the
    // materials, a sheet and a popover, the refresh control, image tints and the layer looks.
    public static let inline = DatePickerFixtures.inlineTime.renamed("uikit/dark/inline").style(.dark)
    public static let calendar = DatePickerFixtures.calendar.renamed("uikit/dark/calendar").style(.dark)
    public static let wheels = DatePickerFixtures.wheels.renamed("uikit/dark/wheels").style(.dark)
    public static let materials = MaterialFixtures.materials.renamed("uikit/dark/materials").style(.dark)
    public static let pageSheet = PresentationFixtures.pageSheet.renamed("uikit/dark/sheet").style(.dark)
    public static let popover = PresentationFixtures.popover.renamed("uikit/dark/popover").style(.dark)
    public static let refresh = RefreshFixtures.refresh.renamed("uikit/dark/refresh").style(.dark)
    public static let imageTints = ImageFixtures.tints.renamed("uikit/dark/imagetints").style(.dark)
    public static let looks = LookFixtures.looks.renamed("uikit/dark/looks").style(.dark)
}
#endif
