// The declarations the IntentDefinitions plugin writes from Base.lproj/Widgets.intentdefinition,
// as Xcode generates them for a widget's configuration (Dime's budget and insights widgets):
// an intent's parameters (an object, an enum, a Boolean, several strings), its response codes,
// its handling protocol with the options provider, a custom type and an enum, and the intent in
// an `IntentConfiguration`.
import Testing
import SwiftUI
import Intents
import WidgetKit

#if !os(WASI)
private struct BudgetEntry: TimelineEntry {
    let date: Date
    let configuration: BudgetConfigurationIntent
}

private struct BudgetProvider: IntentTimelineProvider {
    func placeholder(in context: Context) -> BudgetEntry { BudgetEntry(date: Date(timeIntervalSince1970: 0), configuration: BudgetConfigurationIntent()) }
    func getSnapshot(for configuration: BudgetConfigurationIntent, in context: Context, completion: @escaping (BudgetEntry) -> Void) {
        completion(BudgetEntry(date: Date(timeIntervalSince1970: 0), configuration: configuration))
    }
    func getTimeline(for configuration: BudgetConfigurationIntent, in context: Context, completion: @escaping (Timeline<BudgetEntry>) -> Void) {
        completion(Timeline(entries: [BudgetEntry(date: Date(timeIntervalSince1970: 0), configuration: configuration)], policy: .never))
    }
}

/// An Intents extension's handler, as Dime's lists its budgets.
private final class BudgetHandler: INExtension, BudgetConfigurationIntentHandling {
    override func handler(for _: INIntent) -> Any { self }
    func provideBudgetOptionsCollection(for intent: BudgetConfigurationIntent, with completion: @escaping (INObjectCollection<Budget>?, (any Error)?) -> Void) {
        completion(INObjectCollection(items: [Budget(identifier: "food", display: "Food"), Budget(identifier: "rent", display: "Rent")]), nil)
    }
}

@Suite struct IntentDefinitionsTests {
    @Test func anIntentHasItsParametersUnsetAtFirst() {
        let intent = BudgetConfigurationIntent()
        #expect(intent.budget == nil && intent.period == .unknown && intent.showsIncome == nil && intent.categories == nil)
        intent.budget = Budget(identifier: "food", display: "Food")
        intent.budget?.amount = 120
        intent.period = .month
        intent.showsIncome = true
        intent.categories = ["Groceries", "Dining"]
        #expect(intent.budget?.displayString == "Food" && intent.budget?.amount?.intValue == 120)
        #expect(intent.period.rawValue == 2 && intent.showsIncome?.boolValue == true && intent.categories?.count == 2)
        // An intent with no parameters, as Clendar's `ConfigurationIntent`.
        _ = ConfigurationIntent()
    }

    @Test func theEnumAndTheResponseCodesAreXcodesNumbers() {
        #expect(Period.allCases.map(\.rawValue) == [0, 1, 2])
        #expect(BudgetConfigurationIntentResponse.Code.success.rawValue == 4)
        #expect(BudgetConfigurationIntentResponse.Code.overBudget.rawValue == 100)
        let response = BudgetConfigurationIntentResponse(code: .failure, userActivity: nil)
        #expect(response.code == .failure)
    }

    @Test func aHandlerListsTheOptionsAndTheRestHaveDefaults() {
        let handler = BudgetHandler()
        #expect(handler.handler(for: BudgetConfigurationIntent()) as? BudgetHandler === handler)
        var names: [String] = []
        handler.provideBudgetOptionsCollection(for: BudgetConfigurationIntent()) { collection, _ in
            names = collection?.allItems.map(\.displayString) ?? []
        }
        #expect(names == ["Food", "Rent"])
        var code: BudgetConfigurationIntentResponse.Code?
        handler.handle(intent: BudgetConfigurationIntent()) { code = $0.code }
        #expect(code == .success)
    }

    @MainActor @Test func theIntentConfiguresAWidget() {
        let configuration = IntentConfiguration(kind: "Budget", intent: BudgetConfigurationIntent.self, provider: BudgetProvider()) { entry in
            Text(entry.configuration.budget?.displayString ?? "No budget")
        }
        #expect(configuration.kind == "Budget")
        #expect(configuration._view(for: BudgetEntry(date: Date(), configuration: BudgetConfigurationIntent())) != nil)
    }
}
#endif
