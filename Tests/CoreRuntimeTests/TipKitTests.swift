// TipKit: tips show once TipKit is configured and their rules hold, the close button and actions
// work, display counts and the display frequency hold tips back, and parameters and donations
// persist in the user defaults.
#if !os(WASI)
import Foundation
import Testing
import SwiftUI
import SwiftUIWebCore
import SwiftUIWebHeadless
import TipKit

private struct FavoriteTip: Tip {
    var title: Text { Text("Save as favorite") }
    var message: Text? { Text("Tap the heart to keep this recipe.") }
    var image: Image? { Image(systemName: "heart") }
}

private struct LoggedInTip: Tip {
    @Parameter
    static var isLoggedIn: Bool = false

    var title: Text { Text("Sync your recipes") }
    var rules: [Rule] {
        #Rule(Self.$isLoggedIn) { $0 == true }
    }
}

private struct ShareTip: Tip {
    static let didViewRecipe = Tips.Event(id: "didViewRecipe")

    var title: Text { Text("Share a recipe") }
    var rules: [Rule] {
        #Rule(Self.didViewRecipe) { $0.donations.count >= 2 }
    }
    var actions: [Action] {
        Action(id: "share", title: "Share now")
        Action(id: "later", title: "Later")
    }
}

private struct OnceTip: Tip {
    var title: Text { Text("Only once") }
    var options: [Option] { MaxDisplayCount(1) }
}

private struct UrgentTip: Tip {
    var title: Text { Text("Urgent") }
    var options: [Option] { IgnoresDisplayFrequency(true) }
}

@Suite(.serialized) @MainActor
struct TipKitTests {
    let defaults: UserDefaults

    init() {
        defaults = UserDefaults(suiteName: "TipKitTests")!
        _TipStoreTestHook.reset(defaults)
    }

    private func render(_ view: some View) -> Runtime {
        let runtime = Runtime()
        runtime.textEngine = MetricsTextEngine()
        runtime.mount(view)
        runtime.layout(in: CGSize(width: 390, height: 700))
        _ = runtime.render(scale: 2)
        return runtime
    }

    private func refresh(_ runtime: Runtime) -> [String] {
        runtime.flush()
        runtime.layout(in: CGSize(width: 390, height: 700))
        _ = runtime.render(scale: 2)
        return runtime.semanticsTree().map(\.label)
    }

    @Test func aTipShowsOnceTipKitIsConfiguredAndClosesForGood() throws {
        let tip = FavoriteTip()
        #expect(tip.status == .pending)
        let runtime = render(VStack { TipView(tip); Text("Recipe") })
        #expect(!runtime.semanticsTree().map(\.label).contains("Save as favorite"))
        try Tips.configure()
        #expect(tip.shouldDisplay)
        let labels = refresh(runtime)
        #expect(labels.contains("Save as favorite"))
        #expect(labels.contains("Tap the heart to keep this recipe."))
        let close = try #require(runtime.semanticsTree().first { $0.label == "Close" })
        runtime.activate(semanticsIdentifier: close.identifier)
        #expect(tip.status == .invalidated(.tipClosed))
        #expect(!refresh(runtime).contains("Save as favorite"))
        #expect(throws: TipKitError.tipsDatastoreAlreadyConfigured) { try Tips.configure() }
    }

    @Test func aParameterRuleWaitsForItsValueAndTheValuePersists() throws {
        try Tips.configure()
        let tip = LoggedInTip()
        #expect(tip.status == .pending)
        LoggedInTip.isLoggedIn = true
        #expect(LoggedInTip.isLoggedIn)
        #expect(tip.status == .available)
        // The value is in the defaults: a new launch reads it back.
        _TipStoreTestHook.reload(defaults)
        try Tips.configure()
        #expect(LoggedInTip.isLoggedIn)
        #expect(tip.status == .available)
    }

    @Test func anEventRuleCountsDonationsAndActionsReachTheHandler() throws {
        try Tips.configure([.displayFrequency(.immediate)])
        let tip = ShareTip()
        ShareTip.didViewRecipe.donate()
        #expect(tip.status == .pending)
        ShareTip.didViewRecipe.donate()
        #expect(ShareTip.didViewRecipe.donations.count == 2)
        #expect(ShareTip.didViewRecipe.donations.donatedWithin(.day).count == 2)
        #expect(tip.status == .available)
        var performed: [String] = []
        let runtime = render(TipView(tip) { performed.append($0.id) })
        let share = try #require(runtime.semanticsTree().first { $0.label == "Share now" })
        runtime.activate(semanticsIdentifier: share.identifier)
        #expect(performed == ["share"])
    }

    @Test func aTipWithMaxDisplayCountStaysWhileShownThenInvalidates() throws {
        try Tips.configure()
        let tip = OnceTip()
        let runtime = render(VStack { TipView(tip) })
        #expect(runtime.semanticsTree().map(\.label).contains("Only once"))
        #expect(tip.status == .available)
        _TipStoreTestHook.endAllDisplays(of: tip.id)
        #expect(tip.status == .invalidated(.displayCountExceeded))
    }

    @Test func theDisplayFrequencyHoldsANewTipBack() throws {
        try Tips.configure([.displayFrequency(.daily)])
        let runtime = render(VStack { TipView(FavoriteTip()) })
        #expect(runtime.semanticsTree().map(\.label).contains("Save as favorite"))
        // Another tip that has not shown waits for tomorrow, unless it ignores the frequency.
        #expect(OnceTip().status == .pending)
        #expect(UrgentTip().status == .available)
        // The tip already on screen keeps showing.
        #expect(FavoriteTip().status == .available)
    }

    @Test func testingModesOverrideTheRules() throws {
        Tips.showAllTipsForTesting()
        #expect(LoggedInTip().status == .available)
        Tips.hideTipsForTesting([LoggedInTip.self])
        #expect(LoggedInTip().status == .pending)
        Tips.hideAllTipsForTesting()
        #expect(FavoriteTip().status == .pending)
    }

    @Test func statusUpdatesFollowTheTip() async throws {
        try Tips.configure()
        let tip = FavoriteTip()
        var iterator = tip.statusUpdates.makeAsyncIterator()
        #expect(await iterator.next() == .available)
        tip.invalidate(reason: .actionPerformed)
        #expect(await iterator.next() == .invalidated(.actionPerformed))
        await tip.resetEligibility()
        #expect(await iterator.next() == .available)
    }

    @Test func aPopoverTipPresentsFromItsView() throws {
        try Tips.configure()
        let runtime = render(Text("Settings").popoverTip(FavoriteTip(), arrowEdge: .bottom))
        let labels = refresh(runtime)
        #expect(labels.contains("Settings"))
        #expect(labels.contains("Save as favorite"))
    }
}
#endif
