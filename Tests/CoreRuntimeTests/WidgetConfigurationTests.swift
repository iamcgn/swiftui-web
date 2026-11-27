// A widget's own types (WidgetKit's Widgets.swift), as Dime's widget files declare them: a widget
// with a static configuration and its gallery name, description and sizes, a bundle of widgets,
// and the provider context a preview asks with. The configuration keeps the entry view, so a
// widget's view draws for an entry here as a preview would show it.
import Testing
import SwiftUI
import SwiftUIWebCore
import SwiftUIWebHeadless
import WidgetKit

#if !os(WASI)
private struct BudgetEntry: TimelineEntry {
    let date: Date
    let left: Int
}

private struct OtherEntry: TimelineEntry {
    let date: Date
}

private struct BudgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> BudgetEntry { BudgetEntry(date: Date(timeIntervalSince1970: 0), left: 120) }
    func getSnapshot(in context: Context, completion: @escaping (BudgetEntry) -> Void) { completion(placeholder(in: context)) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<BudgetEntry>) -> Void) {
        completion(Timeline(entries: [placeholder(in: context)], policy: .atEnd))
    }
}

private struct BudgetWidget: Widget {
    let kind = "BudgetWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: BudgetProvider()) { entry in
            Text("\(entry.left) left").widgetURL(URL(string: "dime://budget"))
        }
        .configurationDisplayName("Budget")
        .description(Text("Your budget at a glance."))
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}

private struct InsightsWidget: Widget {
    var showsChart = true
    var body: some WidgetConfiguration {
        if showsChart {
            StaticConfiguration(kind: "Insights", provider: BudgetProvider()) { Text("\($0.left)") }
        }
    }
}

private struct DimeWidgets: WidgetBundle {
    var body: some Widget {
        BudgetWidget()
        InsightsWidget()
    }
}

@Suite @MainActor struct WidgetConfigurationTests {
    @Test func aConfigurationKeepsWhatItsModifiersSet() throws {
        let info = try #require(BudgetWidget().body._widgetInfo)
        #expect(info.displayName == "Budget")
        #expect(info.description == "Your budget at a glance.")
        #expect(info.supportedFamilies == [.systemSmall, .systemMedium])
        #expect(info.contentMarginsDisabled)
        // A configuration with no modifiers comes in every size.
        let plain = StaticConfiguration(kind: "Plain", provider: BudgetProvider()) { Text("\($0.left)") }
        #expect(plain.kind == "Plain" && plain._info.supportedFamilies == WidgetFamily.allCases && plain._info.displayName == nil)
        // An `if` in a body builds; a bundle lists its widgets.
        _ = InsightsWidget(showsChart: false).body
        _ = DimeWidgets().body
    }

    @Test func aConfigurationDrawsItsViewForAnEntryOfItsProvider() throws {
        let configuration = StaticConfiguration(kind: "Budget", provider: BudgetProvider()) { entry in
            Text("\(entry.left) left").widgetURL(URL(string: "dime://budget"))
        }
        #expect(configuration._view(for: OtherEntry(date: Date())) == nil)
        let view = try #require(configuration._placeholderView())
        let runtime = Runtime()
        runtime.mount(view)
        runtime.layout(in: CGSize(width: 170, height: 170))
        let drawn = runtime.render(scale: 2).commands.map(\.description).filter { $0.hasPrefix("drawText(\"") }
        #expect(drawn.count == 1 && drawn.first?.hasPrefix("drawText(\"120 left\"") == true)
    }

    @Test func aPreviewContextIsASmallWidgetsUnlessToldOtherwise() {
        let small = TimelineProviderContext()
        #expect(small.family == .systemSmall && small.isPreview && small.displaySize == CGSize(width: 170, height: 170))
        let medium = TimelineProviderContext(family: .systemMedium, isPreview: false)
        #expect(medium.displaySize == CGSize(width: 364, height: 170) && !medium.isPreview)
        var entries: [BudgetEntry] = []
        BudgetProvider().getTimeline(in: medium) { entries = $0.entries }
        #expect(entries.map(\.left) == [120])
    }
}
#endif
