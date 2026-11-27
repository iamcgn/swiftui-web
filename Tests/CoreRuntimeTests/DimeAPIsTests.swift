// SwiftUI forms Dime and Gem call that draw nothing of their own here: iOS 26's scroll edge
// effects (the scroll views draw none), a widget's tap URL on its view, and the toolbar's title
// placements, which lay out as principal items.
import Testing
import SwiftUI
import SwiftUIWebCore
import SwiftUIWebHeadless

#if !os(WASI)
@Suite @MainActor struct DimeAPIsTests {
    private func drawn<V: View>(_ view: V) -> [String] {
        let runtime = Runtime()
        runtime.mount(view)
        runtime.layout(in: CGSize(width: 320, height: 300))
        return runtime.render(scale: 2).commands.map(\.description)
    }

    @Test func scrollEdgeEffectsAndAWidgetURLDrawTheViewAsItIs() {
        let plain = drawn(ScrollView { Text("Budgets") })
        let styled = drawn(ScrollView { Text("Budgets").widgetURL(URL(string: "dime://budgets")) }
            .scrollEdgeEffectStyle(.soft, for: .top)
            .scrollEdgeEffectHidden(for: .bottom))
        #expect(styled == plain)
        #expect(ScrollEdgeEffectStyle.soft != .hard && ScrollEdgeEffectStyle.automatic == .automatic)
    }

    @Test func theTitlePlacementsAreTheirOwnPrincipalPlaces() {
        #expect(ToolbarItemPlacement.title != .principal && ToolbarItemPlacement.subtitle != .title)
        #expect(ToolbarItemPlacement.title.iOSGroup == ToolbarItemPlacement.principal.iOSGroup)
    }
}
#endif
